import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import '../widgets/common.dart';
import 'fluxo.dart';

class CadastroScreen extends StatefulWidget {
  const CadastroScreen({super.key});

  @override
  State<CadastroScreen> createState() => _CadastroScreenState();
}

class _CadastroScreenState extends State<CadastroScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nome = TextEditingController();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  final _confirmar = TextEditingController();
  bool _senhaVisivel = false;
  bool _carregando = false;

  @override
  void dispose() {
    for (final c in [_nome, _email, _senha, _confirmar]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _criarConta() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _carregando = true);
    try {
      final r = await Supabase.instance.client.auth.signUp(
        email: _email.text.trim(),
        password: _senha.text,
        data: {'nome': _nome.text.trim()},
      );
      if (!mounted) return;
      if (r.session == null) {
        // Projeto com confirmação de e-mail ligada.
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Conta criada! Confirme o e-mail e depois entre.')));
        Navigator.pop(context);
        return;
      }
      await entrarNoApp(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensagemErro(e))));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Widget _campoSenha(TextEditingController c, String label, String hint,
      String? Function(String?) validator) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        TextFormField(
          controller: c,
          obscureText: !_senhaVisivel,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_senhaVisivel
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined),
              onPressed: () => setState(() => _senhaVisivel = !_senhaVisivel),
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SquareIconButton(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Criar conta',
                    style:
                        TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text('Leva menos de um minuto.',
                    style: TextStyle(fontSize: 15, color: AppColors.muted)),
                const SizedBox(height: 28),
                const FieldLabel('Nome'),
                TextFormField(
                  controller: _nome,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Seu nome',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Informe seu nome'
                      : null,
                ),
                const SizedBox(height: 16),
                const FieldLabel('E-mail'),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'seu@email.com',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                  validator: (v) => (v == null || !v.contains('@'))
                      ? 'Informe um e-mail válido'
                      : null,
                ),
                const SizedBox(height: 16),
                _campoSenha(
                  _senha,
                  'Senha',
                  'Mínimo 8 caracteres',
                  (v) => (v == null || v.length < 8)
                      ? 'A senha precisa ter 8 caracteres ou mais'
                      : null,
                ),
                const SizedBox(height: 16),
                _campoSenha(
                  _confirmar,
                  'Confirmar senha',
                  'Repita a senha',
                  (v) => v != _senha.text ? 'As senhas não conferem' : null,
                ),
                const SizedBox(height: 28),
                FilledButton(
                    onPressed: _carregando ? null : _criarConta,
                    child: _carregando
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white))
                        : const Text('Criar conta')),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Já tem conta? ',
                        style: TextStyle(color: AppColors.muted)),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Text('Entrar',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
