import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../data/app_data.dart';
import '../data/pix.dart';
import '../theme.dart';

/// Cadastrar, trocar ou remover a MINHA chave PIX.
Future<void> editarMinhaChavePix(BuildContext context) async {
  final data = AppData.instance;
  final atual = data.meuMorador?.chavePix;
  final messenger = ScaffoldMessenger.of(context);
  final resultado = await showDialog<_ResultadoChave>(
    context: context,
    builder: (_) => _DialogoChavePix(atual: atual),
  );
  if (resultado == null) return;
  await data.salvarMinhaChavePix(resultado.chave);
  messenger.showSnackBar(SnackBar(
      content: Text(
          resultado.chave == null ? 'Chave PIX removida' : 'Chave PIX salva')));
}

class _ResultadoChave {
  final String? chave;
  const _ResultadoChave(this.chave);
}

class _DialogoChavePix extends StatefulWidget {
  final String? atual;
  const _DialogoChavePix({this.atual});

  @override
  State<_DialogoChavePix> createState() => _DialogoChavePixState();
}

class _DialogoChavePixState extends State<_DialogoChavePix> {
  late TipoChavePix _tipo =
      widget.atual == null ? TipoChavePix.celular : Pix.tipoDe(widget.atual!);
  late final _controle = TextEditingController(
      text: widget.atual?.startsWith('+55') == true
          ? widget.atual!.substring(3)
          : widget.atual ?? '');
  String? _erro;

  @override
  void dispose() {
    _controle.dispose();
    super.dispose();
  }

  void _salvar() {
    final chave = Pix.normalizar(_tipo, _controle.text);
    if (chave == null) {
      setState(() => _erro = '${_tipo.label} inválido. Ex.: ${_tipo.exemplo}');
      return;
    }
    Navigator.pop(context, _ResultadoChave(chave));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Minha chave PIX'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Os moradores da casa veem a sua chave para te pagar pelo PIX. '
              'Só você consegue alterá-la.',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<TipoChavePix>(
              initialValue: _tipo,
              decoration: const InputDecoration(labelText: 'Tipo de chave'),
              items: [
                for (final t in TipoChavePix.values)
                  DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged: (t) => setState(() {
                _tipo = t ?? _tipo;
                _erro = null;
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controle,
              autofocus: widget.atual == null,
              keyboardType: switch (_tipo) {
                TipoChavePix.email => TextInputType.emailAddress,
                TipoChavePix.aleatoria => TextInputType.text,
                _ => TextInputType.phone,
              },
              decoration: InputDecoration(
                labelText: _tipo.label,
                hintText: _tipo.exemplo,
                errorText: _erro,
              ),
              onSubmitted: (_) => _salvar(),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.atual != null)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, const _ResultadoChave(null)),
            style: TextButton.styleFrom(foregroundColor: AppColors.negative),
            child: const Text('Remover'),
          ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: _salvar,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

/// Janela de PIX de uma transferência dos acertos.
/// - Se EU pago: mostra a chave de quem recebe e o "copia e cola" com o
///   valor (para colar no app do banco) e oferece registrar o pagamento.
/// - Se EU recebo: mostra o QR code e o "copia e cola" da minha chave para
///   cobrar (pessoalmente ou mandando pelo WhatsApp).
Future<void> mostrarPix(
  BuildContext context, {
  required Transferencia t,
  required VoidCallback onRegistrar,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _PixSheet(t: t, onRegistrar: onRegistrar),
  );
}

class _PixSheet extends StatelessWidget {
  final Transferencia t;
  final VoidCallback onRegistrar;
  const _PixSheet({required this.t, required this.onRegistrar});

  @override
  Widget build(BuildContext context) {
    final data = AppData.instance;
    final recebedor = data.morador(t.paraId);
    final chave = recebedor.chavePix!;
    final souEuQuemPaga = t.deId == data.euId;
    final codigo = Pix.copiaECola(
      chave: chave,
      nome: recebedor.nome,
      valorCentavos: t.valorCentavos,
    );
    final valor = formatarReais(t.valorCentavos);

    void copiar(String texto, String aviso) {
      Clipboard.setData(ClipboardData(text: texto));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(aviso)));
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              souEuQuemPaga
                  ? 'Pagar $valor para ${recebedor.nome}'
                  : 'Cobrar $valor de ${data.nomeDe(t.deId)}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              souEuQuemPaga
                  ? 'Copie o código e cole no app do seu banco, em '
                      '"Pix Copia e Cola". O valor já vai preenchido.'
                  : 'Mostre o QR code para a pessoa escanear no app do banco, '
                      'ou mande o código pelo WhatsApp.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: QrImageView(
                  data: codigo,
                  size: souEuQuemPaga ? 160 : 220,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => copiar(codigo, 'Código PIX copiado'),
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copiar PIX copia e cola'),
            ),
            const SizedBox(height: 8),
            if (souEuQuemPaga)
              OutlinedButton.icon(
                onPressed: () => copiar(chave, 'Chave PIX copiada'),
                icon: const Icon(Icons.key_outlined, size: 18),
                label: Text('Copiar só a chave ($chave)',
                    overflow: TextOverflow.ellipsis),
              )
            else
              OutlinedButton.icon(
                onPressed: () => SharePlus.instance.share(ShareParams(
                  text: 'Oi! Segue o PIX de $valor dos gastos da casa '
                      '"${data.nomeCasa}" (ApeSync). Copie e cole no app do '
                      'banco, em "Pix Copia e Cola":\n\n$codigo',
                )),
                icon: const Icon(Icons.share_outlined, size: 18),
                label: const Text('Mandar cobrança'),
              ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              souEuQuemPaga
                  ? 'Depois de pagar no banco, registre aqui para zerar a dívida.'
                  : 'Quando receber, registre o pagamento para zerar a dívida.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                onRegistrar();
              },
              icon: const Icon(Icons.check),
              label: Text(souEuQuemPaga
                  ? 'Já paguei — registrar'
                  : 'Já recebi — registrar'),
            ),
          ],
        ),
      ),
    );
  }
}
