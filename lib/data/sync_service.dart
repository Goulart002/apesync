import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_data.dart';
import 'local_db.dart';

enum EstadoSync { semInternet, sincronizando, pendente, sincronizado, erro }

/// Sincronização SQLite (celular) <-> Supabase (nuvem), estilo WhatsApp:
///
/// 1. PUSH: envia as linhas com `pendente = 1` (upsert) e as marca como
///    sincronizadas.
/// 2. PULL: baixa só o que mudou no servidor desde o último download
///    (`synced_at > última marca`) e grava no SQLite.
/// 3. Conflito (mesmo registro alterado em dois celulares): vence a
///    alteração com o `updated_at` mais recente ("last write wins").
///
/// Roda: ao abrir o app, ao voltar a internet, após cada alteração local,
/// a cada 60 s e quando o Realtime avisa que outro morador mudou algo.
class SyncService extends ChangeNotifier {
  SyncService._();
  static final SyncService instance = SyncService._();

  EstadoSync estado = EstadoSync.sincronizado;
  int pendentes = 0;
  DateTime? ultimaSync;
  String? ultimoErro;

  StreamSubscription<List<ConnectivityResult>>? _conexao;
  Timer? _timer;
  RealtimeChannel? _canal;
  String? _canalCasaId;
  bool _rodando = false;
  bool _deNovo = false;

  SupabaseClient get _sb => Supabase.instance.client;

  void iniciar() {
    parar();
    _conexao = Connectivity().onConnectivityChanged.listen((r) {
      if (r.contains(ConnectivityResult.none) || r.isEmpty) {
        _mudar(EstadoSync.semInternet);
      } else {
        sincronizar();
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => sincronizar());
    sincronizar(reiniciarRealtime: true);
  }

  void parar() {
    _conexao?.cancel();
    _conexao = null;
    _timer?.cancel();
    _timer = null;
    _pararRealtime();
  }

  void _mudar(EstadoSync novo) {
    estado = novo;
    notifyListeners();
  }

  Future<bool> _temInternet() async {
    final r = await Connectivity().checkConnectivity();
    return r.isNotEmpty && !r.contains(ConnectivityResult.none);
  }

  /// Pode ser chamado a qualquer momento; se já estiver rodando, agenda
  /// mais uma rodada no fim (nada se perde).
  Future<void> sincronizar({bool reiniciarRealtime = false}) async {
    final data = AppData.instance;
    final db = data.db;
    final casa = data.casa;
    if (db == null || casa == null || _sb.auth.currentUser == null) return;

    if (_rodando) {
      _deNovo = true;
      return;
    }
    _rodando = true;
    try {
      if (!await _temInternet()) {
        estado = EstadoSync.semInternet;
        return;
      }
      if (reiniciarRealtime || _canalCasaId != casa.id) _assinarRealtime(casa.id);

      _mudar(EstadoSync.sincronizando);
      var mudou = false;
      do {
        _deNovo = false;
        await _push(db);
        mudou = await _pull(db, casa.id) || mudou;
      } while (_deNovo);

      if (mudou) await data.recarregar();
      ultimaSync = DateTime.now();
      ultimoErro = null;
      estado = EstadoSync.sincronizado;
    } catch (e) {
      ultimoErro = e.toString();
      estado = await _temInternet() ? EstadoSync.erro : EstadoSync.semInternet;
      debugPrint('Sync falhou: $e');
    } finally {
      _rodando = false;
      pendentes = await data.contarPendentes();
      if (pendentes > 0 && estado == EstadoSync.sincronizado) {
        estado = EstadoSync.pendente;
      }
      notifyListeners();
    }
  }

  /// Envia ao Supabase tudo que está pendente, na ordem das chaves
  /// estrangeiras (casa antes de morador, morador antes de gasto...).
  Future<void> _push(Database db) async {
    for (final t in LocalDb.tabelas) {
      final linhas = await db.query(t, where: 'pendente = 1');
      if (linhas.isEmpty) continue;

      await _sb
          .from(t)
          .upsert(linhas.map((l) => LocalDb.paraRemoto(t, l)).toList());

      // Só desmarca se ninguém alterou a linha durante o envio.
      for (final l in linhas) {
        await db.update(t, {'pendente': 0},
            where: 'id = ? AND updated_at = ?',
            whereArgs: [l['id'], l['updated_at']]);
      }
    }
  }

  /// Baixa o que mudou no servidor desde o último download.
  /// Retorna true se alguma linha local mudou.
  Future<bool> _pull(Database db, String casaId) async {
    var mudou = false;
    for (final t in LocalDb.tabelas) {
      final chave = 'pull_${t}_$casaId';
      final desde =
          await LocalDb.lerMeta(db, chave) ?? '1970-01-01T00:00:00Z';

      final filtro = _sb.from(t).select();
      final rows = await (t == 'casas'
              ? filtro.eq('id', casaId)
              : filtro.eq('casa_id', casaId))
          .gt('synced_at', desde)
          .order('synced_at', ascending: true);
      if (rows.isEmpty) continue;

      for (final remoto in rows) {
        final local = await db.query(t,
            columns: ['pendente', 'updated_at'],
            where: 'id = ?',
            whereArgs: [remoto['id']]);

        // Conflito: a versão local pendente é mais nova -> mantém a local
        // (ela vai subir no próximo push e sobrescrever o servidor).
        if (local.isNotEmpty && local.first['pendente'] == 1) {
          final dataLocal = DateTime.parse(local.first['updated_at'] as String);
          final dataRemota = DateTime.parse(remoto['updated_at'] as String);
          if (dataLocal.isAfter(dataRemota)) continue;
        }

        await db.insert(t, LocalDb.deRemoto(t, remoto),
            conflictAlgorithm: ConflictAlgorithm.replace);
        mudou = true;
      }
      await LocalDb.gravarMeta(db, chave, rows.last['synced_at'] as String);
    }
    return mudou;
  }

  /// Realtime: quando outro celular grava algo desta casa, o Supabase avisa
  /// na hora e a gente faz um pull (como mensagem chegando no WhatsApp).
  void _assinarRealtime(String casaId) {
    _pararRealtime();
    var canal = _sb.channel('casa-$casaId');
    for (final t in ['moradores', 'gastos', 'pagamentos']) {
      canal = canal.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: t,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'casa_id',
          value: casaId,
        ),
        callback: (_) => sincronizar(),
      );
    }
    _canal = canal..subscribe();
    _canalCasaId = casaId;
  }

  void _pararRealtime() {
    final c = _canal;
    _canal = null;
    _canalCasaId = null;
    if (c != null) {
      _sb.removeChannel(c);
    }
  }
}
