import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import '../widgets/common.dart';
import 'fluxo.dart';

/// "Esqueci minha senha".
///
/// 1. A pessoa informa o e-mail e o Supabase manda o e-mail "Reset password".
/// 2. Ela toca no link **no celular**: o link abre o app (apesync://
///    recuperar-senha) já logado, e o main.dart mostra esta tela no modo
///    [senhaNova] para escolher a senha nova.
///
/// Se o projeto tiver SMTP próprio e o e-mail mostrar o código ({{ .Token }}),
/// também dá para digitar o código em vez de tocar no link.
class RecuperarSenhaScreen extends StatefulWidget {
  /// true = chegou pelo link do e-mail (já logado): só escolhe a senha nova.
  final bool senhaNova;
  const RecuperarSenhaScreen({super.key, this.senhaNova = false});

  /// Para onde o link do e-mail leva (precisa estar em Supabase →
  /// Authentication → URL Configuration → Redirect URLs).
  static const linkDoApp = 'apesync://recuperar-senha';

  @override
  State<RecuperarSenhaScreen> createState() => _RecuperarSenhaScreenState();
}

enum _Passo { email, emailEnviado, senha }

class _RecuperarSenhaScreenState extends State<RecuperarSenhaScreen> {
  static const _esperaReenvio = 60; // o Supabase recusa pedidos mais rápidos

  final _formEmail = GlobalKey<FormState>();
  final _formSenha = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _codigo = TextEditingController();
  final _senha = TextEditingController();
  final _confirmar = TextEditingController();

  late _Passo _passo = widget.senhaNova ? _Passo.senha : _Passo.email;

  /// Já logado pelo link (ou código já conferido): falta só a senha.
  late bool _logado = widget.senhaNova;
  bool _carregando = false;
  bool _senhaVisivel = false;
  int _segundos = 0;
  Timer? _timer;
  bool _leuArgumento = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_leuArgumento) return;
    _leuArgumento = true;
    final email = ModalRoute.of(context)?.settings.arguments;
    if (email is String) _email.text = email;
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in [_email, _codigo, _senha, _confirmar]) {
      c.dispose();
    }
    super.dispose();
  }

  void _avisar(String texto) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(texto)));

  void _contarReenvio() {
    _timer?.cancel();
    setState(() => _segundos = _esperaReenvio);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _segundos--);
      if (_segundos <= 0) t.cancel();
    });
  }

  Future<void> _enviarEmail() async {
    if (!_formEmail.currentState!.validate()) return;
    setState(() => _carregando = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        _email.text.trim(),
        redirectTo: RecuperarSenhaScreen.linkDoApp,
      );
      if (!mounted) return;
      setState(() => _passo = _Passo.emailEnviado);
      _contarReenvio();
    } catch (e) {
      if (mounted) _avisar(mensagemErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvarSenha() async {
    if (!_formSenha.currentState!.validate()) return;
    setState(() => _carregando = true);
    final auth = Supabase.instance.client.auth;
    try {
      if (!_logado) {
        await auth.verifyOTP(
          type: OtpType.recovery,
          email: _email.text.trim(),
          token: _codigo.text.trim(),
        );
        _logado = true; // o código só vale uma vez
      }
      await auth.updateUser(UserAttributes(password: _senha.text));
      if (!mounted) return;
      _avisar('Senha alterada!');
      await entrarNoApp(context);
    } catch (e) {
      if (mounted) _avisar(mensagemErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  /// Voltar: pelo link a pessoa já está logada, então segue para o app.
  void _voltar() {
    if (widget.senhaNova) {
      entrarNoApp(context);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = _email.text.trim();
    final (titulo, texto) = switch (_passo) {
      _Passo.email => (
          'Recuperar senha',
          'Informe o e-mail da sua conta. Vamos mandar um e-mail para você '
              'criar uma senha nova.'
        ),
      _Passo.emailEnviado => ('Confira seu e-mail', ''),
      _Passo.senha when _logado => (
          'Criar senha nova',
          'Escolha a senha nova da sua conta.'
        ),
      _Passo.senha => (
          'Digite o código',
          'Digite o código que chegou em $email e escolha a senha nova.'
        ),
    };

    return PopScope(
      canPop: !widget.senhaNova,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _voltar();
      },
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child:
                      SquareIconButton(icon: Icons.arrow_back, onTap: _voltar),
                ),
                const SizedBox(height: 20),
                Text(titulo,
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.w700)),
                if (texto.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(texto,
                      style: const TextStyle(
                          fontSize: 15, color: AppColors.muted)),
                ],
                const SizedBox(height: 28),
                switch (_passo) {
                  _Passo.email => _passoEmail(),
                  _Passo.emailEnviado => _passoEmailEnviado(email),
                  _Passo.senha => _passoSenha(),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _botao(String texto, VoidCallback onPressed) => FilledButton(
        onPressed: _carregando ? null : onPressed,
        child: _carregando
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white))
            : Text(texto),
      );

  Widget _passoEmail() {
    return Form(
      key: _formEmail,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FieldLabel('E-mail'),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofocus: _email.text.isEmpty,
            decoration: const InputDecoration(
              hintText: 'seu@email.com',
              prefixIcon: Icon(Icons.mail_outline),
            ),
            validator: (v) => (v == null || !v.contains('@'))
                ? 'Informe um e-mail válido'
                : null,
          ),
          const SizedBox(height: 28),
          _botao('Enviar e-mail', _enviarEmail),
        ],
      ),
    );
  }

  Widget _passoEmailEnviado(String email) {
    Widget item(IconData icone, String texto) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icone, size: 20, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(texto, style: const TextStyle(fontSize: 15))),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              item(Icons.mail_outline,
                  'Mandamos um e-mail para $email (confira também o spam).'),
              item(Icons.smartphone,
                  'Abra o e-mail NESTE celular e toque em "Reset password".'),
              item(Icons.lock_reset,
                  'O ApêSync abre sozinho para você criar a senha nova.'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: _carregando || _segundos > 0 ? null : _enviarEmail,
          child: Text(_segundos > 0
              ? 'Reenviar e-mail em ${_segundos}s'
              : 'Reenviar e-mail'),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: () => setState(() => _passo = _Passo.email),
              child: const Text('Trocar e-mail'),
            ),
            TextButton(
              onPressed: () => setState(() => _passo = _Passo.senha),
              child: const Text('Recebi um código'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _passoSenha() {
    return Form(
      key: _formSenha,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_logado) ...[
            const FieldLabel('Código do e-mail'),
            TextFormField(
              controller: _codigo,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              decoration: const InputDecoration(
                hintText: '123456',
                prefixIcon: Icon(Icons.pin_outlined),
              ),
              validator: (v) => (v == null || v.trim().length < 6)
                  ? 'Digite o código que chegou no e-mail'
                  : null,
            ),
            const SizedBox(height: 16),
          ],
          _campoSenha(
            _senha,
            'Nova senha',
            'Mínimo 8 caracteres',
            (v) => (v == null || v.length < 8)
                ? 'A senha precisa ter 8 caracteres ou mais'
                : null,
          ),
          const SizedBox(height: 16),
          _campoSenha(
            _confirmar,
            'Confirmar nova senha',
            'Repita a senha',
            (v) => v != _senha.text ? 'As senhas não conferem' : null,
          ),
          const SizedBox(height: 28),
          _botao('Salvar nova senha', _salvarSenha),
          if (!_logado) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: _carregando
                  ? null
                  : () => setState(() => _passo = _Passo.emailEnviado),
              child: const Text('Voltar'),
            ),
          ],
        ],
      ),
    );
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
}
