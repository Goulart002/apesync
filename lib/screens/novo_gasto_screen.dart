import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/app_data.dart';
import '../services/nota_scanner.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'fluxo.dart';

/// Criar (sem argumento) ou editar/excluir (argumento: [Gasto]) um gasto,
/// com divisão igualitária entre os moradores.
/// Só quem lançou o gasto ou o administrador edita; os demais veem os
/// detalhes em modo somente leitura.
/// Retorna `true` via Navigator.pop quando um gasto novo é salvo.
class NovoGastoScreen extends StatefulWidget {
  const NovoGastoScreen({super.key});

  @override
  State<NovoGastoScreen> createState() => _NovoGastoScreenState();
}

class _NovoGastoScreenState extends State<NovoGastoScreen> {
  final _data = AppData.instance;
  final _formKey = GlobalKey<FormState>();
  final _valor = TextEditingController();
  final _descricao = TextEditingController();
  Categoria _categoria = Categoria.mercado;
  late String _pagoPor = _data.euId.isNotEmpty
      ? _data.euId
      : (_data.moradores.isEmpty ? '' : _data.moradores.first.id);
  DateTime _dia = DateTime.now();
  Set<String> _divididoEntre = {};
  Gasto? _editando;
  bool _somenteLeitura = false;
  bool _podeExcluir = false;
  bool _carregou = false;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _divididoEntre = _data.moradores.map((m) => m.id).toSet();
  }

  /// Se a tela foi aberta com um gasto como argumento, entra em modo edição.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_carregou) return;
    _carregou = true;
    final arg = ModalRoute.of(context)?.settings.arguments;
    if (arg is Gasto) {
      _editando = arg;
      // Ajuste (dívida de quem foi removido): nunca é editado; o admin só
      // pode excluí-lo depois que a pessoa voltar para a casa.
      _somenteLeitura =
          arg.categoria.ehAjuste || !_data.permissoes.podeEditarGasto(arg);
      _podeExcluir = arg.categoria.ehAjuste
          ? _data.podeExcluirAjuste(arg)
          : !_somenteLeitura;
      final v = arg.valorCentavos;
      _valor.text = '${v ~/ 100},${(v % 100).toString().padLeft(2, '0')}';
      _descricao.text = arg.descricao;
      _categoria = arg.categoria;
      _pagoPor = arg.pagoPorId;
      _dia = arg.data;
      _divididoEntre = arg.divididoEntre.toSet();
    }
    // Registrado depois de preencher o valor (edição), para não chamar
    // setState durante a montagem da tela.
    _valor.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _valor.dispose();
    _descricao.dispose();
    super.dispose();
  }

  int get _valorCentavos => parseReais(_valor.text) ?? 0;

  int get _parteCada => _divididoEntre.isEmpty
      ? 0
      : (_valorCentavos / _divididoEntre.length).round();

  Future<void> _escolherPagador() async {
    final escolhido = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Quem pagou?',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            for (final m in _data.moradores)
              ListTile(
                leading: Avatar(m),
                title: Text(m.nome),
                trailing: m.id == _pagoPor
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(context, m.id),
              ),
          ],
        ),
      ),
    );
    if (escolhido != null) setState(() => _pagoPor = escolhido);
  }

  Future<void> _escolherData() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _dia,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _dia = d);
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_divididoEntre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione ao menos um morador')),
      );
      return;
    }
    if (_pagoPor.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escolha quem pagou')),
      );
      return;
    }
    setState(() => _salvando = true);
    final editando = _editando;
    // Mantém a ordem da lista de moradores (define quem recebe o centavo
    // que sobra na divisão).
    final ordem = [
      ..._data.moradores.map((m) => m.id).where(_divididoEntre.contains),
      ..._divididoEntre.where((id) => !_data.moradores.any((m) => m.id == id)),
    ];
    try {
      await _data.salvarGasto(Gasto(
        id: editando?.id ?? _data.novoId(), // mesmo id = UPDATE; novo = INSERT
        casaId: _data.casa!.id,
        descricao: _descricao.text.trim(),
        valorCentavos: _valorCentavos,
        categoria: _categoria,
        pagoPorId: _pagoPor,
        divididoEntre: ordem,
        data: _dia,
        criadoPor: editando?.criadoPor ?? _data.usuarioId,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensagemErro(e))));
      return;
    }
    if (!mounted) return;
    if (editando != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Gasto atualizado')));
    }
    Navigator.pop(context, true);
  }

  Future<void> _excluir() async {
    final g = _editando!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir gasto'),
        content: Text(
            'Excluir "${g.descricao}" (${formatarReais(g.valorCentavos)})? '
            'Os saldos de todos serão recalculados.'),
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
      await _data.excluirGasto(g);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensagemErro(e))));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Gasto excluído')));
    Navigator.pop(context);
  }

  /// Escaneia uma nota fiscal e pré-preenche o formulário.
  Future<void> _escanearNota() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!NotaScanner.suportado) {
      messenger.showSnackBar(const SnackBar(
          content: Text('O scanner de nota funciona só no celular')));
      return;
    }

    final origem = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tirar foto da nota'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (origem == null || !mounted) return;

    NotaLida? nota;
    // Mostra "lendo..." enquanto o OCR roda.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Lendo a nota...')),
          ],
        ),
      ),
    );
    try {
      nota = await NotaScanner.escanear(origem);
    } catch (e) {
      nota = null;
      debugPrint('Erro no scanner de nota: $e');
      messenger.showSnackBar(const SnackBar(
          content: Text('Não foi possível ler a imagem. Tente outra foto.')));
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
    if (!mounted || nota == null) return;
    final lida = nota;

    if (lida.vazia) {
      messenger.showSnackBar(const SnackBar(
          content:
              Text('Não encontrei os dados da nota. Preencha manualmente.')));
      return;
    }

    setState(() {
      final v = lida.valorCentavos;
      if (v != null) {
        _valor.text = '${v ~/ 100},${(v % 100).toString().padLeft(2, '0')}';
      }
      if (lida.estabelecimento != null) {
        _descricao.text = lida.estabelecimento!;
      }
      if (lida.data != null) _dia = lida.data!;
      if (lida.categoria != null) _categoria = lida.categoria!;
    });
    messenger.showSnackBar(SnackBar(
      content: Text(lida.valorCentavos == null
          ? 'Não achei o total. Confira e digite o valor.'
          : 'Nota lida! Confira os dados antes de salvar.'),
    ));
  }

  String _textoSomenteLeitura() {
    final g = _editando!;
    if (g.categoria.ehAjuste) {
      final nome = _data.morador(g.pagoPorId).nome;
      return 'Ajuste criado ao remover $nome da casa, que estava devendo: '
          'o valor foi dividido entre quem ficou. '
          '${_podeExcluir ? 'Excluir este ajuste faz a dívida voltar para $nome.' : 'Para desfazer, $nome precisa voltar para a casa e o administrador exclui o ajuste.'}';
    }
    return 'Lançado por ${_data.nomeDoUsuario(g.criadoPor)}. Só quem lançou '
        'o gasto ou o administrador da casa pode alterá-lo.';
  }

  Widget _campoSelecao(String texto, IconData icone, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(suffixIcon: Icon(icone)),
        child: Text(texto, style: const TextStyle(fontSize: 15)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  children: [
                    // Barra superior
                    Row(
                      children: [
                        SquareIconButton(
                            icon: Icons.close,
                            onTap: () => Navigator.pop(context)),
                        Expanded(
                          child: Text(
                              _editando == null
                                  ? 'Novo gasto'
                                  : _somenteLeitura
                                      ? 'Detalhes do gasto'
                                      : 'Editar gasto',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w600)),
                        ),
                        if (_editando == null || !_podeExcluir)
                          const SizedBox(width: 40)
                        else
                          SquareIconButton(
                              icon: Icons.delete_outline, onTap: _excluir),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (_somenteLeitura)
                      // Gasto de outra pessoa: só os detalhes.
                      AppCard(
                        color: AppColors.blueLight,
                        border: const Border(),
                        child: Row(
                          children: [
                            const Icon(Icons.lock_outline,
                                color: AppColors.blue),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _textoSomenteLeitura(),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      // Scanner de nota fiscal
                      OutlinedButton.icon(
                        onPressed: _escanearNota,
                        icon: const Icon(Icons.document_scanner_outlined,
                            color: AppColors.primary),
                        label: const Text('Escanear nota fiscal'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: AppColors.primaryLight,
                          foregroundColor: AppColors.primary,
                          side: BorderSide.none,
                        ),
                      ),
                    const SizedBox(height: 16),

                    // Somente leitura: bloqueia toques nos campos (a rolagem
                    // continua funcionando).
                    AbsorbPointer(
                      absorbing: _somenteLeitura,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Valor em destaque
                          const Text('Valor total',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.muted)),
                          TextFormField(
                            controller: _valor,
                            textAlign: TextAlign.center,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            style: const TextStyle(
                                fontSize: 44,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -1),
                            decoration: const InputDecoration(
                              prefixText: 'R\$ ',
                              hintText: '0,00',
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
                            ),
                            validator: (v) => parseReais(v ?? '') == null
                                ? 'Informe um valor maior que zero'
                                : null,
                          ),
                          const SizedBox(height: 12),

                          const FieldLabel('Descrição'),
                          TextFormField(
                            controller: _descricao,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                                hintText: 'Ex.: Gás de cozinha'),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Descreva o gasto'
                                : null,
                          ),
                          const SizedBox(height: 16),

                          const FieldLabel('Categoria'),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final c in [
                                ...CategoriaInfo.lancaveis,
                                if (_categoria.ehAjuste) Categoria.ajuste,
                              ])
                                ChoiceChip(
                                  avatar: Icon(c.icon,
                                      size: 18,
                                      color: c == _categoria
                                          ? Colors.white
                                          : AppColors.text),
                                  label: Text(c.label),
                                  selected: c == _categoria,
                                  showCheckmark: false,
                                  onSelected: (_) =>
                                      setState(() => _categoria = c),
                                  selectedColor: AppColors.primary,
                                  backgroundColor: AppColors.card,
                                  labelStyle: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      color: c == _categoria
                                          ? Colors.white
                                          : AppColors.text),
                                  side: BorderSide(
                                      color: c == _categoria
                                          ? AppColors.primary
                                          : AppColors.border),
                                  shape: const StadiumBorder(),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const FieldLabel('Quem pagou'),
                                    _campoSelecao(
                                        _pagoPor.isEmpty
                                            ? 'Escolher'
                                            : _data.morador(_pagoPor).nome,
                                        Icons.expand_more,
                                        _escolherPagador),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const FieldLabel('Data'),
                                    _campoSelecao(
                                        dataCurta(_dia),
                                        Icons.calendar_today_outlined,
                                        _escolherData),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),

                          // Divisão
                          Row(
                            children: [
                              const Expanded(
                                  child:
                                      FieldLabel('Dividir igualmente entre')),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text('${formatarReais(_parteCada)} cada',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primary)),
                              ),
                            ],
                          ),
                          AppCard(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            child: Column(
                              children: [
                                for (final m in _data.moradores)
                                  InkWell(
                                    onTap: () => setState(() {
                                      if (!_divididoEntre.remove(m.id)) {
                                        _divididoEntre.add(m.id);
                                      }
                                    }),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4),
                                      child: Row(
                                        children: [
                                          Checkbox(
                                            value:
                                                _divididoEntre.contains(m.id),
                                            onChanged: (v) => setState(() {
                                              if (v == true) {
                                                _divididoEntre.add(m.id);
                                              } else {
                                                _divididoEntre.remove(m.id);
                                              }
                                            }),
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(6)),
                                          ),
                                          Avatar(m, size: 30),
                                          const SizedBox(width: 12),
                                          Expanded(
                                              child: Text(m.nome,
                                                  style: const TextStyle(
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w500))),
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(right: 8),
                                            child: Text(
                                              _divididoEntre.contains(m.id)
                                                  ? formatarReais(_parteCada)
                                                  : '—',
                                              style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (!_somenteLeitura)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: FilledButton(
                      onPressed: _salvando ? null : _salvar,
                      child: Text(_editando == null
                          ? 'Salvar gasto'
                          : 'Salvar alterações')),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
