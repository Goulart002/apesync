/// Rotas nomeadas do app. Fluxo de navegação:
///   Login ──► Cadastro ──► (Sua casa) ──► Home
///   Login ──────────────► (Sua casa) ──► Home
///   Home (abas: Início | Gastos | Tarefas | Sobre)
///     ├─► Nova tarefa / Editar tarefa (argumento: Tarefa)
///     ├─► Novo gasto / Editar gasto (argumento: Gasto) ──► Home
///     ├─► Acertos
///     ├─► Gastos fixos (aba Gastos)
///     └─► Moradores
///   Sobre ──(Sair da conta)──► Login
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
}
