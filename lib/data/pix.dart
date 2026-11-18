/// PIX: validação da chave e geração do código "PIX copia e cola"
/// (BR Code estático, padrão EMV do Banco Central). Regras puras, testáveis.
///
/// O código gerado já leva a chave de quem recebe e o valor: quem paga abre
/// o app do banco, escolhe "Pix Copia e Cola", cola e confirma.
library;

enum TipoChavePix { cpf, cnpj, email, celular, aleatoria }

extension TipoChavePixInfo on TipoChavePix {
  String get label => switch (this) {
        TipoChavePix.cpf => 'CPF',
        TipoChavePix.cnpj => 'CNPJ',
        TipoChavePix.email => 'E-mail',
        TipoChavePix.celular => 'Celular',
        TipoChavePix.aleatoria => 'Chave aleatória',
      };

  String get exemplo => switch (this) {
        TipoChavePix.cpf => '123.456.789-09',
        TipoChavePix.cnpj => '12.345.678/0001-95',
        TipoChavePix.email => 'voce@email.com',
        TipoChavePix.celular => '(31) 99999-9999',
        TipoChavePix.aleatoria => '123e4567-e89b-12d3-a456-426614174000',
      };
}

class Pix {
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _uuid =
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

  static String _digitos(String s) => s.replaceAll(RegExp(r'\D'), '');

  /// Deixa a chave no formato que o PIX usa (CPF/CNPJ só números,
  /// celular com +55, e-mail e aleatória em minúsculas).
  /// Retorna null se a chave não for válida para o tipo.
  static String? normalizar(TipoChavePix tipo, String texto) {
    final t = texto.trim();
    switch (tipo) {
      case TipoChavePix.cpf:
        final d = _digitos(t);
        return d.length == 11 ? d : null;
      case TipoChavePix.cnpj:
        final d = _digitos(t);
        return d.length == 14 ? d : null;
      case TipoChavePix.email:
        final e = t.toLowerCase();
        return e.length <= 77 && _email.hasMatch(e) ? e : null;
      case TipoChavePix.celular:
        var d = _digitos(t);
        if (d.startsWith('55') && (d.length == 12 || d.length == 13)) {
          d = d.substring(2);
        }
        return d.length == 10 || d.length == 11 ? '+55$d' : null;
      case TipoChavePix.aleatoria:
        final a = t.toLowerCase();
        return _uuid.hasMatch(a) ? a : null;
    }
  }

  /// Adivinha o tipo de uma chave já salva (para preencher o formulário).
  static TipoChavePix tipoDe(String chave) {
    if (chave.startsWith('+')) return TipoChavePix.celular;
    if (chave.contains('@')) return TipoChavePix.email;
    if (_uuid.hasMatch(chave)) return TipoChavePix.aleatoria;
    if (chave.length == 14) return TipoChavePix.cnpj;
    return TipoChavePix.cpf;
  }

  /// Código "PIX copia e cola" (BR Code estático).
  ///
  /// - [chave]: chave PIX já normalizada de quem RECEBE.
  /// - [nome]: nome de quem recebe (vai sem acento, até 25 letras).
  /// - [valorCentavos]: valor já preenchido (null = quem paga digita).
  static String copiaECola({
    required String chave,
    required String nome,
    int? valorCentavos,
    String cidade = 'BRASIL',
    String identificador = '***',
  }) {
    String campo(String id, String valor) =>
        '$id${valor.length.toString().padLeft(2, '0')}$valor';

    final conta = campo('00', 'br.gov.bcb.pix') + campo('01', chave);
    final buf = StringBuffer()
      ..write(campo('00', '01'))
      ..write(campo('26', conta))
      ..write(campo('52', '0000'))
      ..write(campo('53', '986'));
    if (valorCentavos != null && valorCentavos > 0) {
      final reais = valorCentavos ~/ 100;
      final cent = (valorCentavos % 100).toString().padLeft(2, '0');
      buf.write(campo('54', '$reais.$cent'));
    }
    buf
      ..write(campo('58', 'BR'))
      ..write(campo('59', _textoSimples(nome, 25, 'MORADOR')))
      ..write(campo('60', _textoSimples(cidade, 15, 'BRASIL')))
      ..write(campo('62', campo('05', identificador)))
      ..write('6304');
    final semCrc = buf.toString();
    return '$semCrc${crc16(semCrc)}';
  }

  /// CRC16-CCITT (polinômio 0x1021, início 0xFFFF), em 4 dígitos hexa
  /// maiúsculos — o "dígito verificador" do BR Code.
  static String crc16(String texto) {
    var crc = 0xFFFF;
    for (final byte in texto.codeUnits) {
      crc ^= byte << 8;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) : (crc << 1);
        crc &= 0xFFFF;
      }
    }
    return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
  }

  /// Só letras sem acento, números e espaço (o BR Code exige ASCII).
  static String _textoSimples(String s, int max, String padrao) {
    const de = 'áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ';
    const para = 'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN';
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final i = de.indexOf(ch);
      final c = i >= 0 ? para[i] : ch;
      if (RegExp(r'[A-Za-z0-9 ]').hasMatch(c)) b.write(c);
    }
    var r = b.toString().trim().replaceAll(RegExp(r' +'), ' ');
    if (r.isEmpty) r = padrao;
    return r.length > max ? r.substring(0, max).trim() : r;
  }
}
