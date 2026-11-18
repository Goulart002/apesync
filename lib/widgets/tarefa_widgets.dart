import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../data/rodizio.dart';
import '../routes.dart';
import '../screens/fluxo.dart';
import '../theme.dart';
import 'common.dart';

/// Marca a tarefa como feita por mim, com "Desfazer" no aviso. Se for uma
/// tarefa de compras, oferece lançar o gasto na sequência.
Future<void> concluirComDesfazer(BuildContext context, Tarefa t) async {
  final data = AppData.instance;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final ConclusaoTarefa c;
  try {
    c = await data.concluirTarefa(t);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(mensagemErro(e))));
    return;
  }
  final noLugar = c.feita.noLugarDeOutro
      ? ' (no lugar de ${data.morador(c.feita.responsavelId!).nome})'
      : '';
  final proxima = c.depois.concluida
      ? ''
      : ' Próxima: ${Rodizio.descreverData(c.depois, DateTime.now())}'
          '${c.depois.responsavelId == null ? '' : ', vez de ${data.nomeDe(c.depois.responsavelId!)}'}.';
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text('"${t.titulo}" feita$noLugar.$proxima'),
    action: SnackBarAction(
      label: 'Desfazer',
      onPressed: () => data.desfazerConclusao(c),
    ),
  ));

  if (t.tipo == TipoTarefa.compras && context.mounted) {
    final lancar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lançar o gasto?'),
        content: const Text(
            'Quer lançar o gasto das compras agora, para dividir com a casa?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Agora não')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Lançar gasto'),
          ),
        ],
      ),
    );
    if (lancar == true) {
      navigator.pushNamed(Rotas.novoGasto,
          arguments: GastoRascunho(t.titulo, Categoria.mercado));
    }
  }
}

/// Linha de tarefa: ícone, título, de quem é a vez, repetição, quando, e o
/// botão de marcar como feita.
class TarefaTile extends StatelessWidget {
  final Tarefa tarefa;
  const TarefaTile(this.tarefa, {super.key});

  @override
  Widget build(BuildContext context) {
    final data = AppData.instance;
    final hoje = DateTime.now();
    final situacao = Rodizio.situacao(tarefa, hoje);
    final atrasada = situacao == SituacaoTarefa.atrasada;
    final vez = tarefa.responsavelId == null
        ? 'Qualquer pessoa'
        : 'Vez de ${data.nomeDe(tarefa.responsavelId!)}';
    final repeticao = tarefa.repete
        ? ' · ${Rodizio.descreverRepeticao(tarefa)}'
            '${tarefa.temRodizio ? ' · rodízio' : ''}'
        : '';

    return InkWell(
      onTap: () =>
          Navigator.pushNamed(context, Rotas.novaTarefa, arguments: tarefa),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: atrasada ? AppColors.negativeLight : AppColors.blueLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(tarefa.tipo.icon,
                  color: atrasada ? AppColors.negative : AppColors.blue,
                  size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tarefa.titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('$vez$repeticao',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.muted)),
                  const SizedBox(height: 2),
                  Text(Rodizio.descreverData(tarefa, hoje),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: atrasada
                              ? AppColors.negative
                              : AppColors.primary)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Marcar como feita',
              onPressed: () => concluirComDesfazer(context, tarefa),
              icon: const Icon(Icons.check_circle_outline,
                  color: AppColors.positive, size: 30),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cartão com uma lista de tarefas (separadas por linhas).
class TarefasCard extends StatelessWidget {
  final List<Tarefa> tarefas;
  const TarefasCard(this.tarefas, {super.key});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Column(
        children: [
          for (var i = 0; i < tarefas.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.divider),
            TarefaTile(tarefas[i]),
          ],
        ],
      ),
    );
  }
}
