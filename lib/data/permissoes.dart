import 'modelos.dart';

/// Quem pode fazer o quê na casa (regras puras, fáceis de testar).
///
/// As mesmas regras valem no servidor (policies de RLS em
/// supabase/schema.sql); aqui elas servem para a tela esconder o que o
/// usuário não pode fazer e explicar o porquê.
///
/// - Todo morador: lança gastos, edita o próprio nome, edita/exclui os
///   gastos que ele lançou, registra pagamentos em que ele paga ou recebe
///   e pode sair da casa (com as contas acertadas).
/// - Administrador: tudo isso + remove moradores, edita qualquer gasto ou
///   pagamento, gera novo código de convite e transfere a administração.
class Permissoes {
  /// Conta (auth) do usuário logado.
  final String? usuarioId;

  /// Conta (auth) de quem administra a casa.
  final String? adminUsuarioId;

  /// Id do morador que é o usuário logado.
  final String euMoradorId;

  const Permissoes({
    required this.usuarioId,
    required this.adminUsuarioId,
    required this.euMoradorId,
  });

  bool get souAdmin => usuarioId != null && usuarioId == adminUsuarioId;

  bool ehAdmin(Morador m) =>
      m.usuarioId != null && m.usuarioId == adminUsuarioId;

  bool podeEditarMorador(Morador m) => souAdmin || m.id == euMoradorId;

  bool podeEditarGasto(Gasto g) =>
      souAdmin || (g.criadoPor != null && g.criadoPor == usuarioId);

  /// Editar/excluir tarefa: quem criou ou o admin. (Marcar como feita:
  /// qualquer morador.)
  bool podeEditarTarefa(Tarefa t) =>
      souAdmin || (t.criadoPor != null && t.criadoPor == usuarioId);

  bool podeEditarRecorrencia(Recorrencia r) =>
      souAdmin || (r.criadoPor != null && r.criadoPor == usuarioId);

  bool podeMexerNoPagamento(String deId, String paraId) =>
      souAdmin || deId == euMoradorId || paraId == euMoradorId;

  bool get podeGerarCodigo => souAdmin;

  bool podeTornarAdmin(Morador m) =>
      souAdmin && m.temConta && !m.deleted && m.id != euMoradorId;

  /// null = pode remover; senão, o motivo para mostrar na tela.
  ///
  /// Quem está DEVENDO pode ser removido: a dívida é dividida entre quem
  /// fica (ver Calculos.ajusteDeRemocao). Quem tem a RECEBER não, porque
  /// seria tirar dinheiro de quem já pagou pela casa.
  String? motivoNaoPodeRemover(Morador m, int saldo) {
    if (!souAdmin) return 'Só o administrador pode remover moradores';
    if (m.id == euMoradorId) return 'Para sair, use "Sair da casa"';
    if (saldo > 0) {
      return '${m.nome} ${descreverSaldo(saldo)}. Paguem o que a casa deve '
          'antes de remover.';
    }
    return null;
  }

  /// null = pode sair; senão, o motivo para mostrar na tela.
  String? motivoNaoPodeSair(
      {required int meuSaldo, required int outrosComConta}) {
    if (souAdmin) {
      return outrosComConta == 0
          ? 'Você é o único morador com conta. Convide alguém e transfira '
              'a administração antes de sair.'
          : 'Você é o administrador. Transfira a administração para outro '
              'morador antes de sair.';
    }
    if (meuSaldo != 0) {
      return 'Você ${descreverSaldo(meuSaldo)}. Acerte as contas antes de sair.';
    }
    return null;
  }

  static String descreverSaldo(int saldo) => saldo < 0
      ? 'ainda deve ${formatarReais(-saldo)}'
      : 'ainda tem ${formatarReais(saldo)} a receber';
}
