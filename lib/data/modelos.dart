import 'dart:convert';

import 'package:flutter/material.dart';

import '../theme.dart';

// =============================================================================
// Modelos do app. Cada modelo sabe se converter para:
//   - toLocal()  -> linha do SQLite do celular
//   - toRemote() -> linha do Supabase (PostgreSQL)
// Todos têm `updatedAt` (quando foi alterado) e `deleted` (exclusão lógica),
// que são o que permite sincronizar alterações e exclusões feitas offline.
// =============================================================================

/// [ajuste] não é escolhida pelo usuário: o app cria sozinho quando o
/// administrador remove um morador que estava devendo (a dívida dele é
/// dividida entre quem fica).
enum Categoria { mercado, contas, moradia, outros, ajuste }

extension CategoriaInfo on Categoria {
  /// Categorias que aparecem no "Novo gasto" e nos filtros.
  static const lancaveis = [
    Categoria.mercado,
    Categoria.contas,
    Categoria.moradia,
    Categoria.outros,
  ];

  bool get ehAjuste => this == Categoria.ajuste;

  String get label => switch (this) {
        Categoria.mercado => 'Mercado',
        Categoria.contas => 'Contas',
        Categoria.moradia => 'Moradia',
        Categoria.outros => 'Outros',
        Categoria.ajuste => 'Ajuste',
      };

  IconData get icon => switch (this) {
        Categoria.mercado => Icons.shopping_cart_outlined,
        Categoria.contas => Icons.bolt_outlined,
        Categoria.moradia => Icons.home_outlined,
        Categoria.outros => Icons.category_outlined,
        Categoria.ajuste => Icons.balance_outlined,
      };

  Color get color => switch (this) {
        Categoria.mercado => AppColors.amber,
        Categoria.contas => AppColors.blue,
        Categoria.moradia => AppColors.primary,
        Categoria.outros => AppColors.purple,
        Categoria.ajuste => AppColors.muted,
      };

  Color get background => switch (this) {
        Categoria.mercado => AppColors.amberLight,
        Categoria.contas => AppColors.blueLight,
        Categoria.moradia => AppColors.primaryLight,
        Categoria.outros => AppColors.purpleLight,
        Categoria.ajuste => AppColors.divider,
      };

  static Categoria parse(String? s) => Categoria.values
      .firstWhere((c) => c.name == s, orElse: () => Categoria.outros);
}

/// Cores dos avatares dos moradores (o banco guarda só o índice).
const paletaMoradores = [
  AppColors.primary,
  AppColors.pink,
  AppColors.blue,
  AppColors.amber,
  AppColors.purple,
  AppColors.positive,
  Color(0xFF0891B2),
  Color(0xFFEA580C),
];

// ---------------------------------------------------------------------------
// Helpers de conversão
// ---------------------------------------------------------------------------

/// Agora, em UTC, no formato ISO 8601 (o mesmo que o Postgres entende).
String agoraIso() => DateTime.now().toUtc().toIso8601String();

