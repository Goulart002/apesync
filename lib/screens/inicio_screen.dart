import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../routes.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/sync_badge.dart';
import '../widgets/tarefa_widgets.dart';

/// Tela inicial (dashboard): saldo, resumo do mês, suas tarefas de hoje,
/// moradores, últimos gastos.
class InicioScreen extends StatelessWidget {
  final VoidCallback onVerTodos;
  final VoidCallback? onVerTarefas;
  const InicioScreen({super.key, required this.onVerTodos, this.onVerTarefas});

  @override
  Widget build(BuildContext context) {
    final data = AppData.instance;
    return ListenableBuilder(
      listenable: data,
      builder: (context, _) {
        final doMes = data.gastosDoMes(DateTime.now());
        final saldo = data.saldoCentavos();
        final ultimos = data.gastos.take(3).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
          children: [
            // Cabeçalho
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Olá, ${data.nomeUsuario}',
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                          '${data.nomeCasa} · ${data.moradores.length} moradores',
                          style: const TextStyle(
                              fontSize: 14, color: AppColors.muted)),
                    ],
                  ),
                ),
                Avatar(data.morador(data.euId), size: 40),
              ],
            ),
            const SizedBox(height: 12),
            const Align(alignment: Alignment.centerLeft, child: SyncBadge()),
            const SizedBox(height: 16),

            // Card de saldo
            _SaldoCard(saldo: saldo),
            const SizedBox(height: 12),

            // Resumo do mês
            Row(
              children: [
                Expanded(
                    child: StatCard('Gastos do mês',
                        formatarReais(data.totalCentavos(doMes)))),
                const SizedBox(width: 12),
                Expanded(
                    child: StatCard('Sua parte',
                        formatarReais(data.minhaParteCentavos(doMes)))),
              ],
            ),

            // Suas tarefas de hoje (e as atrasadas)
            if (data.minhasTarefasDeHoje.isNotEmpty) ...[
              SectionHeader('Suas tarefas de hoje',
                  action: 'Ver todas', onAction: onVerTarefas),
              TarefasCard(data.minhasTarefasDeHoje),
            ],

            // Moradores
            SectionHeader('Moradores',
                action: 'Gerenciar',
                onAction: () => Navigator.pushNamed(context, Rotas.moradores)),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final m in data.moradores)
                    Padding(
                      padding: const EdgeInsets.only(right: 18),
                      child: Column(
                        children: [
                          Avatar(m, size: 48),
                          const SizedBox(height: 6),
                          Text(m.id == data.euId ? 'Você' : m.nome,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => Navigator.pushNamed(context, Rotas.moradores),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: AppColors.primaryLight,
                          child: Icon(Icons.person_add_alt_1,
                              color: AppColors.primary),
                        ),
                        SizedBox(height: 6),
                        Text('Convidar',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Últimos gastos
            SectionHeader('Últimos gastos',
                action: 'Ver todos', onAction: onVerTodos),
            if (ultimos.isEmpty)
              const AppCard(
                child: Text(
                    'Nenhum gasto ainda. Toque no + para lançar o primeiro.',
                    style: TextStyle(color: AppColors.muted)),
              )
            else
              GastosCard(ultimos),
          ],
        );
      },
    );
  }
}

class _SaldoCard extends StatelessWidget {
  final int saldo;
  const _SaldoCard({required this.saldo});

  @override
  Widget build(BuildContext context) {
    final String valor;
    final String legenda;
    if (saldo > 0) {
      valor = '+ ${formatarReais(saldo)}';
      legenda = 'A casa te deve esse valor';
    } else if (saldo < 0) {
      valor = formatarReais(saldo);
      legenda = 'Você deve esse valor para a casa';
    } else {
      valor = formatarReais(0);
      legenda = 'Tudo certo, ninguém deve nada';
    }

    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, Rotas.acertos),
      child: AppCard(
      color: AppColors.primary,
      border: const Border(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Seu saldo na casa',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primaryMuted)),
              ),
              Icon(Icons.chevron_right, color: AppColors.primaryMuted),
            ],
          ),
          const SizedBox(height: 6),
          Text(valor,
              style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          const SizedBox(height: 4),
          Text(legenda,
              style: TextStyle(
                  fontSize: 14, color: AppColors.primaryMuted)),
          const SizedBox(height: 14),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => Navigator.pushNamed(context, Rotas.acertos),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text('Ver acertos',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}
