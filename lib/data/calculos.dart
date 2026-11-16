import 'modelos.dart';

/// Regras de negócio puras (sem banco, sem tela) — fáceis de testar.
class Calculos {
  /// Saldo líquido de um morador, em centavos.
  /// = o que ele pagou nos gastos − a parte dele em cada gasto
  ///   + pagamentos que ele fez − pagamentos que ele recebeu.
  /// Positivo = a casa deve a ele; negativo = ele deve à casa.
  static int saldoDe(
      String id, Iterable<Gasto> gastos, Iterable<Pagamento> pagamentos) {
    var saldo = 0;
    for (final g in gastos) {
      if (g.pagoPorId == id) saldo += g.valorCentavos;
      saldo -= g.parteDe(id);
    }
    for (final p in pagamentos) {
      if (p.deId == id) saldo += p.valorCentavos;
      if (p.paraId == id) saldo -= p.valorCentavos;
    }
    return saldo;
  }

  /// Simplifica as dívidas no menor número de transferências (guloso):
  /// a cada passo, quem mais deve paga para quem mais tem a receber.
  static List<Transferencia> simplificar(Map<String, int> saldos) {
    final devedores = <MapEntry<String, int>>[];
    final credores = <MapEntry<String, int>>[];
    saldos.forEach((id, s) {
      if (s < 0) devedores.add(MapEntry(id, -s));
      if (s > 0) credores.add(MapEntry(id, s));
    });

    final resultado = <Transferencia>[];
    while (devedores.isNotEmpty && credores.isNotEmpty) {
      devedores.sort((a, b) => b.value.compareTo(a.value));
      credores.sort((a, b) => b.value.compareTo(a.value));
      final d = devedores.removeAt(0);
      final c = credores.removeAt(0);
      final valor = d.value < c.value ? d.value : c.value;
      resultado.add(Transferencia(d.key, c.key, valor));
      if (d.value > valor) devedores.add(MapEntry(d.key, d.value - valor));
      if (c.value > valor) credores.add(MapEntry(c.key, c.value - valor));
    }
    return resultado;
  }

  /// Quantas dívidas existiriam sem simplificar (pares com saldo pendente).
  static int dividasSemSimplificar(
      Iterable<Gasto> gastos, Iterable<Pagamento> pagamentos) {
    final entre = <String, int>{};
    void soma(String credor, String devedor, int v) {
      if (credor == devedor || v == 0) return;
      final inverte = credor.compareTo(devedor) > 0;
      final chave = inverte ? '$devedor|$credor' : '$credor|$devedor';
      entre[chave] = (entre[chave] ?? 0) + (inverte ? -v : v);
    }

    for (final g in gastos) {
      for (final id in g.divididoEntre) {
        soma(g.pagoPorId, id, g.parteDe(id));
      }
    }
    for (final p in pagamentos) {
      soma(p.deId, p.paraId, p.valorCentavos);
    }
    return entre.values.where((v) => v != 0).length;
  }
}
