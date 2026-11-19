import 'modelos.dart';

/// Busca da aba Gastos: procura na descrição, na categoria, em quem pagou e no
/// valor. Ignora maiúsculas e acentos ("joao" acha "João") e exige todas as
/// palavras ("mercado bia" = gastos de mercado que a Bia pagou).
class BuscaGastos {
  BuscaGastos._();

  static const _semAcento = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', //
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', //
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', //
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', //
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', //
    'ç': 'c', 'ñ': 'n',
  };

  static String normalizar(String texto) {
    final buf = StringBuffer();
    for (final ch in texto.toLowerCase().split('')) {
      buf.write(_semAcento[ch] ?? ch);
    }
    return buf.toString();
  }

  /// [nomeDe] devolve o(s) nome(s) de quem pagou, ex.: "Você Ana".
  static bool combina(
      Gasto g, String termo, String Function(String moradorId) nomeDe) {
    final palavras =
        normalizar(termo).split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (palavras.isEmpty) return true;
    final reais = g.valorCentavos ~/ 100;
    final centavos = (g.valorCentavos % 100).toString().padLeft(2, '0');
    final texto = normalizar([
      g.descricao,
      g.categoria.label,
      nomeDe(g.pagoPorId),
      formatarReais(g.valorCentavos), // "R$ 1.234,56"
      '$reais,$centavos', // "1234,56"
    ].join(' '));
    return palavras.every(texto.contains);
  }

  static List<Gasto> filtrar(List<Gasto> gastos, String termo,
          String Function(String moradorId) nomeDe) =>
      gastos.where((g) => combina(g, termo, nomeDe)).toList();
}
