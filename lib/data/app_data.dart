import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'calculos.dart';
import 'local_db.dart';
import 'modelos.dart';
import 'sync_service.dart';

export 'modelos.dart';

/// Repositório do app (padrão "offline-first").
///
/// - Toda LEITURA vem do SQLite local (carregado em memória para as telas).
/// - Toda ESCRITA (criar/editar/excluir) vai primeiro para o SQLite com
///   `pendente = 1` e a tela atualiza na hora, mesmo sem internet.
/// - O [SyncService] envia os pendentes ao Supabase quando houver conexão
///   e baixa o que os outros moradores mudaram.
class AppData extends ChangeNotifier {
  AppData._();
  static final AppData instance = AppData._();

  static const _uuid = Uuid();

  SupabaseClient get _sb => Supabase.instance.client;

  Database? _db;
  String? _uid;

  Casa? casa;
  List<Morador> _moradores = [];
  List<Gasto> _gastos = [];
  List<Pagamento> _pagamentos = [];

  Database? get db => _db;
  String? get usuarioId => _uid;
  bool get aberto => _db != null;
  bool get temCasa => casa != null;

  // ---------------------------------------------------------------------------
  // Leitura
  // ---------------------------------------------------------------------------

  /// Moradores ativos: você primeiro, depois em ordem alfabética.
  List<Morador> get moradores {
    final lista = _moradores.where((m) => !m.deleted).toList()
      ..sort((a, b) {
        if (a.usuarioId == _uid) return -1;
        if (b.usuarioId == _uid) return 1;
        return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
      });
    return lista;
  }

  /// Gastos ativos, do mais recente para o mais antigo.
  List<Gasto> get gastos => _gastos.where((g) => !g.deleted).toList()
    ..sort((a, b) {
      final c = b.data.compareTo(a.data);
      return c != 0 ? c : b.updatedAt.compareTo(a.updatedAt);
    });

  /// Pagamentos ativos, do mais recente para o mais antigo.
  List<Pagamento> get pagamentos => _pagamentos.where((p) => !p.deleted).toList()
    ..sort((a, b) {
      final c = b.data.compareTo(a.data);
      return c != 0 ? c : b.updatedAt.compareTo(a.updatedAt);
    });

  Morador? get meuMorador {
    for (final m in _moradores) {
      if (m.usuarioId == _uid && !m.deleted) return m;
    }
    return null;
  }

  /// Id do morador que é o usuário logado.
  String get euId => meuMorador?.id ?? '';

  String get nomeUsuario {
    final n = meuMorador?.nome ??
        _sb.auth.currentUser?.userMetadata?['nome'] as String? ??
        'Você';
    return n.trim().isEmpty ? 'Você' : n.trim().split(' ').first;
  }

  String get nomeCasa => casa?.nome ?? '';

  /// Procura também entre excluídos (um gasto antigo pode citar um morador
  /// que saiu da casa).
  Morador morador(String id) {
    for (final m in _moradores) {
      if (m.id == id) return m;
    }
    return Morador(id: id, casaId: '', nome: '?', updatedAt: '');
  }

  /// "Você" para o usuário logado, nome para os demais.
  String nomeDe(String moradorId) =>
      moradorId == euId ? 'Você' : morador(moradorId).nome;

  List<Gasto> gastosDoMes(DateTime mes) => gastos
      .where((g) => g.data.year == mes.year && g.data.month == mes.month)
      .toList();

  int totalCentavos(Iterable<Gasto> lista) =>
      lista.fold(0, (s, g) => s + g.valorCentavos);

  int minhaParteCentavos(Iterable<Gasto> lista) =>
      lista.fold(0, (s, g) => s + g.parteDe(euId));

  int saldoDe(String id) => Calculos.saldoDe(id, gastos, pagamentos);
  int saldoCentavos() => saldoDe(euId);

  List<Transferencia> simplificarDividas() => Calculos.simplificar(
      {for (final m in moradores) m.id: saldoDe(m.id)});

  int dividasSemSimplificar() =>
      Calculos.dividasSemSimplificar(gastos, pagamentos);

  bool moradorEmUso(String id) =>
      gastos.any((g) => g.pagoPorId == id || g.divididoEntre.contains(id)) ||
      pagamentos.any((p) => p.deId == id || p.paraId == id);

  // ---------------------------------------------------------------------------
  // Ciclo de vida
  // ---------------------------------------------------------------------------

  /// Abre o banco local do usuário logado e carrega os dados.
  /// Funciona sem internet (a sessão do Supabase fica salva no aparelho).
  Future<void> abrir() async {
    final user = _sb.auth.currentUser;
    if (user == null) throw StateError('Nenhum usuário logado');
    if (_db != null && _uid == user.id) {
      await recarregar();
      return;
    }
    await _db?.close();
    _uid = user.id;
    _db = await LocalDb.abrir(user.id);
    await recarregar();
    SyncService.instance.iniciar();
  }

  /// Relê o SQLite para a memória e avisa as telas.
  Future<void> recarregar() async {
    final db = _db;
    if (db == null) return;
    final casas = await db.query('casas',
        where: 'deleted = 0', orderBy: 'updated_at DESC', limit: 1);
    casa = casas.isEmpty ? null : Casa.fromMap(casas.first);
    if (casa == null) {
      _moradores = [];
      _gastos = [];
      _pagamentos = [];
    } else {
      final args = [casa!.id];
      _moradores = (await db.query('moradores',
              where: 'casa_id = ?', whereArgs: args))
          .map(Morador.fromMap)
          .toList();
      _gastos = (await db.query('gastos', where: 'casa_id = ?', whereArgs: args))
          .map(Gasto.fromMap)
          .toList();
      _pagamentos = (await db.query('pagamentos',
              where: 'casa_id = ?', whereArgs: args))
          .map(Pagamento.fromMap)
          .toList();
    }
    notifyListeners();
  }

