import 'package:apesync/data/modelos.dart';
import 'package:apesync/data/rodizio.dart';
import 'package:flutter_test/flutter_test.dart';

// 17/11/2026 é uma terça-feira.
final _terca = DateTime(2026, 11, 17);
const _todos = {'ana', 'bia', 'caio'};

Tarefa _lixo({
  DateTime? proxima,
  String? vez = 'ana',
  List<String> rodizio = const ['ana', 'bia', 'caio'],
}) =>
    Tarefa(
      id: 't-lixo',
      casaId: 'c',
      titulo: 'Tirar o lixo',
      tipo: TipoTarefa.lixo,
      responsavelId: vez,
      rodizio: rodizio,
      repeticao: Repeticao.semanal,
      diasSemana: const [1, 3, 5], // seg, qua, sex
      proxima: proxima ?? DateTime(2026, 11, 18), // quarta
    );

void main() {
  group('Próxima vez', () {
    test('Semanal: seg/qua/sex', () {
      final t = _lixo();
      expect(Rodizio.proximaOcorrencia(t, DateTime(2026, 11, 18)),
          DateTime(2026, 11, 20)); // qua -> sex
      expect(Rodizio.proximaOcorrencia(t, DateTime(2026, 11, 20)),
          DateTime(2026, 11, 23)); // sex -> seg
    });

    test('Diária e mensal (dia 31 vira o último dia do mês)', () {
      final diaria = Tarefa(
          id: 'd',
          casaId: 'c',
          titulo: 'Louça',
          repeticao: Repeticao.diaria,
          proxima: DateTime(2026, 11, 30));
      expect(Rodizio.proximaOcorrencia(diaria, DateTime(2026, 11, 30)),
          DateTime(2026, 12, 1));

      final mensal = Tarefa(
          id: 'm',
          casaId: 'c',
          titulo: 'Faxina geral',
          repeticao: Repeticao.mensal,
          diaMes: 31,
          proxima: DateTime(2026, 1, 31));
      expect(Rodizio.proximaOcorrencia(mensal, DateTime(2026, 1, 31)),
          DateTime(2026, 2, 28));
      expect(Rodizio.proximaOcorrencia(mensal, DateTime(2026, 2, 28)),
          DateTime(2026, 3, 31)); // volta para o dia 31
    });

    test('Atrasada há várias vezes: pula as perdidas', () {
      // Era para segunda 9/11; só fizeram na terça 17/11.
      final t = _lixo(proxima: DateTime(2026, 11, 9));
      expect(Rodizio.dataDepoisDeFeita(t, _terca), DateTime(2026, 11, 18));
    });

    test('Feita antes do dia: vai para a vez seguinte', () {
      // Era para sexta 20/11 e fizeram na terça 17/11.
      final t = _lixo(proxima: DateTime(2026, 11, 20));
      expect(Rodizio.dataDepoisDeFeita(t, _terca), DateTime(2026, 11, 23));
    });
  });

  group('De quem é a vez', () {
    test('Passa para o próximo e volta ao começo', () {
      expect(Rodizio.proximoResponsavel(_lixo(vez: 'ana'), _todos), 'bia');
      expect(Rodizio.proximoResponsavel(_lixo(vez: 'caio'), _todos), 'ana');
    });

    test('Pula quem saiu da casa', () {
      expect(Rodizio.proximoResponsavel(_lixo(vez: 'ana'), {'ana', 'caio'}),
          'caio');
    });

    test('Sem rodízio: continua com a mesma pessoa', () {
      expect(
          Rodizio.proximoResponsavel(
              _lixo(vez: 'bia', rodizio: const []), _todos),
          'bia');
      expect(
          Rodizio.proximoResponsavel(
              _lixo(vez: null, rodizio: const []), _todos),
          isNull);
    });
  });

  test('Marcar como feita: avança data e vez; avulsa fica concluída', () {
    final depois = Rodizio.depoisDeFeita(_lixo(), hoje: _terca, ativos: _todos);
    expect(depois.proxima, DateTime(2026, 11, 20));
    expect(depois.responsavelId, 'bia');
    expect(depois.concluida, isFalse);

    final avulsa = Tarefa(
        id: 'a',
        casaId: 'c',
        titulo: 'Comprar papel higiênico',
        tipo: TipoTarefa.compras,
        responsavelId: 'bia',
        proxima: DateTime(2026, 11, 20));
    final feita = Rodizio.depoisDeFeita(avulsa, hoje: _terca, ativos: _todos);
    expect(feita.concluida, isTrue);
    expect(feita.responsavelId, 'bia');
  });

  test('A mesma vez gera o mesmo id no histórico (não conta duas vezes)', () {
    final a = Rodizio.idDaFeita('t-lixo', DateTime(2026, 11, 18));
    final b = Rodizio.idDaFeita('t-lixo', DateTime(2026, 11, 18));
    final outra = Rodizio.idDaFeita('t-lixo', DateTime(2026, 11, 20));
    expect(a, b);
    expect(a, isNot(outra));
  });

  test('Situação e textos', () {
    expect(Rodizio.situacao(_lixo(proxima: DateTime(2026, 11, 15)), _terca),
        SituacaoTarefa.atrasada);
    expect(
        Rodizio.descreverData(_lixo(proxima: DateTime(2026, 11, 15)), _terca),
        'atrasada há 2 dias');
    expect(Rodizio.descreverData(_lixo(proxima: _terca), _terca), 'hoje');
    expect(Rodizio.descreverData(_lixo(), _terca), 'amanhã');
    expect(
        Rodizio.descreverData(_lixo(proxima: DateTime(2026, 11, 20)), _terca),
        'sex, 20/11');
    expect(Rodizio.descreverRepeticao(_lixo()), 'Seg, Qua, Sex');
  });

  test('Placar do mês conta quem fez (não quem era a vez)', () {
    TarefaFeita f(String quem, String vez, String quando,
            {bool excluida = false}) =>
        TarefaFeita(
          id: '$quem$quando',
          casaId: 'c',
          tarefaId: 't',
          titulo: 'Lixo',
          dataPrevista: DateTime(2026, 11, 1),
          responsavelId: vez,
          feitaPorId: quem,
          feitaEm: quando,
          deleted: excluida,
        );
    final placar = Rodizio.placarDoMes([
      f('ana', 'ana', '2026-11-02T10:00:00.000'),
      f('caio', 'bia', '2026-11-05T10:00:00.000'), // no lugar da Bia
      f('caio', 'caio', '2026-11-09T10:00:00.000'),
      f('bia', 'bia', '2026-10-30T10:00:00.000'), // outro mês
      f('ana', 'ana', '2026-11-10T10:00:00.000', excluida: true), // desfeita
    ], DateTime(2026, 11));
    expect(placar, {'ana': 1, 'caio': 2});
  });
}
