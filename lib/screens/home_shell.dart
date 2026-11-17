import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../routes.dart';
import '../theme.dart';
import 'gastos_screen.dart';
import 'inicio_screen.dart';
import 'sobre_screen.dart';

/// Tela "casca" com a barra de navegação inferior (Início | Gastos | Sobre).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _aba = 0;
  bool _saiu = false;

  @override
  void initState() {
    super.initState();
    AppData.instance.addListener(_verificarCasa);
  }

  @override
  void dispose() {
    AppData.instance.removeListener(_verificarCasa);
    super.dispose();
  }

  /// Saiu da casa ou foi removido (o sync avisa): volta para "Sua casa".
  void _verificarCasa() {
    final data = AppData.instance;
    if (_saiu || !mounted || !data.aberto || data.temCasa) return;
    _saiu = true;
    final aviso = data.avisoSaida;
    data.avisoSaida = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pushNamedAndRemoveUntil(context, Rotas.casa, (_) => false);
      if (aviso != null) messenger.showSnackBar(SnackBar(content: Text(aviso)));
    });
  }

  void _irPara(int aba) => setState(() => _aba = aba);

  Future<void> _novoGasto() async {
    final salvou = await Navigator.pushNamed(context, Rotas.novoGasto);
    if (!mounted || salvou != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Gasto adicionado e dividido!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _aba,
          children: [
            InicioScreen(onVerTodos: () => _irPara(1)),
            const GastosScreen(),
            const SobreScreen(),
          ],
        ),
      ),
      floatingActionButton: _aba == 2
          ? null
          : FloatingActionButton(
              onPressed: _novoGasto,
              tooltip: 'Novo gasto',
              child: const Icon(Icons.add, size: 30),
            ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: _aba,
          onDestinationSelected: _irPara,
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home, color: AppColors.primary),
                label: 'Início'),
            NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon:
                    Icon(Icons.receipt_long, color: AppColors.primary),
                label: 'Gastos'),
            NavigationDestination(
                icon: Icon(Icons.info_outline),
                selectedIcon: Icon(Icons.info, color: AppColors.primary),
                label: 'Sobre'),
          ],
        ),
      ),
    );
  }
}
