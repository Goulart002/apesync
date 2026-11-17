import 'package:apesync/data/regras_sync.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _linha(String updatedAt,
        {int pendente = 0, String descricao = 'Mercado'}) =>
    {
      'id': 'g1',
      'descricao': descricao,
      'valor_centavos': 1000,
      'updated_at': updatedAt,
      'deleted': 0,
      'pendente': pendente,
    };

void main() {
  group('Margem do download', () {
    test('Primeiro download pega tudo', () {
      expect(RegrasSync.desdeComMargem(null), '1970-01-01T00:00:00Z');
    });

    test('Volta 60 segundos antes da última marca', () {
      expect(RegrasSync.desdeComMargem('2026-11-17T10:00:30.000Z'),
          '2026-11-17T09:59:30.000Z');
      // Formato do Postgres (+00:00) também funciona.
      expect(RegrasSync.desdeComMargem('2026-11-17T10:00:30+00:00'),
          '2026-11-17T09:59:30.000Z');
    });

    test('A marca nunca anda para trás', () {
      const marca = '2026-11-17T10:00:30.000Z';
      expect(RegrasSync.novaMarca(marca, '2026-11-17T10:00:10.000Z'), marca);
      expect(RegrasSync.novaMarca(marca, '2026-11-17T10:01:00.000Z'),
          '2026-11-17T10:01:00.000Z');
      expect(RegrasSync.novaMarca(null, '2026-11-17T10:01:00.000Z'),
          '2026-11-17T10:01:00.000Z');
    });
  });

  group('Celular x servidor', () {
    const dez = '2026-11-17T10:00:00.000Z';
    const onze = '2026-11-17T11:00:00.000Z';

    test('Linha nova do servidor é gravada', () {
      expect(RegrasSync.aplicarRemoto(null, _linha(dez)), isTrue);
    });

    test('Edição pendente mais nova no celular é mantida', () {
      expect(RegrasSync.aplicarRemoto(_linha(onze, pendente: 1), _linha(dez)),
          isFalse);
    });

    test('Edição pendente mais velha perde para a do servidor', () {
      expect(RegrasSync.aplicarRemoto(_linha(dez, pendente: 1), _linha(onze)),
          isTrue);
    });

    test('Linha igual à que já temos é ignorada (margem não recarrega à toa)',
        () {
      expect(RegrasSync.aplicarRemoto(_linha(dez), _linha(dez)), isFalse);
    });

    test('Linha sincronizada que mudou no servidor é gravada', () {
      expect(
          RegrasSync.aplicarRemoto(
              _linha(dez), _linha(onze, descricao: 'Mercado do mês')),
          isTrue);
    });
  });
}
