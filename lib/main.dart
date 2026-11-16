import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/app_data.dart';
import 'routes.dart';
import 'screens/acertos_screen.dart';
import 'screens/cadastro_screen.dart';
import 'screens/casa_screen.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'screens/moradores_screen.dart';
import 'screens/novo_gasto_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!SupabaseConfig.configurado) {
    runApp(const _ConfiguracaoFaltando());
    return;
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  // Já logado neste celular? Abre direto, mesmo sem internet.
  var rotaInicial = Rotas.login;
  if (Supabase.instance.client.auth.currentUser != null) {
    try {
      await AppData.instance.abrir();
      rotaInicial = AppData.instance.temCasa ? Rotas.home : Rotas.casa;
    } catch (e) {
      debugPrint('Falha ao abrir dados locais: $e');
    }
  }

  runApp(ApeSyncApp(rotaInicial: rotaInicial));
}

class ApeSyncApp extends StatelessWidget {
  final String rotaInicial;
  const ApeSyncApp({super.key, this.rotaInicial = Rotas.login});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ApeSync',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      initialRoute: rotaInicial,
      routes: {
        Rotas.login: (_) => const LoginScreen(),
        Rotas.cadastro: (_) => const CadastroScreen(),
        Rotas.casa: (_) => const CasaScreen(),
        Rotas.home: (_) => const HomeShell(),
        Rotas.novoGasto: (_) => const NovoGastoScreen(),
        Rotas.acertos: (_) => const AcertosScreen(),
        Rotas.moradores: (_) => const MoradoresScreen(),
      },
    );
  }
}

/// Aparece se lib/config.dart ainda não tiver a URL e a chave do Supabase.
class _ConfiguracaoFaltando extends StatelessWidget {
  const _ConfiguracaoFaltando();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'Configure o Supabase em lib/config.dart\n'
              '(Project URL e anon key em Supabase → Project Settings → API).',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }
}