/// 2026-10-25 (coluna `date` do Postgres).
String dataIso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime lerData(String s) {
  final p = s.split('T').first.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

bool _lerBool(Object? v) => v == true || v == 1 || v == 'true';

// ---------------------------------------------------------------------------

class Casa {
  final String id;
  final String nome;
  final String codigoConvite;
  final String criadoPor;

  /// usuario_id (conta) de quem administra a casa.
  final String adminId;
  final String updatedAt;
  final bool deleted;

  const Casa({
    required this.id,
    required this.nome,
    required this.codigoConvite,
    required this.criadoPor,
    required this.adminId,
    required this.updatedAt,
    this.deleted = false,
  });

  factory Casa.fromMap(Map<String, Object?> m) => Casa(
        id: m['id'] as String,
        nome: m['nome'] as String,
        codigoConvite: m['codigo_convite'] as String,
        criadoPor: m['criado_por'] as String,
        // Casas antigas (antes do administrador): quem criou é o admin.
        adminId: (m['admin_id'] as String?) ?? m['criado_por'] as String,
        updatedAt: m['updated_at'] as String,
        deleted: _lerBool(m['deleted']),
      );

  Casa copia({String? nome, String? codigoConvite}) => Casa(
        id: id,
        nome: nome ?? this.nome,
        codigoConvite: codigoConvite ?? this.codigoConvite,
        criadoPor: criadoPor,
        adminId: adminId,
        updatedAt: updatedAt,
        deleted: deleted,
      );

  Map<String, Object?> toLocal() => {
        'id': id,
        'nome': nome,
        'codigo_convite': codigoConvite,
        'criado_por': criadoPor,
        'admin_id': adminId,
        'updated_at': updatedAt,
        'deleted': deleted ? 1 : 0,
      };
}

class Morador {
  final String id;
  final String casaId;
  final String nome;
  final int cor;
  final String? usuarioId;

  /// Chave PIX já normalizada (ver Pix.normalizar). Só a própria pessoa
  /// muda a dela.
  final String? chavePix;
  final String updatedAt;
  final bool deleted;

  const Morador({
    required this.id,
    required this.casaId,
    required this.nome,
    this.cor = 0,
    this.usuarioId,
    this.chavePix,
    required this.updatedAt,
    this.deleted = false,
  });

  Color get color => paletaMoradores[cor.abs() % paletaMoradores.length];
  String get inicial => nome.isEmpty ? '?' : nome[0].toUpperCase();
  bool get temConta => usuarioId != null;

  Morador copia({String? nome, bool? deleted}) => Morador(
        id: id,
        casaId: casaId,
        nome: nome ?? this.nome,
        cor: cor,
        usuarioId: usuarioId,
        chavePix: chavePix,
        updatedAt: updatedAt,
        deleted: deleted ?? this.deleted,
      );

  /// Mesma pessoa com outra chave PIX (null = remove a chave).
  Morador comChavePix(String? chave) => Morador(
        id: id,
        casaId: casaId,
        nome: nome,
        cor: cor,
        usuarioId: usuarioId,
        chavePix: chave,
        updatedAt: updatedAt,
        deleted: deleted,
      );

  factory Morador.fromMap(Map<String, Object?> m) => Morador(
        id: m['id'] as String,
        casaId: m['casa_id'] as String,
        nome: m['nome'] as String,
        cor: (m['cor'] as num?)?.toInt() ?? 0,
        usuarioId: m['usuario_id'] as String?,
        chavePix: m['chave_pix'] as String?,
        updatedAt: m['updated_at'] as String,
        deleted: _lerBool(m['deleted']),
      );

  Map<String, Object?> toLocal() => {
        'id': id,
        'casa_id': casaId,
        'nome': nome,
        'cor': cor,
        'usuario_id': usuarioId,
        'chave_pix': chavePix,
        'updated_at': updatedAt,
        'deleted': deleted ? 1 : 0,
      };
}

class Gasto {
  final String id;
  final String casaId;
  final String descricao;
  final int valorCentavos;
  final Categoria categoria;
  final String pagoPorId;
  final List<String> divididoEntre;
  final DateTime data;
  final String? criadoPor;

  /// Gasto fixo que gerou este gasto (null = lançado à mão).
  final String? recorrenciaId;
  final String updatedAt;
  final bool deleted;

  const Gasto({
    required this.id,
    required this.casaId,
    required this.descricao,
    required this.valorCentavos,
    required this.categoria,
    required this.pagoPorId,
    required this.divididoEntre,
    required this.data,
    this.criadoPor,
    this.recorrenciaId,
    this.updatedAt = '',
    this.deleted = false,
  });

  /// Parte de um morador neste gasto (divisão igualitária), em centavos.
  /// Os centavos que sobram vão para os primeiros da lista, assim a soma
  /// das partes é sempre exatamente o valor do gasto.
  int parteDe(String moradorId) {
    final i = divididoEntre.indexOf(moradorId);
    if (i < 0) return 0;
    final n = divididoEntre.length;
    return valorCentavos ~/ n + (i < valorCentavos % n ? 1 : 0);
  }

  /// Mesma linha marcada como excluída (exclusão lógica, para sincronizar).
  Gasto copiaExcluida() => Gasto(
        id: id,
        casaId: casaId,
        descricao: descricao,
        valorCentavos: valorCentavos,
        categoria: categoria,
        pagoPorId: pagoPorId,
        divididoEntre: divididoEntre,
        data: data,
        criadoPor: criadoPor,
        recorrenciaId: recorrenciaId,
        deleted: true,
      );

  factory Gasto.fromMap(Map<String, Object?> m) {
    final div = m['dividido_entre'];
    final lista = div is String
        ? (jsonDecode(div) as List).cast<String>()
        : (div as List).cast<String>();
    return Gasto(
      id: m['id'] as String,
      casaId: m['casa_id'] as String,
      descricao: m['descricao'] as String,
      valorCentavos: (m['valor_centavos'] as num).toInt(),
      categoria: CategoriaInfo.parse(m['categoria'] as String?),
      pagoPorId: m['pago_por'] as String,
      divididoEntre: lista,
      data: lerData(m['data'] as String),
      criadoPor: m['criado_por'] as String?,
      recorrenciaId: m['recorrencia_id'] as String?,
      updatedAt: m['updated_at'] as String,
      deleted: _lerBool(m['deleted']),
    );
  }

  Map<String, Object?> toLocal() => {
        'id': id,
        'casa_id': casaId,
        'descricao': descricao,
        'valor_centavos': valorCentavos,
        'categoria': categoria.name,
        'pago_por': pagoPorId,
        'dividido_entre': jsonEncode(divididoEntre),
        'data': dataIso(data),
        'criado_por': criadoPor,
        'recorrencia_id': recorrenciaId,
        'updated_at': updatedAt,
        'deleted': deleted ? 1 : 0,
      };
}

/// Gasto fixo (aluguel, internet...): vira um [Gasto] por mês, no [dia]
/// escolhido, a partir do mês [inicio] (AAAA-MM).
class Recorrencia {
  final String id;
  final String casaId;
  final String descricao;
  final int valorCentavos;
  final Categoria categoria;
  final String pagoPorId;
  final List<String> divididoEntre;
  final int dia;
  final String inicio;
  final bool ativo;
  final String? criadoPor;
  final String updatedAt;
  final bool deleted;

  const Recorrencia({
    required this.id,
    required this.casaId,
    required this.descricao,
    required this.valorCentavos,
    required this.categoria,
    required this.pagoPorId,
    required this.divididoEntre,
    required this.dia,
    required this.inicio,
    this.ativo = true,
    this.criadoPor,
    this.updatedAt = '',
    this.deleted = false,
  });

  Recorrencia copia({
    String? descricao,
    int? valorCentavos,
    String? inicio,
    bool? ativo,
    bool? deleted,
  }) =>
      Recorrencia(
        id: id,
        casaId: casaId,
        descricao: descricao ?? this.descricao,
        valorCentavos: valorCentavos ?? this.valorCentavos,
        categoria: categoria,
        pagoPorId: pagoPorId,
        divididoEntre: divididoEntre,
        dia: dia,
        inicio: inicio ?? this.inicio,
        ativo: ativo ?? this.ativo,
        criadoPor: criadoPor,
        updatedAt: updatedAt,
        deleted: deleted ?? this.deleted,
      );

  factory Recorrencia.fromMap(Map<String, Object?> m) {
    final div = m['dividido_entre'];
    final lista = div is String
        ? (jsonDecode(div) as List).cast<String>()
        : (div as List).cast<String>();
    return Recorrencia(
      id: m['id'] as String,
      casaId: m['casa_id'] as String,
      descricao: m['descricao'] as String,
      valorCentavos: (m['valor_centavos'] as num).toInt(),
      categoria: CategoriaInfo.parse(m['categoria'] as String?),
      pagoPorId: m['pago_por'] as String,
      divididoEntre: lista,
      dia: (m['dia'] as num).toInt(),
      inicio: m['inicio'] as String,
      ativo: _lerBool(m['ativo']),
      criadoPor: m['criado_por'] as String?,
      updatedAt: m['updated_at'] as String,
      deleted: _lerBool(m['deleted']),
    );
  }

  Map<String, Object?> toLocal() => {
        'id': id,
        'casa_id': casaId,
        'descricao': descricao,
        'valor_centavos': valorCentavos,
        'categoria': categoria.name,
        'pago_por': pagoPorId,
        'dividido_entre': jsonEncode(divididoEntre),
        'dia': dia,
        'inicio': inicio,
        'ativo': ativo ? 1 : 0,
        'criado_por': criadoPor,
        'updated_at': updatedAt,
        'deleted': deleted ? 1 : 0,
      };
}

class Pagamento {
  final String id;
  final String casaId;
  final String deId;
  final String paraId;
  final int valorCentavos;
  final DateTime data;
  final String updatedAt;
  final bool deleted;

  const Pagamento({
    required this.id,
    required this.casaId,
    required this.deId,
    required this.paraId,
    required this.valorCentavos,
    required this.data,
    this.updatedAt = '',
    this.deleted = false,
  });

  Pagamento copiaExcluida() => Pagamento(
        id: id,
        casaId: casaId,
        deId: deId,
        paraId: paraId,
        valorCentavos: valorCentavos,
        data: data,
        deleted: true,
      );

  factory Pagamento.fromMap(Map<String, Object?> m) => Pagamento(
        id: m['id'] as String,
        casaId: m['casa_id'] as String,
        deId: m['de_id'] as String,
        paraId: m['para_id'] as String,
        valorCentavos: (m['valor_centavos'] as num).toInt(),
        data: lerData(m['data'] as String),
        updatedAt: m['updated_at'] as String,
        deleted: _lerBool(m['deleted']),
      );

  Map<String, Object?> toLocal() => {
        'id': id,
        'casa_id': casaId,
        'de_id': deId,
        'para_id': paraId,
        'valor_centavos': valorCentavos,
        'data': dataIso(data),
        'updated_at': updatedAt,
        'deleted': deleted ? 1 : 0,
      };
}

/// Uma transferência sugerida pela simplificação de dívidas.
class Transferencia {
  final String deId;
  final String paraId;
  final int valorCentavos;
  const Transferencia(this.deId, this.paraId, this.valorCentavos);
}

// ---------- Formatação (sem pacote intl) ----------

String formatarReais(int centavos) {
  final negativo = centavos < 0;
  final abs = centavos.abs();
  final reais = (abs ~/ 100).toString();
  final cent = (abs % 100).toString().padLeft(2, '0');
  final buf = StringBuffer();
  for (var i = 0; i < reais.length; i++) {
    if (i > 0 && (reais.length - i) % 3 == 0) buf.write('.');
    buf.write(reais[i]);
  }
  return '${negativo ? '- ' : ''}R\$ $buf,$cent';
}

/// Converte "120", "120,5", "1.234,56" em centavos. Retorna null se inválido.
int? parseReais(String texto) {
  final limpo = texto
      .replaceAll('R\$', '')
      .replaceAll(' ', '')
      .replaceAll('.', '')
      .replaceAll(',', '.');
  final v = double.tryParse(limpo);
  if (v == null || v <= 0) return null;
  return (v * 100).round();
}

const _meses = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro'
];

String nomeMes(DateTime d) {
  final m = _meses[d.month - 1];
  return '${m[0].toUpperCase()}${m.substring(1)} ${d.year}';
}

String diaPorExtenso(DateTime d) => '${d.day} de ${_meses[d.month - 1]}';

String dataCurta(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
