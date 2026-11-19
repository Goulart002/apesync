import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../services/login_google.dart';
import 'calculos.dart';
import 'local_db.dart';
import 'modelos.dart';
import 'permissoes.dart';
import 'recorrentes.dart';
import 'rodizio.dart';
import 'sync_service.dart';

export 'modelos.dart';
export 'permissoes.dart';

/// Erro "de regra" com mensagem pronta para mostrar ao usuário
/// (ex.: "Transfira a administração antes de sair").
class AvisoApp implements Exception {
  final String mensagem;
  const AvisoApp(this.mensagem);
  @override
  String toString() => mensagem;
}

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
  List<Recorrencia> _recorrencias = [];
  List<Tarefa> _tarefas = [];
  List<TarefaFeita> _feitas = [];

  /// Mensagem para mostrar quando o usuário sai ou é removido da casa
  /// (a tela lê e limpa).
  String? avisoSaida;

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

  /// Gastos fixos (ativos e pausados), por dia do mês.
  List<Recorrencia> get recorrencias =>
      _recorrencias.where((r) => !r.deleted).toList()
        ..sort((a, b) {
          final c = a.dia.compareTo(b.dia);
          return c != 0 ? c : a.descricao.compareTo(b.descricao);
        });

  Recorrencia? recorrencia(String? id) {
    for (final r in _recorrencias) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Tarefas por fazer (não concluídas), da mais urgente para a mais longe.
  List<Tarefa> get tarefas =>
      _tarefas.where((t) => !t.deleted && !t.concluida).toList()
        ..sort((a, b) {
          final c = a.proxima.compareTo(b.proxima);
          return c != 0 ? c : a.titulo.compareTo(b.titulo);
        });

  /// As minhas: a vez é minha, ou é de "qualquer pessoa".
  List<Tarefa> get minhasTarefas => tarefas
      .where((t) => t.responsavelId == null || t.responsavelId == euId)
      .toList();

  /// Minhas tarefas de hoje e as atrasadas (para o Início).
  List<Tarefa> get minhasTarefasDeHoje {
    final hoje = DateTime.now();
    return minhasTarefas.where((t) {
      final s = Rodizio.situacao(t, hoje);
      return s == SituacaoTarefa.hoje || s == SituacaoTarefa.atrasada;
    }).toList();
  }

  /// Histórico: o que foi feito, do mais recente para o mais antigo.
  List<TarefaFeita> get tarefasFeitas =>
      _feitas.where((f) => !f.deleted).toList()
        ..sort((a, b) => b.feitaEm.compareTo(a.feitaEm));

  Map<String, int> placarDoMes([DateTime? mes]) =>
      Rodizio.placarDoMes(_feitas, mes ?? DateTime.now());

  /// Pagamentos ativos, do mais recente para o mais antigo.
  List<Pagamento> get pagamentos =>
      _pagamentos.where((p) => !p.deleted).toList()
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
    final conta = _sb.auth.currentUser;
    final n = meuMorador?.nome ??
        (conta == null
            ? 'Você'
            : nomeDaConta(conta.userMetadata, conta.email));
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

  /// Nome do morador dono de uma conta (ex.: quem lançou um gasto).
  String nomeDoUsuario(String? usuarioId) {
    if (usuarioId == null) return 'outro morador';
    if (usuarioId == _uid) return 'você';
    for (final m in _moradores) {
      if (m.usuarioId == usuarioId) return m.nome;
    }
    return 'outro morador';
  }

  // ---------------------------------------------------------------------------
  // Permissões (administrador x membro)
  // ---------------------------------------------------------------------------

  Permissoes get permissoes => Permissoes(
        usuarioId: _uid,
        adminUsuarioId: casa?.adminId,
        euMoradorId: euId,
      );

  bool get souAdmin => permissoes.souAdmin;

  /// Morador que administra a casa (null se ele não estiver mais na lista).
  Morador? get adminMorador {
    for (final m in moradores) {
      if (permissoes.ehAdmin(m)) return m;
    }
    return null;
  }

  List<Gasto> gastosDoMes(DateTime mes) => gastos
      .where((g) => g.data.year == mes.year && g.data.month == mes.month)
      .toList();

  /// Totais do mês: ajustes (dívida de quem saiu) não são gasto da casa,
  /// então ficam de fora (mas continuam contando no saldo).
  int totalCentavos(Iterable<Gasto> lista) => lista
      .where((g) => !g.categoria.ehAjuste)
      .fold(0, (s, g) => s + g.valorCentavos);

  int minhaParteCentavos(Iterable<Gasto> lista) => lista
      .where((g) => !g.categoria.ehAjuste)
      .fold(0, (s, g) => s + g.parteDe(euId));

  int saldoDe(String id) => Calculos.saldoDe(id, gastos, pagamentos);
  int saldoCentavos() => saldoDe(euId);

  List<Transferencia> simplificarDividas() =>
      Calculos.simplificar({for (final m in moradores) m.id: saldoDe(m.id)});

  int dividasSemSimplificar() =>
      Calculos.dividasSemSimplificar(gastos, pagamentos);

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
    await gerarRecorrentes(); // gastos fixos do mês, mesmo offline
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
      _recorrencias = [];
      _tarefas = [];
      _feitas = [];
    } else {
      final args = [casa!.id];
      _moradores =
          (await db.query('moradores', where: 'casa_id = ?', whereArgs: args))
              .map(Morador.fromMap)
              .toList();
      _gastos =
          (await db.query('gastos', where: 'casa_id = ?', whereArgs: args))
              .map(Gasto.fromMap)
              .toList();
      _pagamentos =
          (await db.query('pagamentos', where: 'casa_id = ?', whereArgs: args))
              .map(Pagamento.fromMap)
              .toList();
      _recorrencias = (await db.query('recorrencias',
              where: 'casa_id = ?', whereArgs: args))
          .map(Recorrencia.fromMap)
          .toList();
      _tarefas =
          (await db.query('tarefas', where: 'casa_id = ?', whereArgs: args))
              .map(Tarefa.fromMap)
              .toList();
      _feitas = (await db.query('tarefas_feitas',
              where: 'casa_id = ?', whereArgs: args))
          .map(TarefaFeita.fromMap)
          .toList();

      // O sync baixou o meu registro de morador como excluído: fui
      // removido pelo administrador. Limpa a casa do celular.
      final meus = _moradores.where((m) => m.usuarioId == _uid);
      if (meus.isNotEmpty && meus.every((m) => m.deleted)) {
        avisoSaida = 'Você foi removido da casa "${casa!.nome}".';
        await LocalDb.apagarCasa(db, casa!.id);
        return recarregar();
      }
    }
    notifyListeners();
  }

  Future<int> contarPendentes() async =>
      _db == null ? 0 : await LocalDb.contarPendentes(_db!);

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
    _recorrencias = [];
    _tarefas = [];
    _feitas = [];
    notifyListeners();
    try {
      await _sb.auth.signOut();
    } catch (_) {
      // Sem internet: a sessão local é apagada mesmo assim.
    }
    await LoginGoogle.sair(); // próxima entrada com Google pergunta a conta
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
    await db.insert(tabela, linha,
        conflictAlgorithm: ConflictAlgorithm.replace);
    await recarregar();
    SyncService.instance.sincronizar();
  }

  String novoId() => _uuid.v4();

  // ---- Casa ----

  /// Cria uma casa (funciona offline) e você como primeiro morador.
  Future<void> criarCasa(String nome) async {
    final user = _sb.auth.currentUser!;
    final casaId = novoId();
    await _gravar(
        'casas',
        Casa(
          id: casaId,
          nome: nome.trim(),
          codigoConvite: _gerarCodigo(),
          criadoPor: user.id,
          adminId: user.id, // quem cria a casa é o administrador
          updatedAt: '',
        ).toLocal());
    await _gravar(
        'moradores',
        Morador(
          id: novoId(),
          casaId: casaId,
          nome: nomeDaConta(user.userMetadata, user.email),
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
      'p_nome': nomeDaConta(user.userMetadata, user.email),
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
    final row = await _sb.from('casas').select().eq('id', casaId).single();
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

  /// Admin: gera um novo código de convite (o antigo para de funcionar).
  /// Funciona offline; o código novo vale quando sincronizar.
  Future<void> gerarNovoCodigo() async {
    if (!permissoes.podeGerarCodigo) {
      throw const AvisoApp('Só o administrador pode gerar um novo código');
    }
    await _gravar(
        'casas', casa!.copia(codigoConvite: _gerarCodigo()).toLocal());
  }

  /// Admin: passa a administração para outro morador (precisa de internet).
  Future<void> transferirAdmin(Morador m) async {
    if (!permissoes.podeTornarAdmin(m)) {
      throw const AvisoApp('Escolha outro morador que tenha conta no app');
    }
    await SyncService.instance.sincronizar(); // sobe o que estiver pendente
    await _sb.rpc('transferir_admin',
        params: {'p_casa': casa!.id, 'p_morador': m.id});
    await _baixarCasa(casa!.id);
  }

  /// Sai da casa (precisa de internet). Admin precisa transferir antes, e
  /// as contas precisam estar acertadas.
  Future<void> sairDaCasa() async {
    final c = casa;
    final eu = meuMorador;
    if (c == null || eu == null) return;
    final motivo = permissoes.motivoNaoPodeSair(
      meuSaldo: saldoDe(eu.id),
      outrosComConta:
          moradores.where((m) => m.temConta && m.id != eu.id).length,
    );
    if (motivo != null) throw AvisoApp(motivo);

    // Sobe o que estiver pendente antes, para não perder nada.
    await SyncService.instance.sincronizar();
    final r = await _sb
        .from('moradores')
        .update({'deleted': true, 'updated_at': agoraIso()})
        .eq('id', eu.id)
        .select('id');
    if (r.isEmpty) throw const AvisoApp('Não foi possível sair da casa');

    avisoSaida = 'Você saiu da casa "${c.nome}".';
    await LocalDb.apagarCasa(_db!, c.id);
    await recarregar();
  }

  // ---- Moradores ----
  // Moradores novos só entram pelo código de convite (entrarNaCasa).

  Future<void> editarNome(Morador m, String nome) async {
    if (!permissoes.podeEditarMorador(m)) {
      throw const AvisoApp('Você só pode editar o seu próprio nome');
    }
    await _gravar('moradores', m.copia(nome: nome.trim()).toLocal());
  }

  /// Ajuste que será criado se [m] for removido agora (null = não deve nada).
  Gasto? previaAjuste(Morador m) => Calculos.ajusteDeRemocao(
        id: novoId(),
        casaId: casa?.id ?? '',
        removido: m,
        saldo: saldoDe(m.id),
        ficam: moradores.map((o) => o.id).toList(),
        data: DateTime.now(),
        criadoPor: _uid,
      );

  /// Admin: remove um morador da casa (exclusão lógica: o nome continua
  /// aparecendo nos gastos antigos). Quem tem a receber não pode ser
  /// removido; se estiver devendo, a dívida vira um ajuste dividido entre
  /// quem fica.
  Future<void> removerMorador(Morador m) async {
    final motivo = permissoes.motivoNaoPodeRemover(m, saldoDe(m.id));
    if (motivo != null) throw AvisoApp(motivo);
    final ajuste = previaAjuste(m);
    if (ajuste != null) await _gravar('gastos', ajuste.toLocal());
    await _gravar('moradores', m.copia(deleted: true).toLocal());
  }

  /// Ajuste só pode ser excluído pelo admin e se a pessoa voltou para a
  /// casa (senão a dívida voltaria para alguém que não está mais na lista).
  bool podeExcluirAjuste(Gasto g) =>
      souAdmin && moradores.any((m) => m.id == g.pagoPorId);

  // ---- Tarefas da casa ----

  /// Cria ou altera uma tarefa (só quem criou ou o admin altera).
  Future<void> salvarTarefa(Tarefa t) async {
    for (final salva in _tarefas) {
      if (salva.id == t.id && !permissoes.podeEditarTarefa(salva)) {
        throw const AvisoApp(
            'Só quem criou a tarefa ou o administrador pode alterá-la');
      }
    }
    await _gravar('tarefas', t.toLocal());
  }

  Future<void> excluirTarefa(Tarefa t) async {
    if (!permissoes.podeEditarTarefa(t)) {
      throw const AvisoApp(
          'Só quem criou a tarefa ou o administrador pode excluí-la');
    }
    await _gravar('tarefas', t.copia(deleted: true).toLocal());
  }

  /// Marca a vez atual como feita por MIM (qualquer morador pode, inclusive
  /// cobrindo a vez de outra pessoa). Registra no histórico e passa a vez
  /// / a data para a próxima. Retorna o que é preciso para desfazer.
  Future<ConclusaoTarefa> concluirTarefa(Tarefa t) async {
    final eu = meuMorador;
    if (eu == null) throw const AvisoApp('Você não está nesta casa');
    final feita = TarefaFeita(
      id: Rodizio.idDaFeita(t.id, t.proxima),
      casaId: t.casaId,
      tarefaId: t.id,
      titulo: t.titulo,
      dataPrevista: t.proxima,
      responsavelId: t.responsavelId,
      feitaPorId: eu.id,
      feitaEm: agoraIso(),
    );
    final depois = Rodizio.depoisDeFeita(t,
        hoje: DateTime.now(), ativos: {for (final m in moradores) m.id});
    await _gravar('tarefas_feitas', feita.toLocal());
    await _gravar('tarefas', depois.toLocal());
    return ConclusaoTarefa(antes: t, depois: depois, feita: feita);
  }

  /// Desfaz o "feita" que acabou de ser marcado.
  Future<void> desfazerConclusao(ConclusaoTarefa c) async {
    await _gravar('tarefas_feitas', c.feita.copiaExcluida().toLocal());
    await _gravar('tarefas', c.antes.toLocal());
  }

  // ---- PIX ----

  /// Salva (ou remove, com null) a MINHA chave PIX, já normalizada.
  Future<void> salvarMinhaChavePix(String? chave) async {
    final eu = meuMorador;
    if (eu == null) return;
    await _gravar('moradores', eu.comChavePix(chave).toLocal());
  }

  // ---- Gastos fixos ----

  void _conferirRecorrencia(Recorrencia r) {
    for (final salva in _recorrencias) {
      if (salva.id == r.id && !permissoes.podeEditarRecorrencia(salva)) {
        throw const AvisoApp(
            'Só quem criou o gasto fixo ou o administrador pode alterá-lo');
      }
    }
  }

  /// Cria ou altera um gasto fixo e já lança os meses que venceram.
  Future<void> salvarRecorrencia(Recorrencia r) async {
    _conferirRecorrencia(r);
    await _gravar('recorrencias', r.toLocal());
    await gerarRecorrentes();
  }

  /// Pausa ou retoma. Ao retomar, começa a contar do mês atual (não lança
  /// os meses em que ficou pausado).
  Future<void> pausarRecorrencia(Recorrencia r, {required bool pausar}) =>
      salvarRecorrencia(pausar
          ? r.copia(ativo: false)
          : r.copia(ativo: true, inicio: Recorrentes.mes(DateTime.now())));

  /// Exclui o gasto fixo. Os gastos que ele já lançou continuam.
  Future<void> excluirRecorrencia(Recorrencia r) async {
    _conferirRecorrencia(r);
    await _gravar('recorrencias', r.copia(deleted: true).toLocal());
  }

  bool _gerando = false;

  /// Lança os gastos fixos dos meses que já venceram e ainda não estão no
  /// celular. Só o celular de quem criou o gasto fixo (ou do admin) lança:
  /// o gasto sai com o mesmo autor do gasto fixo. Ids e datas são
  /// determinísticos, então dois celulares lançando o mesmo mês não
  /// duplicam nada. Retorna true se lançou algum.
  Future<bool> gerarRecorrentes() async {
    final db = _db;
    final c = casa;
    if (db == null || c == null || _gerando) return false;
    _gerando = true;
    try {
      final hoje = DateTime.now();
      final existentes = {for (final g in _gastos) g.id};
      var gerou = false;
      for (final r in _recorrencias) {
        if (!permissoes.podeEditarRecorrencia(r)) continue;
        for (final venc in Recorrentes.vencimentosAte(r, hoje)) {
          final g = Recorrentes.gastoDoMes(r, venc);
          if (existentes.contains(g.id)) continue;
          // Sem _gravar: mantém a data de alteração determinística.
          await db.insert('gastos', g.toLocal()..['pendente'] = 1,
              conflictAlgorithm: ConflictAlgorithm.ignore);
          existentes.add(g.id);
          gerou = true;
        }
      }
      if (gerou) await recarregar();
      return gerou;
    } finally {
      _gerando = false;
    }
  }

  // ---- Gastos ----

  Gasto? _gastoSalvo(String id) {
    for (final g in _gastos) {
      if (g.id == id) return g;
    }
    return null;
  }

  void _conferirGasto(Gasto g, {bool excluir = false}) {
    final salvo = _gastoSalvo(g.id);
    if (salvo == null) return; // gasto novo
    if (salvo.categoria.ehAjuste) {
      if (!excluir) throw const AvisoApp('Ajustes não podem ser editados');
      if (!podeExcluirAjuste(salvo)) {
        throw const AvisoApp('Só o administrador pode desfazer o ajuste, '
            'e só depois que a pessoa voltar para a casa');
      }
      return;
    }
    if (!permissoes.podeEditarGasto(salvo)) {
      throw const AvisoApp(
          'Só quem lançou o gasto ou o administrador pode alterá-lo');
    }
  }

  /// Cria (id novo) ou atualiza (id existente) um gasto.
  Future<void> salvarGasto(Gasto g) async {
    _conferirGasto(g);
    await _gravar('gastos', g.toLocal());
  }

  Future<void> excluirGasto(Gasto g) async {
    _conferirGasto(g, excluir: true);
    await _gravar('gastos', g.copiaExcluida().toLocal());
  }

  // ---- Pagamentos ----

  void _conferirPagamento(String deId, String paraId) {
    if (!permissoes.podeMexerNoPagamento(deId, paraId)) {
      throw const AvisoApp(
          'Só quem paga, quem recebe ou o administrador pode fazer isso');
    }
  }

  Future<void> registrarPagamento(
      String deId, String paraId, int valorCentavos) async {
    _conferirPagamento(deId, paraId);
    await _gravar(
        'pagamentos',
        Pagamento(
          id: novoId(),
          casaId: casa!.id,
          deId: deId,
          paraId: paraId,
          valorCentavos: valorCentavos,
          data: DateTime.now(),
        ).toLocal());
  }

  Future<void> excluirPagamento(Pagamento p) async {
    _conferirPagamento(p.deId, p.paraId);
    await _gravar('pagamentos', p.copiaExcluida().toLocal());
  }
}

/// Resultado de marcar uma tarefa como feita (para poder desfazer).
class ConclusaoTarefa {
  final Tarefa antes;
  final Tarefa depois;
  final TarefaFeita feita;
  const ConclusaoTarefa(
      {required this.antes, required this.depois, required this.feita});
}
