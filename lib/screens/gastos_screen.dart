import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../data/busca.dart';
import '../routes.dart';
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

  // Busca: com texto digitado, procura em todos os meses.
  bool _buscando = false;
  final _busca = TextEditingController();
  String get _termo => _busca.text.trim();

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  void _mudarMes(int delta) =>
      setState(() => _mes = DateTime(_mes.year, _mes.month + delta));

  void _alternarBusca() => setState(() {
        _buscando = !_buscando;
        if (!_buscando) _busca.clear();
      });

  @override
  Widget build(BuildContext context) {
    final data = AppData.instance;
    return ListenableBuilder(
      listenable: data,
      builder: (context, _) {
        final pesquisando = _buscando && _termo.isNotEmpty;
        final doMes = data.gastosDoMes(_mes);
        final base = pesquisando
            ? BuscaGastos.filtrar(data.gastos, _termo,
                (id) => '${data.nomeDe(id)} ${data.morador(id).nome}')
            : doMes;
        final filtrados = _filtro == null
            ? base
            : base.where((g) => g.categoria == _filtro).toList();
        final anoAtual = DateTime.now().year;

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
                TextButton.icon(
                  onPressed: () =>
                      Navigator.pushNamed(context, Rotas.gastosFixos),
                  icon: const Icon(Icons.repeat, size: 18),
                  label: const Text('Gastos fixos'),
                ),
                const SizedBox(width: 4),
                SquareIconButton(
                  icon: _buscando ? Icons.close : Icons.search,
                  onTap: _alternarBusca,
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_buscando) ...[
              TextField(
                controller: _busca,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Descrição, categoria, quem pagou ou valor',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _busca.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(_busca.clear),
                        ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Seletor de mês (a busca procura em todos os meses)
            if (!pesquisando) ...[
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
            ],

            // Resumo (do mês ou do que a busca encontrou)
            AppCard(
              padding: EdgeInsets.zero,
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    _Resumo(
                        pesquisando
                            ? (filtrados.length == 1
                                ? '1 gasto encontrado'
                                : '${filtrados.length} gastos encontrados')
                            : 'Total da casa',
                        formatarReais(data
                            .totalCentavos(pesquisando ? filtrados : doMes))),
                    const VerticalDivider(
                        width: 1, color: AppColors.border),
                    _Resumo(
                        'Sua parte',
                        formatarReais(data.minhaParteCentavos(
                            pesquisando ? filtrados : doMes))),
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
                  if (base.any((g) => g.categoria.ehAjuste))
                    _chip(Categoria.ajuste.label, Categoria.ajuste),
                ],
              ),
            ),

            // Lista agrupada por dia
            if (grupos.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 48),
                child: Column(
                  children: [
                    Icon(
                        pesquisando
                            ? Icons.search_off
                            : Icons.receipt_long_outlined,
                        size: 48,
                        color: AppColors.hint),
                    const SizedBox(height: 12),
                    Text(
                        pesquisando
                            ? 'Nada encontrado para "$_termo"'
                            : 'Nenhum gasto aqui',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                        pesquisando
                            ? 'A busca olha todos os meses'
                            : 'Toque no + para adicionar',
                        style: const TextStyle(color: AppColors.muted)),
                  ],
                ),
              ),
            for (final entry in grupos.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 8),
                child: Text(
                    (entry.key.year == anoAtual
                            ? diaPorExtenso(entry.key)
                            : '${diaPorExtenso(entry.key)} de ${entry.key.year}')
                        .toUpperCase(),
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
