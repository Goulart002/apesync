import 'package:apesync/data/modelos.dart';
import 'package:apesync/data/recorrentes.dart';
import 'package:flutter_test/flutter_test.dart';

Recorrencia _aluguel(
        {int dia = 5, String inicio = '2026-09', bool ativo = true}) =>
    Recorrencia(
      id: 'rec-aluguel',
      casaId: 'c',
      descricao: 'Aluguel',
      valorCentavos: 180000,
      categoria: Categoria.moradia,
      pagoPorId: 'ana',
      divididoEntre: const ['ana', 'bia', 'caio'],
      dia: dia,
      inicio: inicio,
      ativo: ativo,
      criadoPor: 'u-ana',
    );

void main() {
  test('Lança os meses desde o início, só depois do dia chegar', () {
    final v = Recorrentes.vencimentosAte(_aluguel(), DateTime(2026, 11, 17));
    expect(v,
        [DateTime(2026, 9, 5), DateTime(2026, 10, 5), DateTime(2026, 11, 5)]);

    // Dia 20 ainda não chegou em novembro.
    final v20 =
        Recorrentes.vencimentosAte(_aluguel(dia: 20), DateTime(2026, 11, 17));
    expect(v20.last, DateTime(2026, 10, 20));
  });

  test('Dia 31 em mês curto vira o último dia (fevereiro bissexto também)', () {
    expect(Recorrentes.vencimento(2027, 2, 31), DateTime(2027, 2, 28));
    expect(Recorrentes.vencimento(2028, 2, 31), DateTime(2028, 2, 29));
    expect(Recorrentes.vencimento(2026, 4, 31), DateTime(2026, 4, 30));
  });

  test('Virada de ano funciona', () {
    final v = Recorrentes.vencimentosAte(
        _aluguel(inicio: '2026-12'), DateTime(2027, 1, 10));
    expect(v, [DateTime(2026, 12, 5), DateTime(2027, 1, 5)]);
  });

  test('Pausado não lança; app sem abrir há anos lança no máximo 12 meses', () {
    expect(
        Recorrentes.vencimentosAte(
            _aluguel(ativo: false), DateTime(2026, 11, 17)),
        isEmpty);
    final v = Recorrentes.vencimentosAte(
        _aluguel(inicio: '2020-01'), DateTime(2026, 11, 17));
    expect(v.length, 12);
    expect(v.first, DateTime(2025, 12, 5));
  });

  test('Mesmo mês gera o mesmo gasto em qualquer celular (sem duplicar)', () {
    final r = _aluguel();
    final a = Recorrentes.gastoDoMes(r, DateTime(2026, 11, 5));
    final b = Recorrentes.gastoDoMes(r, DateTime(2026, 11, 5));
    final dez = Recorrentes.gastoDoMes(r, DateTime(2026, 12, 5));
    expect(a.id, b.id);
    expect(a.updatedAt, b.updatedAt);
    expect(a.id, isNot(dez.id));
    expect(a.recorrenciaId, 'rec-aluguel');
    expect(a.criadoPor, 'u-ana');
    expect(a.valorCentavos, 180000);
    expect(a.data, DateTime(2026, 11, 5));
  });
}
