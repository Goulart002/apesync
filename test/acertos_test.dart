import 'package:apesync/data/calculos.dart';
import 'package:apesync/data/modelos.dart';
import 'package:flutter_test/flutter_test.dart';

Gasto _g(String id, int valor, String pagoPor) => Gasto(
      id: id,
      casaId: 'c',
      descricao: id,
      valorCentavos: valor,
      categoria: Categoria.mercado,
      pagoPorId: pagoPor,
      divididoEntre: const ['eu', 'ana', 'lucas', 'bia'],
      data: DateTime(2026, 10, 1),
    );

void main() {
  final gastos = [
    _g('limpeza', 5800, 'bia'),
    _g('compras', 32000, 'ana'),
    _g('luz', 18640, 'eu'),
    _g('internet', 11960, 'lucas'),
  ];
  const ids = ['eu', 'ana', 'lucas', 'bia'];
  Map<String, int> saldos(List<Pagamento> pg) =>
      {for (final id in ids) id: Calculos.saldoDe(id, gastos, pg)};

  test('Saldos somam zero', () {
    final s = saldos([]);
    expect(s, {'eu': 1540, 'ana': 14900, 'lucas': -5140, 'bia': -11300});
    expect(s.values.reduce((a, b) => a + b), 0);
  });

  test('Simplifica em 3 transferências (em vez de 6 dívidas)', () {
    final t = Calculos.simplificar(saldos([]));
    expect(t.length, 3);
    expect(Calculos.dividasSemSimplificar(gastos, []), 6);
    expect([t[0].deId, t[0].paraId, t[0].valorCentavos], ['bia', 'ana', 11300]);
    expect([t[1].deId, t[1].paraId, t[1].valorCentavos], ['lucas', 'ana', 3600]);
    expect([t[2].deId, t[2].paraId, t[2].valorCentavos], ['lucas', 'eu', 1540]);
  });

  test('Pagamento registrado zera a dívida', () {
    final pg = [
      Pagamento(
          id: 'p1',
          casaId: 'c',
          deId: 'lucas',
          paraId: 'eu',
          valorCentavos: 1540,
          data: DateTime(2026, 10, 2)),
    ];
    expect(saldos(pg)['eu'], 0);
    expect(Calculos.simplificar(saldos(pg)).length, 2);
  });

  test('Centavo que sobra vai para o primeiro da divisão', () {
    final g = _g('x', 1001, 'eu');
    expect([for (final id in ids) g.parteDe(id)], [251, 250, 250, 250]);
  });

  group('Remover morador devendo', () {
    const bia = Morador(id: 'bia', casaId: 'c', nome: 'Bia', updatedAt: '');
    Gasto? ajuste(String quem, int saldo) => Calculos.ajusteDeRemocao(
          id: 'aj',
          casaId: 'c',
          removido: Morador(id: quem, casaId: 'c', nome: quem, updatedAt: ''),
          saldo: saldo,
          ficam: ids,
          data: DateTime(2026, 11, 17),
        );

    test('Dívida da Bia é dividida entre quem fica e as contas fecham', () {
      final aj = Calculos.ajusteDeRemocao(
        id: 'aj',
        casaId: 'c',
        removido: bia,
        saldo: -11300,
        ficam: ids, // a própria Bia é ignorada na divisão
        data: DateTime(2026, 11, 17),
      )!;
      expect(aj.categoria, Categoria.ajuste);
      expect(aj.valorCentavos, 11300);
      expect(aj.divididoEntre, ['eu', 'ana', 'lucas']);

      final depois = [...gastos, aj];
      final s = {for (final id in ids) id: Calculos.saldoDe(id, depois, [])};
      expect(s['bia'], 0);
      // 11300 / 3 = 3766,67 -> 3767 + 3767 + 3766
      expect(s, {
        'eu': 1540 - 3767,
        'ana': 14900 - 3767,
        'lucas': -5140 - 3766,
        'bia': 0
      });
      expect(s.values.reduce((a, b) => a + b), 0);
    });

    test('Sem dívida (ou com dinheiro a receber) não cria ajuste', () {
      expect(ajuste('eu', 0), isNull);
      expect(ajuste('ana', 14900), isNull);
    });
  });
}
