import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../data/modelos.dart';

/// O que foi possível extrair de uma nota fiscal. Qualquer campo pode vir null.
class NotaLida {
  final int? valorCentavos;
  final DateTime? data;
  final String? estabelecimento;
  final Categoria? categoria;

  const NotaLida({
    this.valorCentavos,
    this.data,
    this.estabelecimento,
    this.categoria,
  });

  /// Sem total e sem data não dá pra considerar que leu uma nota.
  bool get vazia => valorCentavos == null && data == null;
}

/// Lê uma foto de nota fiscal / cupom com OCR no próprio aparelho (Google ML Kit)
/// e tenta encontrar total, data e nome do estabelecimento.
class NotaScanner {
  /// O ML Kit só existe em Android e iOS (não funciona no Chrome nem no desktop).
  static bool get suportado =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Abre a câmera (ou a galeria), roda o OCR e interpreta o texto.
  /// Retorna null se o usuário cancelar.
  static Future<NotaLida?> escanear(ImageSource origem) async {
    final foto = await ImagePicker().pickImage(
      source: origem,
      maxWidth: 2000,
      imageQuality: 90,
    );
    if (foto == null) return null;

    final reconhecedor = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final resultado =
          await reconhecedor.processImage(InputImage.fromFilePath(foto.path));
      return interpretar(resultado.text);
    } finally {
      reconhecedor.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Interpretação do texto (função pura: não depende de câmera, dá pra testar).
  // ---------------------------------------------------------------------------

  /// Valores como "1.234,56", "58,00", "58.00" ou "58, 00" (erro comum do OCR).
  static final _dinheiro =
      RegExp(r'(\d{1,3}(?:\.\d{3})+|\d+)\s?[,.]\s?(\d{2})(?!\d)');
  static final _dataRegex = RegExp(r'(\d{2})[/.-](\d{2})[/.-](\d{4})');

  static const _palavrasTotal = [
    'VALOR A PAGAR',
    'VALOR TOTAL',
    'TOTAL A PAGAR',
    'TOTAL R\$',
    'TOTAL',
  ];

  /// Linhas cujo valor não é o total da compra.
  static const _ignorar = [
    'TROCO',
    'DINHEIRO',
    'RECEBIDO',
    'DESCONTO',
    'TRIBUTOS',
    'IMPOSTO',
    'LEI 12.741',
    'QTD',
    'ITENS',
  ];

  static const _palavrasMercado = [
    'SUPERMERCADO', 'MERCADO', 'ATACAD', 'HORTIFRUTI', 'SACOLAO',
    'SACOLÃO', 'PADARIA', 'PANIFICADORA', 'MERCEARIA', 'ACOUGUE', 'AÇOUGUE',
  ];
  static const _palavrasContas = [
    'ENERGIA', 'CEMIG', 'COPASA', 'SANEAMENTO', 'INTERNET', 'TELECOM',
    'TELEFONIA', 'FATURA', 'GAS ', 'GÁS ',
  ];

  static NotaLida interpretar(String texto) {
    final linhas = texto
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final maiusculo = texto.toUpperCase();

    return NotaLida(
      valorCentavos: _acharTotal(linhas),
      data: _acharData(texto),
      estabelecimento: _acharEstabelecimento(linhas),
      categoria: _acharCategoria(maiusculo),
    );
  }

  static List<int> _valoresNaLinha(String linha) => _dinheiro
      .allMatches(linha)
      .map((m) =>
          int.parse(m.group(1)!.replaceAll('.', '')) * 100 +
          int.parse(m.group(2)!))
      .where((v) => v > 0)
      .toList();

  static bool _linhaIgnorada(String upper) =>
      _ignorar.any((p) => upper.contains(p));

  static int? _acharTotal(List<String> linhas) {
    // 1) Linha com palavra-chave de total (em ordem de prioridade),
    //    valor na mesma linha ou na linha seguinte.
    for (final chave in _palavrasTotal) {
      for (var i = 0; i < linhas.length; i++) {
        final upper = linhas[i].toUpperCase();
        if (!upper.contains(chave) || upper.contains('SUBTOTAL')) continue;
        if (_linhaIgnorada(upper)) continue;
        final mesma = _valoresNaLinha(linhas[i]);
        if (mesma.isNotEmpty) return mesma.last;
        if (i + 1 < linhas.length) {
          final prox = _valoresNaLinha(linhas[i + 1]);
          if (prox.isNotEmpty) return prox.last;
        }
      }
    }
    // 2) Fallback: maior valor da nota, fora de troco/pagamento/impostos.
    int? maior;
    for (final l in linhas) {
      if (_linhaIgnorada(l.toUpperCase())) continue;
      for (final v in _valoresNaLinha(l)) {
        if (maior == null || v > maior) maior = v;
      }
    }
    return maior;
  }

  static DateTime? _acharData(String texto) {
    final agora = DateTime.now();
    for (final m in _dataRegex.allMatches(texto)) {
      final dia = int.parse(m.group(1)!);
      final mes = int.parse(m.group(2)!);
      final ano = int.parse(m.group(3)!);
      if (dia < 1 || dia > 31 || mes < 1 || mes > 12) continue;
      if (ano < 2000 || ano > agora.year + 1) continue;
      return DateTime(ano, mes, dia);
    }
    return null;
  }

  static const _naoNome = [
    'CNPJ', 'CPF', 'CUPOM', 'NFC', 'NF-E', 'DOCUMENTO', 'AUXILIAR',
    'CONSUMIDOR', 'ELETR', 'EXTRATO', 'SAT', 'RUA ', 'AV.', 'AVENIDA',
    'CEP', 'TEL', 'FONE', 'IE:', 'INSCR',
  ];

  static String? _acharEstabelecimento(List<String> linhas) {
    for (final l in linhas.take(6)) {
      final upper = l.toUpperCase();
      if (_naoNome.any((p) => upper.contains(p))) continue;
      final letras = RegExp(r'[A-Za-zÀ-ÿ]').allMatches(l).length;
      final digitos = RegExp(r'\d').allMatches(l).length;
      if (letras < 4 || digitos > letras / 3) continue;
      return _tituloCurto(l);
    }
    return null;
  }

  /// "SUPERMERCADO BH LTDA" -> "Supermercado Bh Ltda" (máx. 40 caracteres).
  static String _tituloCurto(String s) {
    final t = s
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
        .join(' ');
    return t.length > 40 ? t.substring(0, 40).trim() : t;
  }

  static Categoria? _acharCategoria(String upper) {
    if (_palavrasMercado.any(upper.contains)) return Categoria.mercado;
    if (_palavrasContas.any(upper.contains)) return Categoria.contas;
    return null;
  }
}
