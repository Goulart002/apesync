import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../routes.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'fluxo.dart';

/// "Sua casa": criar uma casa nova (funciona offline) ou entrar numa
/// existente pelo código de convite (precisa de internet).
class CasaScreen extends StatefulWidget {
  const CasaScreen({super.key});

  @override
  State<CasaScreen> createState() => _CasaScreenState();
}

class _CasaScreenState extends State<CasaScreen> {
  final _nomeCasa = TextEditingController();
  final _codigo = TextEditingController();
  bool _criando = false;
  bool _entrando = false;

  @override
  void dispose() {
    _nomeCasa.dispose();
    _codigo.dispose();
    super.dispose();
  }

  void _aviso(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _criar() async {
    if (_nomeCasa.text.trim().isEmpty) {
      _aviso('Dê um nome para a casa');
      return;
    }
    setState(() => _criando = true);
    try {
      await AppData.instance.criarCasa(_nomeCasa.text);
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, Rotas.home, (_) => false);
    } catch (e) {
      if (mounted) _aviso(mensagemErro(e));
    } finally {
      if (mounted) setState(() => _criando = false);
    }
  }

  Future<void> _entrar() async {
    if (_codigo.text.trim().length != 6) {
      _aviso('O código tem 6 caracteres');
      return;
    }
    setState(() => _entrando = true);
    try {
      await AppData.instance.entrarNaCasa(_codigo.text);
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, Rotas.home, (_) => false);
    } catch (e) {
      if (mounted) _aviso(mensagemErro(e));
    } finally {
      if (mounted) setState(() => _entrando = false);
    }
  }

  Widget _tile(IconData icon, Color cor, Color fundo) => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
            color: fundo, borderRadius: BorderRadius.circular(14)),
        child: Icon(icon, color: cor, size: 26),
      );

  Widget _carregando() => const SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
          children: [
            Text('Bem-vindo, ${AppData.instance.nomeUsuario}!',
                style:
                    const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              'Crie uma casa nova ou entre na casa dos seus colegas com o código de convite.',
              style: TextStyle(fontSize: 15, color: AppColors.muted),
            ),
            const SizedBox(height: 28),

            // Criar casa
            AppCard(
              padding: const EdgeInsets.all(20),
              border: Border.all(color: AppColors.primary, width: 1.5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                      alignment: Alignment.centerLeft,
                      child: _tile(Icons.add_home_outlined, AppColors.primary,
                          AppColors.primaryLight)),
                  const SizedBox(height: 14),
                  const Text('Criar nova casa',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  const Text(
                    'Você entra como primeiro morador e recebe um código para convidar os outros.',
                    style: TextStyle(fontSize: 14, color: AppColors.muted),
                  ),
                  const SizedBox(height: 14),
                  const FieldLabel('Nome da casa'),
                  TextField(
                    controller: _nomeCasa,
                    textCapitalization: TextCapitalization.words,
                    decoration:
                        const InputDecoration(hintText: 'Ex.: República Ap. 302'),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: _criando ? null : _criar,
                    child: _criando ? _carregando() : const Text('Criar casa'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Entrar com código
            AppCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                      alignment: Alignment.centerLeft,
                      child: _tile(Icons.vpn_key_outlined, AppColors.blue,
                          AppColors.blueLight)),
                  const SizedBox(height: 14),
                  const Text('Entrar com código',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  const Text(
                    'Peça o código de 6 caracteres para quem já mora na casa. Precisa de internet.',
                    style: TextStyle(fontSize: 14, color: AppColors.muted),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _codigo,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 6),
                    decoration: const InputDecoration(
                        hintText: 'K7P2XQ', counterText: ''),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton(
                    onPressed: _entrando ? null : _entrar,
                    child: _entrando
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child:
                                CircularProgressIndicator(strokeWidth: 2.5))
                        : const Text('Entrar na casa'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () async {
                await AppData.instance.sair();
                if (!context.mounted) return;
                Navigator.pushNamedAndRemoveUntil(
                    context, Rotas.login, (_) => false);
              },
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Sair da conta'),
            ),
          ],
        ),
      ),
    );
  }
}
