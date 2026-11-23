/// Rotas nomeadas do app. Fluxo de navegação:
///   Login ──► Cadastro ──► (Sua casa) ──► Home
///   Login (e-mail ou Google) ──► (Sua casa) ──► Home
///   Login ──► Recuperar senha ──(link do e-mail abre o app)──► Senha nova ──► Home
///   Home (abas: Início | Gastos | Tarefas | Ajustes)
///     ├─► Nova tarefa / Editar tarefa (argumento: Tarefa)
///     ├─► Novo gasto / Editar gasto (argumento: Gasto) ──► Home
///     ├─► Acertos
///     ├─► Gastos fixos (aba Gastos)
///     └─► Moradores
///   Ajustes ──(Sair da conta / Excluir conta)──► Login · Ajustes ──► Sobre
class Rotas {
  static const login = '/';
  static const cadastro = '/cadastro';
  static const casa = '/casa';
  static const home = '/home';
  static const novoGasto = '/novo-gasto';
  static const acertos = '/acertos';
  static const moradores = '/moradores';
  static const gastosFixos = '/gastos-fixos';
  static const novaTarefa = '/nova-tarefa';
  static const recuperarSenha = '/recuperar-senha';

  /// Aberta pelo link do e-mail de recuperação (já logado).
  static const senhaNova = '/senha-nova';

  /// Ajustes → Sobre o ApêSync.
  static const sobre = '/sobre';
}
