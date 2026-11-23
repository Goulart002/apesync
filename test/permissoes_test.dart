import 'package:apesync/data/modelos.dart';
import 'package:apesync/data/permissoes.dart';
import 'package:flutter_test/flutter_test.dart';

// Contas (auth) e moradores de exemplo.
const _contaAna = 'u-ana';
const _contaBia = 'u-bia';

const _ana = Morador(
    id: 'ana', casaId: 'c', nome: 'Ana', usuarioId: _contaAna, updatedAt: '');
const _bia = Morador(
    id: 'bia', casaId: 'c', nome: 'Bia', usuarioId: _contaBia, updatedAt: '');
const _semConta = Morador(id: 'zé', casaId: 'c', nome: 'Zé', updatedAt: '');

/// Ana administra a casa.
const _comoAna = Permissoes(
    usuarioId: _contaAna, adminUsuarioId: _contaAna, euMoradorId: 'ana');
const _comoBia = Permissoes(
    usuarioId: _contaBia, adminUsuarioId: _contaAna, euMoradorId: 'bia');

Gasto _gasto({String? criadoPor}) => Gasto(
      id: 'g',
      casaId: 'c',
      descricao: 'Mercado',
      valorCentavos: 1000,
      categoria: Categoria.mercado,
      pagoPorId: 'ana',
      divididoEntre: const ['ana', 'bia'],
      data: DateTime(2026, 11, 1),
      criadoPor: criadoPor,
    );

void main() {
  test('Quem é o administrador', () {
    expect(_comoAna.souAdmin, isTrue);
    expect(_comoBia.souAdmin, isFalse);
    expect(_comoBia.ehAdmin(_ana), isTrue);
    expect(_comoBia.ehAdmin(_bia), isFalse);
    expect(_comoBia.ehAdmin(_semConta), isFalse);
  });

  test('Membro edita só o próprio nome; admin edita qualquer um', () {
    expect(_comoBia.podeEditarMorador(_bia), isTrue);
    expect(_comoBia.podeEditarMorador(_ana), isFalse);
    expect(_comoAna.podeEditarMorador(_bia), isTrue);
  });

  test('Gasto: só quem lançou ou o admin altera', () {
    expect(_comoBia.podeEditarGasto(_gasto(criadoPor: _contaBia)), isTrue);
    expect(_comoBia.podeEditarGasto(_gasto(criadoPor: _contaAna)), isFalse);
    expect(
        _comoBia.podeEditarGasto(_gasto()), isFalse); // gasto antigo sem autor
    expect(_comoAna.podeEditarGasto(_gasto(criadoPor: _contaBia)), isTrue);
  });

  test('Pagamento: quem paga, quem recebe ou o admin', () {
    expect(_comoBia.podeMexerNoPagamento('bia', 'ana'), isTrue);
    expect(_comoBia.podeMexerNoPagamento('ana', 'bia'), isTrue);
    expect(_comoBia.podeMexerNoPagamento('ana', 'zé'), isFalse);
    expect(_comoAna.podeMexerNoPagamento('bia', 'zé'), isTrue);
  });

  test('Remover morador: só admin, nunca a si mesmo, nunca quem tem a receber',
      () {
    expect(_comoBia.motivoNaoPodeRemover(_ana, 0), isNotNull);
    expect(_comoAna.motivoNaoPodeRemover(_ana, 0), isNotNull);
    expect(_comoAna.motivoNaoPodeRemover(_bia, 0), isNull);
    // Devendo: pode (a dívida vira ajuste dividido entre quem fica).
    expect(_comoAna.motivoNaoPodeRemover(_bia, -500), isNull);
    // Com dinheiro a receber: não pode.
    expect(_comoAna.motivoNaoPodeRemover(_bia, 500),
        contains('R\$ 5,00 a receber'));
  });

  test('Sair da casa: admin transfere antes; membro acerta as contas', () {
    expect(_comoAna.motivoNaoPodeSair(meuSaldo: 0, outrosComConta: 1),
        contains('Transfira'));
    expect(_comoAna.motivoNaoPodeSair(meuSaldo: 0, outrosComConta: 0),
        contains('único morador'));
    expect(_comoBia.motivoNaoPodeSair(meuSaldo: 250, outrosComConta: 1),
        contains('a receber'));
    expect(_comoBia.motivoNaoPodeSair(meuSaldo: 0, outrosComConta: 1), isNull);
  });

  test('Excluir conta: admin sozinho pode (a casa vai junto)', () {
    expect(
        _comoAna.motivoNaoPodeExcluirConta(meuSaldo: 0, outrosComConta: 0),
        isNull);
    expect(
        _comoAna.motivoNaoPodeExcluirConta(meuSaldo: 0, outrosComConta: 1),
        contains('Transfira'));
    expect(
        _comoBia.motivoNaoPodeExcluirConta(meuSaldo: -1000, outrosComConta: 1),
        contains('ainda deve'));
    expect(
        _comoBia.motivoNaoPodeExcluirConta(meuSaldo: 0, outrosComConta: 1),
        isNull);
  });

  test('Tornar administrador: só admin, para outro morador com conta', () {
    expect(_comoAna.podeTornarAdmin(_bia), isTrue);
    expect(_comoAna.podeTornarAdmin(_semConta), isFalse);
    expect(_comoAna.podeTornarAdmin(_ana), isFalse);
    expect(_comoBia.podeTornarAdmin(_ana), isFalse);
  });

  test('Gasto fixo: só quem criou ou o admin altera', () {
    Recorrencia fixo(String? criadoPor) => Recorrencia(
          id: 'r',
          casaId: 'c',
          descricao: 'Internet',
          valorCentavos: 10000,
          categoria: Categoria.contas,
          pagoPorId: 'bia',
          divididoEntre: const ['ana', 'bia'],
          dia: 10,
          inicio: '2026-11',
          criadoPor: criadoPor,
        );
    expect(_comoBia.podeEditarRecorrencia(fixo(_contaBia)), isTrue);
    expect(_comoBia.podeEditarRecorrencia(fixo(_contaAna)), isFalse);
    expect(_comoAna.podeEditarRecorrencia(fixo(_contaBia)), isTrue);
  });

  test('Tarefa: só quem criou ou o admin edita/exclui', () {
    Tarefa tarefa(String? criadoPor) => Tarefa(
          id: 't',
          casaId: 'c',
          titulo: 'Lavar a louça',
          proxima: DateTime(2026, 11, 18),
          criadoPor: criadoPor,
        );
    expect(_comoBia.podeEditarTarefa(tarefa(_contaBia)), isTrue);
    expect(_comoBia.podeEditarTarefa(tarefa(_contaAna)), isFalse);
    expect(_comoAna.podeEditarTarefa(tarefa(_contaBia)), isTrue);
  });
}
