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
  if (e is AuthException) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login')) return 'E-mail ou senha incorretos';
    if (m.contains('already registered')) return 'Este e-mail já tem conta';
    if (m.contains('email not confirmed')) {
      return 'Confirme seu e-mail antes de entrar';
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
