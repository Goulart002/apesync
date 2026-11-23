import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/app_data.dart';
import 'routes.dart';
import 'screens/acertos_screen.dart';
import 'screens/cadastro_screen.dart';
import 'screens/casa_screen.dart';
import 'screens/fluxo.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'screens/moradores_screen.dart';
import 'screens/nova_tarefa_screen.dart';
import 'screens/novo_gasto_screen.dart';
import 'screens/recorrentes_screen.dart';
import 'screens/recuperar_senha_screen.dart';
import 'screens/sobre_screen.dart';
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

  // Link "Reset password" do e-mail de recuperação: o supabase_flutter abre o
  // app já logado e avisa que é recuperação; mostramos a tela de senha nova.
  var abrirSenhaNova = false;
  Supabase.instance.client.auth.onAuthStateChange.listen(
    (estado) {
      // Cor do app escolhida em Ajustes (fica na conta; sem conta = padrão).
      AppColors.usarPaleta(
          estado.session?.user.userMetadata?['cor_app'] as String?);
      if (estado.event != AuthChangeEvent.passwordRecovery) return;
      final nav = navegador.currentState;
      if (nav == null) {
        abrirSenhaNova = true; // o app ainda está abrindo: vira a 1ª tela
      } else {
        nav.pushNamedAndRemoveUntil(Rotas.senhaNova, (_) => false);
      }
    },
    // Link vencido, já usado ou aberto em outro celular.
    onError: (Object e) => avisos.currentState
        ?.showSnackBar(SnackBar(content: Text(mensagemErro(e)))),
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
  await Future<void>.delayed(Duration.zero); // deixa o aviso acima chegar
  if (abrirSenhaNova) rotaInicial = Rotas.senhaNova;

  runApp(ApeSyncApp(rotaInicial: rotaInicial));
}

/// Navegação e avisos fora de uma tela (ex.: link de recuperação de senha).
final navegador = GlobalKey<NavigatorState>();
final avisos = GlobalKey<ScaffoldMessengerState>();

class ApeSyncApp extends StatelessWidget {
  final String rotaInicial;
  const ApeSyncApp({super.key, this.rotaInicial = Rotas.login});

  @override
  Widget build(BuildContext context) {
    // Refaz o tema quando a cor do app muda (Ajustes → Cor do app).
    return ValueListenableBuilder<Paleta>(
      valueListenable: AppColors.paleta,
      builder: (context, _, __) => _app(),
    );
  }

  Widget _app() {
    return MaterialApp(
      title: 'ApeSync',
      debugShowCheckedModeBanner: false,
      navigatorKey: navegador,
      scaffoldMessengerKey: avisos,
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
        Rotas.gastosFixos: (_) => const RecorrentesScreen(),
        Rotas.novaTarefa: (_) => const NovaTarefaScreen(),
        Rotas.recuperarSenha: (_) => const RecuperarSenhaScreen(),
        Rotas.senhaNova: (_) => const RecuperarSenhaScreen(senhaNova: true),
        Rotas.sobre: (_) => const SobreScreen(),
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
