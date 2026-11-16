import 'package:apesync/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Login navega para Cadastro e volta', (tester) async {
    await tester.pumpWidget(const ApeSyncApp());
    expect(find.text('ApeSync'), findsOneWidget);

    await tester.ensureVisible(find.text('Cadastre-se'));
    await tester.tap(find.text('Cadastre-se'));
    await tester.pumpAndSettle();
    expect(find.text('Leva menos de um minuto.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Esqueci minha senha'), findsOneWidget);
  });
}
