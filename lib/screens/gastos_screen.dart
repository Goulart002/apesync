import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Principal funcionalidade: lista de gastos da casa por mês e categoria.
class GastosScreen extends StatefulWidget {
  const GastosScreen({super.key});

  @override
  State<GastosScreen> createState() => _GastosScreenState();
}

class _GastosScreenState extends State<GastosScreen> {
  DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month);
  Categoria? _filtro; // null = Todos

  void _mudarMes(int delta) =>
      setState(() => _mes = DateTime(_mes.year, _mes.month + delta));

  @override
  Widget build(BuildContext context) {
    final data = AppData.instance;
    return ListenableBuilder(
      listenable: data,
      builder: (context, _) {
        final doMes = data.gastosDoMes(_mes);
        final filtrados = _filtro == null
            ? doMes
            : doMes.where((g) => g.categoria == _filtro).toList();

        // Agrupa por dia (a lista já vem ordenada do mais recente).
        final grupos = <DateTime, List<Gasto>>{};
        for (final g in filtrados) {
          final dia = DateTime(g.data.year, g.data.month, g.data.day);
          grupos.putIfAbsent(dia, () => []).add(g);
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Gastos',
                      style: TextStyle(
                          fontSize: 28, fontWeight: FontWeight.w700)),
                ),
                SquareIconButton(
                  icon: Icons.search,
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Busca: próxima sprint')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Seletor de mês
            Row(
              children: [
                SquareIconButton(
                    icon: Icons.chevron_left, onTap: () => _mudarMes(-1)),
                Expanded(
                  child: Text(nomeMes(_mes),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                SquareIconButton(
                    icon: Icons.chevron_right, onTap: () => _mudarMes(1)),
              ],
            ),
            const SizedBox(height: 16),

            // Resumo
            AppCard(
              padding: EdgeInsets.zero,
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    _Resumo('Total da casa',
                        formatarReais(data.totalCentavos(doMes))),
                    const VerticalDivider(
                        width: 1, color: AppColors.border),
                    _Resumo('Sua parte',
                        formatarReais(data.minhaParteCentavos(doMes))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Filtros por categoria
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: Row(
                children: [
                  _chip('Todos', null),
                  for (final c in CategoriaInfo.lancaveis) _chip(c.label, c),
                  // "Ajuste" só aparece se houver algum no mês.
                  if (doMes.any((g) => g.categoria.ehAjuste))
                    _chip(Categoria.ajuste.label, Categoria.ajuste),
                ],
              ),
            ),

            // Lista agrupada por dia
            if (grupos.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Column(
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        size: 48, color: AppColors.hint),
                    SizedBox(height: 12),
                    Text('Nenhum gasto aqui',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    SizedBox(height: 4),
                    Text('Toque no + para adicionar',
                        style: TextStyle(color: AppColors.muted)),
                  ],
                ),
              ),
            for (final entry in grupos.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 8),
                child: Text(diaPorExtenso(entry.key).toUpperCase(),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                        color: AppColors.muted)),
              ),
              GastosCard(entry.value),
            ],
          ],
        );
      },
    );
  }

  Widget _chip(String label, Categoria? cat) {
    final selecionado = _filtro == cat;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selecionado,
        showCheckmark: false,
        onSelected: (_) => setState(() => _filtro = cat),
        selectedColor: AppColors.primary,
        backgroundColor: AppColors.card,
        labelStyle: TextStyle(
            fontWeight: FontWeight.w500,
            color: selecionado ? Colors.white : AppColors.text),
        side: BorderSide(
            color: selecionado ? AppColors.primary : AppColors.border),
        shape: const StadiumBorder(),
      ),
    );
  }
}

class _Resumo extends StatelessWidget {
  final String label;
  final String valor;
  const _Resumo(this.label, this.valor);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.muted)),
            const SizedBox(height: 6),
            Text(valor,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
