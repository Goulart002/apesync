import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config_google.dart';
import '../data/app_data.dart' show AvisoApp;

/// Login com Google nativo: abre a janela de contas do Android (sem
/// navegador), o Google devolve um ID token e o Supabase troca por uma sessão.
///
/// Configuração (Google Cloud + Supabase) no README, seção "Login com Google".
class LoginGoogle {
  LoginGoogle._();

  static Future<void>? _iniciando;

  /// Número aleatório usado uma vez: o Google recebe o hash dele e o grava no
  /// token; o Supabase recebe o original e confere. Impede reaproveitar um
  /// token roubado.
  static String? _nonce;

  static bool get configurado => GoogleConfig.configurado;

  static Future<void> _inicializar() {
    final r = Random.secure();
    _nonce = base64Url.encode(List.generate(32, (_) => r.nextInt(256)));
    return GoogleSignIn.instance.initialize(
      serverClientId: GoogleConfig.webClientId,
      nonce: sha256.convert(utf8.encode(_nonce!)).toString(),
    );
  }

  /// O plugin só pode ser inicializado uma vez por execução do app.
  static Future<void> _iniciar() async {
    final f = _iniciando ??= _inicializar();
    try {
      await f;
    } catch (_) {
      _iniciando = null;
      rethrow;
    }
  }

  /// Entra com Google. Retorna false se a pessoa fechou a janela sem escolher
  /// uma conta.
  static Future<bool> entrar() async {
    if (!configurado) {
      throw const AvisoApp('O login com Google ainda não foi configurado '
          'neste app. Use e-mail e senha.');
    }
    await _iniciar();

    final GoogleSignInAccount conta;
    try {
      conta = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      final aviso = _traduzir(e);
      if (aviso == null) return false; // só cancelou
      throw aviso;
    }

    final idToken = conta.authentication.idToken;
    if (idToken == null) {
      throw const AvisoApp(
          'O Google não devolveu a identificação da conta. Tente de novo.');
    }
    await Supabase.instance.client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      nonce: _nonce,
    );
    return true;
  }

  /// Ao sair da conta: esquece a conta Google escolhida.
  static Future<void> sair() async {
    if (_iniciando == null) return;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Nada a fazer: a sessão do Supabase já foi encerrada.
    }
  }

  /// null = a pessoa só cancelou (não é erro).
  static AvisoApp? _traduzir(GoogleSignInException e) {
    final detalhe = e.description ?? '';
    switch (e.code) {
      case GoogleSignInExceptionCode.canceled:
        // "[16] Account reauth failed" chega como cancelado, mas na verdade é
        // o app não estar liberado no Google Cloud (SHA-1 ou pacote).
        if (detalhe.contains('[16]')) return _naoLiberado;
        return null;
      case GoogleSignInExceptionCode.interrupted:
        return null;
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return _naoLiberado;
      default:
        if (detalhe.contains('No credential')) {
          return const AvisoApp('Nenhuma conta Google disponível. Adicione '
              'uma conta nas configurações do celular e tente de novo.');
        }
        return AvisoApp('Não deu para entrar com Google. $detalhe'.trim());
    }
  }

  static const _naoLiberado = AvisoApp('O Google recusou o login neste '
      'aparelho. Confira o SHA-1 e o ID do cliente (README → Login com '
      'Google).');
}
