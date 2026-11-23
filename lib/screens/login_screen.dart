import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../routes.dart';
import '../services/login_google.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'fluxo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  bool _senhaVisivel = false;
  bool _carregando = false;
  bool _carregandoGoogle = false;

  bool get _ocupado => _carregando || _carregandoGoogle;

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _carregando = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _senha.text,
      );
      if (!mounted) return;
      await entrarNoApp(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensagemErro(e))));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  /// Primeira vez com Google cria a conta sozinha; se o e-mail já tinha conta
  /// com senha, o Supabase junta as duas (mesma casa e histórico).
  Future<void> _entrarComGoogle() async {
    setState(() => _carregandoGoogle = true);
    try {
      final entrou = await LoginGoogle.entrar();
      if (!entrou || !mounted) return;
      await entrarNoApp(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensagemErro(e))));
    } finally {
      if (mounted) setState(() => _carregandoGoogle = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverFillRemaining(
                hasScrollBody: false,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 48),
                      const Align(
                          alignment: Alignment.centerLeft, child: AppLogo()),
                      const SizedBox(height: 24),
                      const Text('ApeSync',
                          style: TextStyle(
                              fontSize: 32, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      const Text(
                        'Divida contas e tarefas da sua casa sem estresse.',
                        style:
                            TextStyle(fontSize: 16, color: AppColors.muted),
                      ),
                      const SizedBox(height: 40),
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
                      const FieldLabel('Senha'),
                      TextFormField(
                        controller: _senha,
                        obscureText: !_senhaVisivel,
                        decoration: InputDecoration(
                          hintText: 'Sua senha',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_senhaVisivel
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                            onPressed: () => setState(
                                () => _senhaVisivel = !_senhaVisivel),
                          ),
                        ),
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'Informe sua senha'
                            : null,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _ocupado
                              ? null
                              : () => Navigator.pushNamed(
                                  context, Rotas.recuperarSenha,
                                  arguments: _email.text.trim()),
                          child: const Text('Esqueci minha senha',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                          onPressed: _ocupado ? null : _entrar,
                          child: _carregando
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5, color: Colors.white))
                              : const Text('Entrar')),
                      const SizedBox(height: 24),
                      const Row(
                        children: [
                          Expanded(child: Divider(color: AppColors.border)),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text('ou',
                                style: TextStyle(color: AppColors.muted)),
                          ),
                          Expanded(child: Divider(color: AppColors.border)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        onPressed: _ocupado ? null : _entrarComGoogle,
                        icon: _carregandoGoogle
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Text('G',
                                style: TextStyle(
                                    color: AppColors.blue,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 17)),
                        label: const Text('Continuar com Google'),
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.only(top: 24, bottom: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('Não tem conta? ',
                                style: TextStyle(color: AppColors.muted)),
                            GestureDetector(
                              onTap: () =>
                                  Navigator.pushNamed(context, Rotas.cadastro),
                              child: Text('Cadastre-se',
                                  style: TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
