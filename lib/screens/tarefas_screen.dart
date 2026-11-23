import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../data/rodizio.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/tarefa_widgets.dart';

/// Aba Tarefas: o que tem para fazer (atrasadas, hoje, próximas), filtro
/// "Minhas / Da casa", placar do mês e o que foi feito recentemente.
class TarefasScreen extends StatefulWidget {
  const TarefasScreen({super.key});

  @override
  State<TarefasScreen> createState() => _TarefasScreenState();
}

class _TarefasScreenState extends State<TarefasScreen> {
  bool _soMinhas = false;

  @override
  Widget build(BuildContext context) {
    final data = AppData.instance;
    return ListenableBuilder(
      listenable: data,
      builder: (context, _) {
        final hoje = DateTime.now();
        final lista = _soMinhas ? data.minhasTarefas : data.tarefas;
        List<Tarefa> com(Set<SituacaoTarefa> s) =>
            lista.where((t) => s.contains(Rodizio.situacao(t, hoje))).toList();
        final atrasadas = com({SituacaoTarefa.atrasada});
        final deHoje = com({SituacaoTarefa.hoje});
        final proximas = com({SituacaoTarefa.amanha, SituacaoTarefa.futura});

        final placar = data.placarDoMes();
        final ranking = data.moradores
            .map((m) => MapEntry(m, placar[m.id] ?? 0))
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final recentes = data.tarefasFeitas.take(8).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
          children: [
            const Text('Tarefas',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                    value: false,
                    label: Text('Da casa'),
                    icon: Icon(Icons.home_outlined)),
                ButtonSegment(
                    value: true,
                    label: Text('Minhas'),
                    icon: Icon(Icons.person_outline)),
              ],
              selected: {_soMinhas},
              onSelectionChanged: (s) => setState(() => _soMinhas = s.first),
            ),
            if (lista.isEmpty) ...[
              const SizedBox(height: 20),
              AppCard(
                child: Text(
                  _soMinhas
                      ? 'Nenhuma tarefa sua por enquanto.'
                      : 'Nenhuma tarefa ainda. Toque no + para criar: faxina, '
                          'louça, lixo, compras... Dá para repetir toda semana '
                          'e revezar entre os moradores.',
                  style: const TextStyle(color: AppColors.muted),
                ),
              ),
            ],
            if (atrasadas.isNotEmpty) ...[
              const SectionHeader('Atrasadas'),
              TarefasCard(atrasadas),
            ],
            if (deHoje.isNotEmpty) ...[
              const SectionHeader('Hoje'),
              TarefasCard(deHoje),
            ],
            if (proximas.isNotEmpty) ...[
              const SectionHeader('Próximas'),
              TarefasCard(proximas),
            ],

            // Placar do mês
            if (placar.isNotEmpty) ...[
              SectionHeader(
                  'Placar de ${nomeMes(hoje).split(' ').first.toLowerCase()}'),
              AppCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(
                  children: [
                    for (var i = 0; i < ranking.length; i++) ...[
                      if (i > 0)
                        const Divider(height: 1, color: AppColors.divider),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Avatar(ranking[i].key, size: 32),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(data.nomeDe(ranking[i].key.id),
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                            ),
                            Text(
                                ranking[i].value == 1
                                    ? '1 tarefa'
                                    : '${ranking[i].value} tarefas',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            // Feitas recentemente
            if (recentes.isNotEmpty) ...[
              const SectionHeader('Feitas recentemente'),
              AppCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(
                  children: [
                    for (var i = 0; i < recentes.length; i++) ...[
                      if (i > 0)
                        const Divider(height: 1, color: AppColors.divider),
                      _Feita(recentes[i]),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Feita extends StatelessWidget {
  final TarefaFeita f;
  const _Feita(this.f);

  @override
  Widget build(BuildContext context) {
    final data = AppData.instance;
    final quando = DateTime.tryParse(f.feitaEm)?.toLocal();
    final noLugar = f.noLugarDeOutro
        ? ' no lugar de ${data.morador(f.responsavelId!).nome}'
        : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.positive, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
                '${data.nomeDe(f.feitaPorId)} fez "${f.titulo}"$noLugar',
                style: const TextStyle(fontSize: 13)),
          ),
          if (quando != null)
            Text(dataCurta(quando),
                style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ],
      ),
    );
  }
}
