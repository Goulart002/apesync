import 'package:flutter/material.dart';

/// Uma opção de "Cor do app" (Ajustes): a cor principal e dois tons claros
/// dela (fundo de destaque e borda suave).
class Paleta {
  final String id;
  final String nome;
  final Color cor;
  final Color clara;
  final Color suave;
  const Paleta(this.id, this.nome, this.cor, this.clara, this.suave);
}

/// Paleta do app (mesmos valores usados no projeto das telas).
///
/// [primary], [primaryLight] e [primaryMuted] seguem a cor escolhida em
/// Ajustes (por isso não são `const`); as demais são fixas.
class AppColors {
  static const paletas = [
    Paleta('verde', 'Verde-água', Color(0xFF0F766E), Color(0xFFE6F4F2),
        Color(0xFFB7E4DF)),
    Paleta('azul', 'Azul', Color(0xFF1D4ED8), Color(0xFFE8EFFD),
        Color(0xFFBFD3FA)),
    Paleta('roxo', 'Roxo', Color(0xFF7C3AED), Color(0xFFF1EAFE),
        Color(0xFFD9C7FB)),
    Paleta('rosa', 'Rosa', Color(0xFFDB2777), Color(0xFFFCE8F2),
        Color(0xFFF7C3DD)),
    Paleta('laranja', 'Laranja', Color(0xFFC2410C), Color(0xFFFDEEE6),
        Color(0xFFF8CDB6)),
    Paleta('grafite', 'Grafite', Color(0xFF374151), Color(0xFFECEEF1),
        Color(0xFFC9CED6)),
  ];

  /// Muda quando a pessoa escolhe outra cor (o MaterialApp escuta).
  static final paleta = ValueNotifier<Paleta>(paletas.first);

  static Color get primary => paleta.value.cor;
  static Color get primaryLight => paleta.value.clara;
  static Color get primaryMuted => paleta.value.suave;

  /// Aplica a cor salva na conta ([id] desconhecido ou null = padrão) e
  /// redesenha todas as telas abertas.
  static void usarPaleta(String? id) {
    final nova =
        paletas.firstWhere((p) => p.id == id, orElse: () => paletas.first);
    if (nova.id == paleta.value.id) return;
    paleta.value = nova;
    // Telas que usam AppColors.primary direto (sem Theme.of) também precisam
    // ser redesenhadas.
    void redesenhar(Element e) {
      e.markNeedsBuild();
      e.visitChildren(redesenhar);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(redesenhar);
  }

  static const background = Color(0xFFF6F7F5);
  static const card = Color(0xFFFFFFFF);
  static const text = Color(0xFF1A1D1F);
  static const muted = Color(0xFF6B7280);
  static const hint = Color(0xFF9CA3AF);
  static const border = Color(0xFFE5E7EB);
  static const divider = Color(0xFFF0F1F3);
  static const positive = Color(0xFF16A34A);
  static const positiveLight = Color(0xFFDCFCE7);
  static const negative = Color(0xFFDC2626);
  static const negativeLight = Color(0xFFFEE2E2);
  static const amber = Color(0xFFD97706);
  static const amberLight = Color(0xFFFEF3C7);
  static const blue = Color(0xFF2563EB);
  static const blueLight = Color(0xFFDBEAFE);
  static const purple = Color(0xFF7C3AED);
  static const purpleLight = Color(0xFFEDE9FE);
  static const pink = Color(0xFFDB2777);
}

class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: AppColors.card,
    );

    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.text,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        hintStyle: const TextStyle(color: AppColors.hint),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        prefixIconColor: AppColors.muted,
        suffixIconColor: AppColors.muted,
        border: border(AppColors.border),
        enabledBorder: border(AppColors.border),
        focusedBorder: border(AppColors.primary, 1.5),
        errorBorder: border(AppColors.negative),
        focusedErrorBorder: border(AppColors.negative, 1.5),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          textStyle:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.card,
          foregroundColor: AppColors.text,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          textStyle:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.card,
        indicatorColor: AppColors.primaryLight,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
