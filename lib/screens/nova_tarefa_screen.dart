import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../data/rodizio.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/tarefa_widgets.dart';
import 'fluxo.dart';

/// Criar (sem argumento) ou editar (argumento: [Tarefa]) uma tarefa da
/// casa. Quem não criou a tarefa (e não é admin) vê só os detalhes e pode
/// marcar como feita.
class NovaTarefaScreen extends StatefulWidget {
  const NovaTarefaScreen({super.key});

  @override
  State<NovaTarefaScreen> createState() => _NovaTarefaScreenState();
}

class _NovaTarefaScreenState extends State<NovaTarefaScreen> {
  static const _semana = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

  final _data = AppData.instance;
  final _titulo = TextEditingController();
  TipoTarefa _tipo = TipoTarefa.faxina;
  DateTime _dia = DateTime.now();
  Repeticao _repeticao = Repeticao.nenhuma;
  Set<int> _dias = {};
  String? _responsavel; // null = qualquer pessoa
  bool _revezar = false;
  Set<String> _noRodizio = {};
  Tarefa? _editando;
  bool _somenteLeitura = false;
  bool _carregou = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_carregou) return;
    _carregou = true;
    _responsavel = _data.euId.isEmpty ? null : _data.euId;
    _dias = {_dia.weekday};
    final arg = ModalRoute.of(context)?.settings.arguments;
    if (arg is Tarefa) {
      _editando = arg;
      _somenteLeitura = !_data.permissoes.podeEditarTarefa(arg);
      _titulo.text = arg.titulo;
      _tipo = arg.tipo;
      _dia = arg.proxima;
      _repeticao = arg.repeticao;
      _dias = arg.diasSemana.isEmpty
          ? {arg.proxima.weekday}
          : arg.diasSemana.toSet();
      _responsavel = arg.responsavelId;
      _revezar = arg.temRodizio;
      _noRodizio = arg.rodizio.toSet();
    }
  }

  @override
  void dispose() {
    _titulo.dispose();
    super.dispose();
  }

  void _aviso(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _escolherData() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _dia,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _dia = d);
  }

  Future<void> _salvar() async {
    final titulo = _titulo.text.trim();
    if (titulo.isEmpty) return _aviso('Dê um nome para a tarefa');
    if (_repeticao == Repeticao.semanal && _dias.isEmpty) {
      return _aviso('Escolha pelo menos um dia da semana');
    }
    final rodizio = _revezar && _repeticao != Repeticao.nenhuma
        ? [
            for (final m in _data.moradores)
              if (_noRodizio.contains(m.id)) m.id,
          ]
        : <String>[];
    if (_revezar && _repeticao != Repeticao.nenhuma && rodizio.length < 2) {
      return _aviso('Escolha pelo menos duas pessoas para revezar');
    }
    var responsavel = _responsavel;
    if (rodizio.isNotEmpty && !rodizio.contains(responsavel)) {
      responsavel = rodizio.first;
    }

    var t = Tarefa(
      id: _editando?.id ?? _data.novoId(),
      casaId: _data.casa!.id,
      titulo: titulo,
      tipo: _tipo,
      responsavelId: responsavel,
      rodizio: rodizio,
      repeticao: _repeticao,
      diasSemana:
          _repeticao == Repeticao.semanal ? (_dias.toList()..sort()) : const [],
      diaMes: _repeticao == Repeticao.mensal ? _dia.day : null,
      proxima: _dia,
      concluida: _editando?.concluida ?? false,
      criadoPor: _editando?.criadoPor ?? _data.usuarioId,
    );
    // Semanal num dia que não está marcado: começa no próximo dia marcado.
    if (t.repeticao == Repeticao.semanal && !_dias.contains(_dia.weekday)) {
      final primeira = Rodizio.proximaOcorrencia(
          t, DateTime(_dia.year, _dia.month, _dia.day - 1));
      if (primeira != null) t = t.copia(proxima: primeira);
    }

    try {
      await _data.salvarTarefa(t);
    } catch (e) {
      return _aviso(mensagemErro(e));
    }
    if (!mounted) return;
    _aviso(_editando == null ? 'Tarefa criada' : 'Tarefa atualizada');
    Navigator.pop(context);
  }

  Future<void> _excluir() async {
    final t = _editando!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir tarefa'),
        content: Text('Excluir "${t.titulo}"? O histórico de quem já fez '
            'continua no placar.'),
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
    if (ok != true || !mounted) return;
    try {
      await _data.excluirTarefa(t);
    } catch (e) {
      return _aviso(mensagemErro(e));
    }
    if (!mounted) return;
    _aviso('Tarefa excluída');
    Navigator.pop(context);
  }

  /// Lista "Quem faz" / "Começa com". O valor é sempre um que existe na
  /// lista (com rodízio, só quem está revezando).
  Widget _escolherQuemFaz(List<Morador> moradores) {
    final comRodizio = _revezar && _repeticao != Repeticao.nenhuma;
    final opcoes = [
      for (final m in moradores)
        if (!comRodizio || _noRodizio.contains(m.id)) m,
    ];
    final valor = opcoes.any((m) => m.id == _responsavel) ? _responsavel : null;
    return InputDecorator(
      decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: valor,
          isExpanded: true,
          items: [
            DropdownMenuItem<String?>(
                value: null,
                child: Text(
                    comRodizio ? 'O primeiro da lista' : 'Qualquer pessoa')),
            for (final m in opcoes)
              DropdownMenuItem<String?>(
                  value: m.id,
                  child:
                      Text(m.id == _data.euId ? '${m.nome} (você)' : m.nome)),
          ],
          onChanged: (v) => setState(() => _responsavel = v),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editando = _editando;
    final moradores = _data.moradores;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: [
                  Row(
                    children: [
                      SquareIconButton(
                          icon: Icons.close,
                          onTap: () => Navigator.pop(context)),
                      Expanded(
                        child: Text(
                            editando == null
                                ? 'Nova tarefa'
                                : _somenteLeitura
                                    ? 'Detalhes da tarefa'
                                    : 'Editar tarefa',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w600)),
                      ),
                      if (editando == null || _somenteLeitura)
                        const SizedBox(width: 40)
                      else
                        SquareIconButton(
                            icon: Icons.delete_outline, onTap: _excluir),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_somenteLeitura)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: AppCard(
                        color: AppColors.blueLight,
                        border: const Border(),
                        child: Row(
                          children: [
                            const Icon(Icons.lock_outline,
                                color: AppColors.blue),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Criada por ${_data.nomeDoUsuario(editando!.criadoPor)}. '
                                'Só quem criou ou o administrador altera; '
                                'qualquer um pode marcar como feita.',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  AbsorbPointer(
                    absorbing: _somenteLeitura,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const FieldLabel('Tarefa'),
                        TextField(
                          controller: _titulo,
                          maxLength: 60,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                              hintText: 'Ex.: Tirar o lixo', counterText: ''),
                        ),
                        const SizedBox(height: 16),
                        const FieldLabel('Tipo'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final t in TipoTarefa.values)
                              ChoiceChip(
                                avatar: Icon(t.icon, size: 18),
                                label: Text(t.label),
                                selected: t == _tipo,
                                showCheckmark: false,
                                onSelected: (_) => setState(() => _tipo = t),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        FieldLabel(_repeticao == Repeticao.nenhuma
                            ? 'Para quando'
                            : 'Primeira vez'),
                        InkWell(
                          onTap: _escolherData,
                          borderRadius: BorderRadius.circular(12),
                          child: InputDecorator(
                            decoration: const InputDecoration(
                                suffixIcon:
                                    Icon(Icons.calendar_today_outlined)),
                            child: Text(dataCurta(_dia),
                                style: const TextStyle(fontSize: 15)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const FieldLabel('Repetir'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final r in Repeticao.values)
                              ChoiceChip(
                                label: Text(switch (r) {
                                  Repeticao.nenhuma => 'Não repete',
                                  Repeticao.diaria => 'Todo dia',
                                  Repeticao.semanal => 'Toda semana',
                                  Repeticao.mensal => 'Todo mês',
                                }),
                                selected: r == _repeticao,
                                onSelected: (_) =>
                                    setState(() => _repeticao = r),
                              ),
                          ],
                        ),
                        if (_repeticao == Repeticao.semanal) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (var d = 1; d <= 7; d++)
                                FilterChip(
                                  label: Text(_semana[d - 1]),
                                  selected: _dias.contains(d),
                                  onSelected: (v) => setState(
                                      () => v ? _dias.add(d) : _dias.remove(d)),
                                ),
                            ],
                          ),
                        ],
                        if (_repeticao == Repeticao.mensal)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('Todo dia ${_dia.day} do mês',
                                style: const TextStyle(
                                    fontSize: 13, color: AppColors.muted)),
                          ),
                        const SizedBox(height: 16),

                        // Quem faz
                        if (_repeticao != Repeticao.nenhuma)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _revezar,
                            onChanged: (v) => setState(() {
                              _revezar = v;
                              if (v && _noRodizio.isEmpty) {
                                _noRodizio = moradores.map((m) => m.id).toSet();
                              }
                            }),
                            secondary: Icon(Icons.autorenew,
                                color: AppColors.primary),
                            title: const Text('Revezar entre moradores',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w600)),
                            subtitle: const Text(
                                'A cada vez feita, passa para o próximo',
                                style: TextStyle(fontSize: 12)),
                          ),
                        if (_revezar && _repeticao != Repeticao.nenhuma) ...[
                          const FieldLabel('Quem reveza (nesta ordem)'),
                          AppCard(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            child: Column(
                              children: [
                                for (final m in moradores)
                                  CheckboxListTile(
                                    value: _noRodizio.contains(m.id),
                                    onChanged: (v) => setState(() => v == true
                                        ? _noRodizio.add(m.id)
                                        : _noRodizio.remove(m.id)),
                                    secondary: Avatar(m, size: 30),
                                    title: Text(m.nome),
                                    controlAffinity:
                                        ListTileControlAffinity.trailing,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          const FieldLabel('Começa com'),
                        ] else
                          const FieldLabel('Quem faz'),
                        _escolherQuemFaz(moradores),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  if (editando != null && !editando.concluida) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          // Fecha os detalhes e usa o contexto do Navigator
                          // (que continua existindo) para o aviso.
                          final nav = Navigator.of(context);
                          nav.pop();
                          await concluirComDesfazer(nav.context, editando);
                        },
                        icon: const Icon(Icons.check),
                        label: const Text('Feita'),
                      ),
                    ),
                    if (!_somenteLeitura) const SizedBox(width: 12),
                  ],
                  if (!_somenteLeitura)
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _salvar,
                        child: Text(editando == null
                            ? 'Criar tarefa'
                            : 'Salvar alterações'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
