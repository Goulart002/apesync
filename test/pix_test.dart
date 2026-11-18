import 'package:apesync/data/pix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Dígito verificador (CRC16-CCITT)', () {
    test('Valor de referência padrão', () {
      expect(Pix.crc16('123456789'), '29B1');
    });
  });

  group('PIX copia e cola', () {
    test('Igual ao exemplo do manual do Banco Central (sem valor)', () {
      expect(
        Pix.copiaECola(
          chave: '123e4567-e12b-12d1-a456-426655440000',
          nome: 'Fulano de Tal',
          cidade: 'BRASILIA',
        ),
        '00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-426655440000'
        '5204000053039865802BR5913Fulano de Tal6008BRASILIA62070503***63041D3D',
      );
    });

    test('Leva o valor, nome sem acento e termina com o CRC certo', () {
      final c = Pix.copiaECola(
          chave: '+5531999998888', nome: 'João Conceição', valorCentavos: 4550);
      expect(c, contains('540545.50'));
      expect(c, contains('5914Joao Conceicao'));
      final semCrc = c.substring(0, c.length - 4);
      expect(c.substring(c.length - 4), Pix.crc16(semCrc));
    });

    test('Nome comprido é cortado em 25 letras', () {
      final c = Pix.copiaECola(
          chave: 'a@b.com', nome: 'Maria Aparecida dos Santos Oliveira');
      expect(c, contains('5925Maria Aparecida dos Sant'));
    });
  });

  group('Chave PIX', () {
    test('CPF e CNPJ ficam só com números', () {
      expect(Pix.normalizar(TipoChavePix.cpf, '123.456.789-09'), '12345678909');
      expect(Pix.normalizar(TipoChavePix.cpf, '123'), isNull);
      expect(Pix.normalizar(TipoChavePix.cnpj, '12.345.678/0001-95'),
          '12345678000195');
    });

    test('Celular ganha +55 (com ou sem DDI)', () {
      expect(Pix.normalizar(TipoChavePix.celular, '(31) 99999-8888'),
          '+5531999998888');
      expect(Pix.normalizar(TipoChavePix.celular, '+55 31 99999-8888'),
          '+5531999998888');
      expect(Pix.normalizar(TipoChavePix.celular, '9999'), isNull);
    });

    test('E-mail e chave aleatória em minúsculas', () {
      expect(Pix.normalizar(TipoChavePix.email, ' Ana@Email.com '),
          'ana@email.com');
      expect(Pix.normalizar(TipoChavePix.email, 'sem-arroba'), isNull);
      expect(
          Pix.normalizar(
              TipoChavePix.aleatoria, '123E4567-E89B-12D3-A456-426614174000'),
          '123e4567-e89b-12d3-a456-426614174000');
    });

    test('Descobre o tipo de uma chave salva', () {
      expect(Pix.tipoDe('+5531999998888'), TipoChavePix.celular);
      expect(Pix.tipoDe('ana@email.com'), TipoChavePix.email);
      expect(Pix.tipoDe('12345678909'), TipoChavePix.cpf);
      expect(Pix.tipoDe('12345678000195'), TipoChavePix.cnpj);
      expect(Pix.tipoDe('123e4567-e89b-12d3-a456-426614174000'),
          TipoChavePix.aleatoria);
    });
  });
}
