import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_data.dart';
import 'local_db.dart';
import 'regras_sync.dart';

enum EstadoSync { semInternet, sincronizando, pendente, sincronizado, erro }

/// Sincronização SQLite (celular) <-> Supabase (nuvem), estilo WhatsApp:
///
/// 1. PUSH: envia as linhas com `pendente = 1` (upsert) e as marca como
///    sincronizadas.
/// 2. PULL: baixa só o que mudou no servidor desde o último download
///    (`synced_at > última marca − 60 s` de margem) e grava no SQLite.
/// 3. Conflito (mesmo registro alterado em dois celulares): vence a
///    alteração com o `updated_at` mais recente ("last write wins"). Quem
///    decide é o servidor (trigger `mais_recente_vence` em schema.sql); no
///    download, o celular aplica a mesma regra (ver [RegrasSync]).
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
      if (reiniciarRealtime || _canalCasaId != casa.id)
        _assinarRealtime(casa.id);

      _mudar(EstadoSync.sincronizando);
      var mudou = false;
      do {
        _deNovo = false;
        mudou = await _push(db, casa.id) || mudou;
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
  /// Retorna true se alguma linha local mudou (descartada ou trocada pela
  /// versão do servidor).
  Future<bool> _push(Database db, String casaId) async {
    var mudou = false;
    for (final t in LocalDb.tabelas) {
      final linhas = await db.query(t, where: 'pendente = 1');
      if (linhas.isEmpty) continue;

      try {
        mudou = await _enviar(db, t, linhas) || mudou;
      } on PostgrestException catch (e) {
        if (!_recusadoPeloServidor(e)) rethrow;
        // Alguma linha foi recusada pelas regras (ex.: a pessoa perdeu a
        // permissão enquanto estava offline). Envia uma por uma: as
        // aceitas sobem, as recusadas são descartadas e voltam a ser a
        // versão do servidor — senão o sync travaria para sempre.
        for (final l in linhas) {
          try {
            mudou = await _enviar(db, t, [l]) || mudou;
          } on PostgrestException catch (e) {
            if (!_recusadoPeloServidor(e)) rethrow;
            debugPrint('Servidor recusou $t ${l['id']}: ${e.message}');
            await LocalDb.descartar(db, t, l['id'] as String, casaId);
            mudou = true;
          }
        }
      }
    }
    return mudou;
  }

  /// Faz o upsert e confere o que o servidor gravou de fato. Uma linha que
  /// não volta na resposta foi IGNORADA pelo servidor por ser mais velha que
  /// a versão dele (trigger mais_recente_vence) — então baixa a versão do
  /// servidor na hora, em vez de continuar mostrando a velha.
  /// Retorna true se trocou alguma linha local pela do servidor.
  Future<bool> _enviar(
      Database db, String t, List<Map<String, Object?>> linhas) async {
    final gravadas = await _sb
        .from(t)
        .upsert(linhas.map((l) => LocalDb.paraRemoto(t, l)).toList())
        .select('id');
    final aceitas = {for (final r in gravadas) r['id']};
    for (final l in linhas) {
      await _desmarcar(db, t, l);
    }

    final ignoradas = [
      for (final l in linhas)
        if (!aceitas.contains(l['id'])) l['id'] as String,
    ];
    if (ignoradas.isEmpty) return false;
    final doServidor = await _sb.from(t).select().inFilter('id', ignoradas);
    for (final r in doServidor) {
      await db.insert(t, LocalDb.deRemoto(t, r),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    return true;
  }

  /// Só desmarca se ninguém alterou a linha durante o envio.
  Future<void> _desmarcar(Database db, String t, Map<String, Object?> l) =>
      db.update(t, {'pendente': 0},
          where: 'id = ? AND updated_at = ?',
          whereArgs: [l['id'], l['updated_at']]);

  /// 42501 = sem permissão (RLS); P0001 = regra de um trigger (raise).
  bool _recusadoPeloServidor(PostgrestException e) =>
      e.code == '42501' || e.code == 'P0001';

  /// Baixa o que mudou no servidor desde o último download (com uma margem
  /// de segurança, ver [RegrasSync.margem]).
  /// Retorna true se alguma linha local mudou.
  Future<bool> _pull(Database db, String casaId) async {
    var mudou = false;
    for (final t in LocalDb.tabelas) {
      final chave = 'pull_${t}_$casaId';
      final marca = await LocalDb.lerMeta(db, chave);

      final filtro = _sb.from(t).select();
      final rows = await (t == 'casas'
              ? filtro.eq('id', casaId)
              : filtro.eq('casa_id', casaId))
          .gt('synced_at', RegrasSync.desdeComMargem(marca))
          .order('synced_at', ascending: true);
      if (rows.isEmpty) continue;

      for (final r in rows) {
        final remoto = LocalDb.deRemoto(t, r);
        final local = await db.query(t, where: 'id = ?', whereArgs: [r['id']]);
        // Decide quem vence (celular x servidor) e ignora o que já temos.
        if (!RegrasSync.aplicarRemoto(
            local.isEmpty ? null : local.first, remoto)) {
          continue;
        }
        await db.insert(t, remoto,
            conflictAlgorithm: ConflictAlgorithm.replace);
        mudou = true;
      }
      await LocalDb.gravarMeta(db, chave,
          RegrasSync.novaMarca(marca, rows.last['synced_at'] as String));
    }
    return mudou;
  }

  /// Realtime: quando outro celular grava algo desta casa, o Supabase avisa
  /// na hora e a gente faz um pull (como mensagem chegando no WhatsApp).
  void _assinarRealtime(String casaId) {
    _pararRealtime();
    // A própria casa: código de convite novo, troca de administrador...
    var canal = _sb.channel('casa-$casaId').onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'casas',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: casaId,
          ),
          callback: (_) => sincronizar(),
        );
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
