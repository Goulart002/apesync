import 'package:apesync/data/busca.dart';
import 'package:apesync/data/modelos.dart';
import 'package:flutter_test/flutter_test.dart';

Gasto _gasto(String id, String descricao, int centavos, Categoria cat,
        String pagoPor) =>
    Gasto(
      id: id,
      casaId: 'c',
      descricao: descricao,
      valorCentavos: centavos,
      categoria: cat,
      pagoPorId: pagoPor,
      divididoEntre: const ['joao', 'bia'],
      data: DateTime(2026, 11, 1),
      updatedAt: '',
    );

final _gastos = [
  _gasto('1', 'Supermercado BH', 23450, Categoria.mercado, 'joao'),
  _gasto('2', 'Conta de luz', 18990, Categoria.contas, 'bia'),
  _gasto('3', 'Aluguel', 150000, Categoria.moradia, 'joao'),
  _gasto('4', 'Pão de queijo', 1200, Categoria.mercado, 'bia'),
];

String _nome(String id) => const {'joao': 'João', 'bia': 'Bia'}[id] ?? '?';

List<String> _ids(String termo) =>
    BuscaGastos.filtrar(_gastos, termo, _nome).map((g) => g.id).toList();

void main() {
  group('Busca de gastos', () {
    test('Ignora maiúsculas e acentos', () {
      expect(BuscaGastos.normalizar('Pão de Açúcar'), 'pao de acucar');
      expect(_ids('PAO'), ['4']);
      expect(_ids('joao'), ['1', '3']); // quem pagou: João
    });

    test('Acha pela categoria', () {
      expect(_ids('mercado'), ['1', '4']);
      expect(_ids('moradia'), ['3']);
    });

    test('Acha pelo valor, com ou sem ponto de milhar', () {
      expect(_ids('1.500'), ['3']);
      expect(_ids('1500'), ['3']);
      expect(_ids('189,90'), ['2']);
    });

    test('Todas as palavras precisam aparecer', () {
      expect(_ids('mercado bia'), ['4']);
      expect(_ids('luz joão'), isEmpty);
    });

    test('Texto vazio não filtra nada', () {
      expect(_ids('   '), ['1', '2', '3', '4']);
    });
  });

  group('Nome da conta', () {
    test('Usa o nome do cadastro', () {
      expect(nomeDaConta({'nome': ' Ana Souza '}, 'ana@x.com'), 'Ana Souza');
    });

    test('Conta Google: usa full_name ou name', () {
      expect(nomeDaConta({'full_name': 'Bia Lima', 'name': 'B'}, 'b@x.com'),
          'Bia Lima');
      expect(nomeDaConta({'name': 'Caio'}, 'c@x.com'), 'Caio');
    });

    test('Sem nome: começo do e-mail', () {
      expect(nomeDaConta({'nome': ''}, 'davi.r@gmail.com'), 'davi.r');
      expect(nomeDaConta(null, null), 'Eu');
    });
  });
}
