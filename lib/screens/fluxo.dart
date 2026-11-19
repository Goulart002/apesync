import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/app_data.dart';
import '../routes.dart';

/// Depois de logar: abre o banco local, procura a casa do usuário
/// (primeiro no celular, depois no servidor) e vai para Home ou "Sua casa".
Future<void> entrarNoApp(BuildContext context) async {
  final data = AppData.instance;
  await data.abrir();
  if (!data.temCasa) {
    try {
      await data.buscarCasaNoServidor();
    } catch (_) {
      // Sem internet: segue para "Sua casa".
    }
  }
  if (!context.mounted) return;
  Navigator.pushNamedAndRemoveUntil(
      context, data.temCasa ? Rotas.home : Rotas.casa, (_) => false);
}

/// Mensagem amigável para erros do Supabase / rede.
String mensagemErro(Object e) {
  if (e is AvisoApp) return e.mensagem;
  if (e is AuthException) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login')) return 'E-mail ou senha incorretos';
    if (m.contains('already registered')) return 'Este e-mail já tem conta';
    if (m.contains('email not confirmed')) {
      return 'Confirme seu e-mail antes de entrar';
    }
    // Recuperar senha
    if (m.contains('link is invalid or has expired')) {
      return 'O link venceu ou já foi usado. Peça outro e-mail.';
    }
    if (m.contains('code verifier')) {
      return 'Abra o link no mesmo celular em que pediu a recuperação';
    }
    if (m.contains('token has expired') || m.contains('otp')) {
      return 'Código errado ou vencido. Confira o e-mail ou peça outro.';
    }
    if (m.contains('only request this after')) {
      return 'Espere um minuto antes de pedir outro código';
    }
    if (m.contains('rate limit')) {
      return 'Muitos e-mails enviados. Espere alguns minutos e tente de novo.';
    }
    if (m.contains('different from the old password')) {
      return 'A senha nova precisa ser diferente da antiga';
    }
    if (m.contains('password should be')) {
      return 'Senha fraca: use 8 caracteres ou mais';
    }
    // Login com Google (configuração do Supabase)
    if (m.contains('provider is not enabled') ||
        m.contains('unsupported provider')) {
      return 'O login com Google não está ativado no Supabase '
          '(README → Login com Google)';
    }
    if (m.contains('audience')) {
      return 'O ID do cliente Google do app não está no Supabase '
          '(README → Login com Google)';
    }
    if (m.contains('nonce')) {
      return 'O Google não confirmou o login. Tente de novo.';
    }
    return e.message;
  }
  if (e is PostgrestException) {
    if (e.message.contains('Código de convite inválido')) {
      return 'Código de convite inválido';
    }
    return e.message;
  }
  final s = e.toString();
  if (s.contains('SocketException') ||
      s.contains('Failed host lookup') ||
      s.contains('ClientException')) {
    return 'Sem conexão com a internet';
  }
  return 'Algo deu errado. Tente de novo.';
}
