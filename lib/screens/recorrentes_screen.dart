import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../routes.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'fluxo.dart';

/// Gastos fixos da casa (aluguel, internet...): o app lança um gasto por
/// mês, no dia escolhido. Aqui dá para mudar o valor, pausar ou excluir.
/// Para criar: "Novo gasto" → "Repetir todo mês".
class RecorrentesScreen extends StatelessWidget {
  const RecorrentesScreen({super.key});

  static void _aviso(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _editar(BuildContext context, Recorrencia r) async {
    final descricao = TextEditingController(text: r.descricao);
    final valor = TextEditingController(
        text: '${r.valorCentavos ~/ 100},'
            '${(r.valorCentavos % 100).toString().padLeft(2, '0')}');
    final salvar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar gasto fixo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: descricao,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Descrição'),
            ),
            TextField(
              controller: valor,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Valor', prefixText: 'R\$ '),
            ),
            const SizedBox(height: 8),
            const Text(
              'Vale para os próximos meses. Os gastos já lançados não mudam.',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (salvar != true || !context.mounted) return;
    final centavos = parseReais(valor.text);
    if (centavos == null || descricao.text.trim().isEmpty) {
      _aviso(context, 'Informe a descrição e um valor maior que zero');
      return;
    }
    try {
      await AppData.instance.salvarRecorrencia(
          r.copia(descricao: descricao.text.trim(), valorCentavos: centavos));
      if (context.mounted) _aviso(context, 'Gasto fixo atualizado');
    } catch (e) {
      if (context.mounted) _aviso(context, mensagemErro(e));
    }
  }

  Future<void> _pausar(BuildContext context, Recorrencia r) async {
    try {
      await AppData.instance.pausarRecorrencia(r, pausar: r.ativo);
      if (context.mounted) {
        _aviso(
            context,
            r.ativo
                ? '"${r.descricao}" pausado: não será lançado nos próximos meses'
                : '"${r.descricao}" retomado');
      }
    } catch (e) {
      if (context.mounted) _aviso(context, mensagemErro(e));
    }
  }

  Future<void> _excluir(BuildContext context, Recorrencia r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir gasto fixo'),
        content: Text('Parar de lançar "${r.descricao}" todo mês? Os gastos '
            'que já foram lançados continuam na lista.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                backgroundColor: AppColors.negative),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await AppData.instance.excluirRecorrencia(r);
      if (context.mounted) _aviso(context, 'Gasto fixo excluído');
    } catch (e) {
      if (context.mounted) _aviso(context, mensagemErro(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = AppData.instance;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, Rotas.novoGasto),
        icon: const Icon(Icons.add),
        label: const Text('Novo gasto'),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: data,
          builder: (context, _) {
            final lista = data.recorrencias;
            final perm = data.permissoes;
            final totalMes = lista
                .where((r) => r.ativo)
                .fold(0, (s, r) => s + r.valorCentavos);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              children: [
                Row(
                  children: [
                    SquareIconButton(
                        icon: Icons.arrow_back,
                        onTap: () => Navigator.pop(context)),
                    const Expanded(
                      child: Text('Gastos fixos',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 40),
                  ],
                ),
                const SizedBox(height: 20),
                if (lista.isEmpty)
                  const AppCard(
                    child: Text(
                      'Nenhum gasto fixo ainda. Para criar, toque em '
                      '"Novo gasto" e ligue "Repetir todo mês" — ótimo para '
                      'aluguel, internet e condomínio.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  )
                else ...[
                  StatCard('Fixos por mês (ativos)', formatarReais(totalMes)),
                  const SectionHeader('Lançados todo mês'),
                  AppCard(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Column(
                      children: [
                        for (var i = 0; i < lista.length; i++) ...[
                          if (i > 0)
                            const Divider(height: 1, color: AppColors.divider),
                          _linha(context, data, perm, lista[i]),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'O app lança cada gasto no dia certo, quando o celular de '
                    'quem criou o gasto fixo (ou do administrador) abrir o '
                    'app. Dia 31 em meses mais curtos vira o último dia.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _linha(
      BuildContext context, AppData data, Permissoes perm, Recorrencia r) {
    final pode = perm.podeEditarRecorrencia(r);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: r.ativo ? r.categoria.background : AppColors.divider,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(r.ativo ? r.categoria.icon : Icons.pause,
            color: r.ativo ? r.categoria.color : AppColors.muted, size: 22),
      ),
      title: Text(r.descricao,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontWeight: FontWeight.w600,
              color: r.ativo ? null : AppColors.muted)),
      subtitle: Text(
          '${formatarReais(r.valorCentavos)} · todo dia ${r.dia} · '
          '${data.nomeDe(r.pagoPorId)} paga'
          '${r.ativo ? '' : ' · pausado'}',
          style: const TextStyle(fontSize: 12)),
      trailing: pode
          ? PopupMenuButton<String>(
              tooltip: 'Opções',
              onSelected: (op) {
                if (op == 'editar') _editar(context, r);
                if (op == 'pausar') _pausar(context, r);
                if (op == 'excluir') _excluir(context, r);
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                    value: 'editar',
                    child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Editar valor'))),
                PopupMenuItem(
                    value: 'pausar',
                    child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(r.ativo ? Icons.pause : Icons.play_arrow),
                        title: Text(r.ativo ? 'Pausar' : 'Retomar'))),
                const PopupMenuItem(
                    value: 'excluir',
                    child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline,
                            color: AppColors.negative),
                        title: Text('Excluir',
                            style: TextStyle(color: AppColors.negative)))),
              ],
            )
          : null,
    );
  }
}
