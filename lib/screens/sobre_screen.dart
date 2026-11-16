import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../routes.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Tela Sobre o App.
class SobreScreen extends StatelessWidget {
  const SobreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const Text('Sobre o app',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        const AppCard(
          child: Row(
            children: [
              AppLogo(size: 56),
              SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ApeSync',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  SizedBox(height: 2),
                  Text('Versão 1.0.0',
                      style: TextStyle(fontSize: 13, color: AppColors.muted)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('O que é',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              SizedBox(height: 6),
              Text(
                'Um app para quem divide moradia — repúblicas, casas e '
                'apartamentos compartilhados. Registre os gastos da casa e '
                'veja na hora quanto cada morador deve.',
                style: TextStyle(
                    fontSize: 14, height: 1.45, color: AppColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const AppCard(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: [
              _Recurso(Icons.receipt_long_outlined, AppColors.primary,
                  AppColors.primaryLight, 'Divisão de gastos',
                  'Igualitária entre os moradores'),
              Divider(height: 1, color: AppColors.divider),
              _Recurso(Icons.account_balance_wallet_outlined,
                  AppColors.positive, AppColors.positiveLight,
                  'Saldo automático', 'Quem deve e quem recebe'),
              Divider(height: 1, color: AppColors.divider),
              _Recurso(Icons.task_alt, AppColors.blue, AppColors.blueLight,
                  'Tarefas da casa', 'Rodízio de limpeza · em breve'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => _sair(context),
          icon: const Icon(Icons.logout, size: 20),
          label: const Text('Sair da conta'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.negative,
            side: const BorderSide(color: Color(0xFFFECACA)),
          ),
        ),
      ],
    );
  }
}

class _Recurso extends StatelessWidget {
  final IconData icon;
  final Color cor;
  final Color fundo;
  final String titulo;
  final String subtitulo;
  const _Recurso(this.icon, this.cor, this.fundo, this.titulo, this.subtitulo);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: fundo, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: cor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitulo,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _sair(BuildContext context) async {
  final data = AppData.instance;
  final pendentes = await data.contarPendentes();
  if (!context.mounted) return;
  if (pendentes > 0) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair da conta'),
        content: Text('Há $pendentes alteração(ões) ainda não sincronizada(s). '
            'Elas ficam guardadas neste celular e sobem quando você entrar de novo. Sair mesmo assim?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (ok != true) return;
  }
  await data.sair();
  if (!context.mounted) return;
  Navigator.of(context).pushNamedAndRemoveUntil(Rotas.login, (_) => false);
}