  Future<int> contarPendentes() async =>
      _db == null ? 0 : LocalDb.contarPendentes(_db!);

  /// Sai da conta. Os dados continuam no celular (se entrar de novo com a
  /// mesma conta, o que estava pendente ainda sobe).
  Future<void> sair() async {
    SyncService.instance.parar();
    await _db?.close();
    _db = null;
    _uid = null;
    casa = null;
    _moradores = [];
    _gastos = [];
    _pagamentos = [];
    notifyListeners();
    try {
      await _sb.auth.signOut();
    } catch (_) {
      // Sem internet: a sessão local é apagada mesmo assim.
    }
  }

  // ---------------------------------------------------------------------------
  // Escrita local (CREATE / UPDATE / DELETE) — sempre offline-first
  // ---------------------------------------------------------------------------

  /// Grava no SQLite marcando como pendente, atualiza a tela e pede sync.
  Future<void> _gravar(String tabela, Map<String, Object?> linha) async {
    final db = _db;
    if (db == null) throw StateError('Banco local fechado');
    linha['updated_at'] = agoraIso();
    linha['pendente'] = 1;
    await db.insert(tabela, linha, conflictAlgorithm: ConflictAlgorithm.replace);
    await recarregar();
    SyncService.instance.sincronizar();
  }

  String novoId() => _uuid.v4();

  // ---- Casa ----

  /// Cria uma casa (funciona offline) e você como primeiro morador.
  Future<void> criarCasa(String nome) async {
    final user = _sb.auth.currentUser!;
    final casaId = novoId();
    await _gravar('casas', Casa(
      id: casaId,
      nome: nome.trim(),
      codigoConvite: _gerarCodigo(),
      criadoPor: user.id,
      updatedAt: '',
    ).toLocal());
    await _gravar('moradores', Morador(
      id: novoId(),
      casaId: casaId,
      nome: (user.userMetadata?['nome'] as String?)?.trim().isNotEmpty == true
          ? (user.userMetadata!['nome'] as String).trim()
          : (user.email ?? 'Eu').split('@').first,
      cor: 0,
      usuarioId: user.id,
      updatedAt: '',
    ).toLocal());
  }

  /// Entra numa casa existente pelo código de convite (precisa de internet).
  Future<void> entrarNaCasa(String codigo) async {
    final user = _sb.auth.currentUser!;
    final casaId = await _sb.rpc('entrar_na_casa', params: {
      'p_codigo': codigo.trim().toUpperCase(),
      'p_nome': user.userMetadata?['nome'] ?? user.email?.split('@').first,
    });
    await _baixarCasa(casaId as String);
  }

  /// Depois do login num celular novo: procura no servidor se o usuário
  /// já mora em alguma casa e baixa tudo. Retorna false se não achar.
  Future<bool> buscarCasaNoServidor() async {
    final rows = await _sb
        .from('moradores')
        .select('casa_id')
        .eq('usuario_id', _uid!)
        .eq('deleted', false)
        .limit(1);
    if (rows.isEmpty) return false;
    await _baixarCasa(rows.first['casa_id'] as String);
    return true;
  }

  Future<void> _baixarCasa(String casaId) async {
    final row =
        await _sb.from('casas').select().eq('id', casaId).single();
    await _db!.insert('casas', LocalDb.deRemoto('casas', row),
        conflictAlgorithm: ConflictAlgorithm.replace);
    await recarregar();
    await SyncService.instance.sincronizar(reiniciarRealtime: true);
  }

  String _gerarCodigo() {
    const letras = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // sem 0/O, 1/I
    final r = Random.secure();
    return List.generate(6, (_) => letras[r.nextInt(letras.length)]).join();
  }

  // ---- Moradores ----

  Future<void> salvarMorador({String? id, required String nome}) async {
    final existente = id == null ? null : morador(id);
    await _gravar('moradores', Morador(
      id: id ?? novoId(),
      casaId: casa!.id,
      nome: nome.trim(),
      cor: existente?.cor ?? _moradores.length % paletaMoradores.length,
      usuarioId: existente?.usuarioId,
      updatedAt: '',
    ).toLocal());
  }

  /// Exclusão lógica. Retorna false (e não exclui) se o morador aparece em
  /// algum gasto ou pagamento, para não quebrar os saldos.
  Future<bool> excluirMorador(String id) async {
    if (moradorEmUso(id) || id == euId) return false;
    final m = morador(id);
    await _gravar('moradores', Morador(
      id: m.id,
      casaId: m.casaId,
      nome: m.nome,
      cor: m.cor,
      usuarioId: m.usuarioId,
      updatedAt: '',
      deleted: true,
    ).toLocal());
    return true;
  }

  // ---- Gastos ----

  /// Cria (id novo) ou atualiza (id existente) um gasto.
  Future<void> salvarGasto(Gasto g) => _gravar('gastos', g.toLocal());

  Future<void> excluirGasto(Gasto g) =>
      _gravar('gastos', g.copiaExcluida().toLocal());

  // ---- Pagamentos ----

  Future<void> registrarPagamento(
          String deId, String paraId, int valorCentavos) =>
      _gravar('pagamentos', Pagamento(
        id: novoId(),
        casaId: casa!.id,
        deId: deId,
        paraId: paraId,
        valorCentavos: valorCentavos,
        data: DateTime.now(),
      ).toLocal());

  Future<void> excluirPagamento(Pagamento p) =>
      _gravar('pagamentos', p.copiaExcluida().toLocal());
}
