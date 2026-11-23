import 'package:apesync/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Cor do app: aplica a escolhida e volta ao padrão se não conhecer', () {
    AppColors.usarPaleta('roxo');
    expect(AppColors.primary, const Color(0xFF7C3AED));
    expect(AppColors.paleta.value.nome, 'Roxo');

    AppColors.usarPaleta('cor-que-nao-existe');
    expect(AppColors.paleta.value.id, 'verde');

    AppColors.usarPaleta('azul');
    AppColors.usarPaleta(null); // saiu da conta
    expect(AppColors.primary, const Color(0xFF0F766E));
  });

  test('Cada cor tem um id diferente', () {
    final ids = AppColors.paletas.map((p) => p.id).toSet();
    expect(ids.length, AppColors.paletas.length);
  });
}
