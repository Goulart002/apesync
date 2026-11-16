import 'package:apesync/data/modelos.dart';
import 'package:apesync/services/nota_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Lê total, data, loja e categoria de um cupom NFC-e', () {
    const texto = '''
SUPERMERCADO BOM PRECO LTDA
CNPJ: 12.345.678/0001-90
RUA DA BAHIA, 1200 - CENTRO
DOCUMENTO AUXILIAR DA NOTA FISCAL DE CONSUMIDOR ELETRONICA
001 ARROZ 5KG 1 UN X 24,90 24,90
002 FEIJAO 1KG 2 UN X 8,49 16,98
QTD. TOTAL DE ITENS 3
VALOR TOTAL R\$ 41,88
Dinheiro 50,00
Troco R\$ 8,12
Tributos Totais Incidentes (Lei 12.741/2012) 7,23
Emissao: 27/09/2026 14:32:10''';

    final nota = NotaScanner.interpretar(texto);
    expect(nota.valorCentavos, 4188);
    expect(nota.data, DateTime(2026, 9, 27));
    expect(nota.estabelecimento, 'Supermercado Bom Preco Ltda');
    expect(nota.categoria, Categoria.mercado);
  });

  test('Sem palavra "total": usa o maior valor, ignorando troco', () {
    const texto = 'PADARIA PAO QUENTE\nPAO FRANCES 6,50\nCAFE 12,00\nTROCO 81,50';
    final nota = NotaScanner.interpretar(texto);
    expect(nota.valorCentavos, 1200);
  });

  test('Texto sem dados de nota', () {
    expect(NotaScanner.interpretar('foto borrada').vazia, isTrue);
  });
}
