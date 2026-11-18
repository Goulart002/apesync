import 'package:uuid/uuid.dart';

import 'modelos.dart';

/// Gastos fixos (aluguel, internet...): quais meses gerar e como fica o
/// gasto de cada mês. Regras puras, fáceis de testar.
///
/// O gasto de cada mês tem um id DETERMINÍSTICO (calculado a partir do
/// gasto fixo + mês): se dois celulares gerarem o aluguel de dezembro ao
/// mesmo tempo, os dois criam o mesmo id e o servidor guarda um só.
class Recorrentes {
  /// "Namespace" fixo do ApeSync para os ids determinísticos (UUID v5).
  static const _namespace = '6f1b0d5e-3b0a-4f7c-9a55-0c1e7d2a9b31';

  /// Se o app ficou meses sem abrir, gera no máximo este tanto de meses.
  static const mesesParaTras = 12;

  /// Mês no formato AAAA-MM.
  static String mes(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  /// Dia do vencimento no mês: dia 31 em fevereiro vira o último dia.
  static DateTime vencimento(int ano, int mes, int dia) {
    final ultimoDia = DateTime(ano, mes + 1, 0).day;
    return DateTime(ano, mes, dia > ultimoDia ? ultimoDia : dia);
  }

  /// Vencimentos que já chegaram, do mês de início (no máximo
  /// [mesesParaTras] meses atrás) até hoje. Gasto fixo pausado ou excluído
  /// não gera nada.
  static List<DateTime> vencimentosAte(Recorrencia r, DateTime hoje) {
    if (!r.ativo || r.deleted) return const [];
    final p = r.inicio.split('-');
    var ano = int.parse(p[0]);
    var m = int.parse(p[1]);
    final limite = DateTime(hoje.year, hoje.month - (mesesParaTras - 1));
    if (DateTime(ano, m).isBefore(limite)) {
      ano = limite.year;
      m = limite.month;
    }
    final hojeDia = DateTime(hoje.year, hoje.month, hoje.day);
    final fim = DateTime(hoje.year, hoje.month + 1);
    final res = <DateTime>[];
    while (DateTime(ano, m).isBefore(fim)) {
      final v = vencimento(ano, m, r.dia);
      if (!v.isAfter(hojeDia)) res.add(v);
      if (++m > 12) {
        m = 1;
        ano++;
      }
    }
    return res;
  }

  static String idDoGasto(String recorrenciaId, DateTime vencimento) =>
      const Uuid().v5(_namespace, '$recorrenciaId/${mes(vencimento)}');

  /// Data de alteração "oficial" do gasto gerado, igual em todos os
  /// celulares: duas gerações do mesmo mês são a mesma versão, e qualquer
  /// edição feita depois por alguém vence (é mais recente).
  static String updatedAtDoGasto(DateTime vencimento) =>
      DateTime.utc(vencimento.year, vencimento.month, vencimento.day)
          .toIso8601String();

  /// O gasto daquele mês.
  static Gasto gastoDoMes(Recorrencia r, DateTime vencimento) => Gasto(
        id: idDoGasto(r.id, vencimento),
        casaId: r.casaId,
        descricao: r.descricao,
        valorCentavos: r.valorCentavos,
        categoria: r.categoria,
        pagoPorId: r.pagoPorId,
        divididoEntre: r.divididoEntre,
        data: vencimento,
        criadoPor: r.criadoPor,
        recorrenciaId: r.id,
        updatedAt: updatedAtDoGasto(vencimento),
      );
}
