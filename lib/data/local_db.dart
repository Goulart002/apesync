import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Banco LOCAL (SQLite) do celular. É a fonte da verdade da interface:
/// as telas leem e escrevem só aqui, com ou sem internet.
/// Cada tabela espelha a do Supabase e tem a coluna extra `pendente`
/// (1 = alteração feita no celular que ainda não subiu para o servidor).
class LocalDb {
  /// Na ordem do envio: quem é referenciado vem antes (casa, morador,
  /// gasto fixo, gasto...).
  static const tabelas = [
    'casas',
    'moradores',
    'recorrencias',
    'gastos',
    'pagamentos',
  ];

  static const _tabelaRecorrencias = '''CREATE TABLE recorrencias (
      id TEXT PRIMARY KEY,
      casa_id TEXT NOT NULL,
      descricao TEXT NOT NULL,
      valor_centavos INTEGER NOT NULL,
      categoria TEXT NOT NULL,
      pago_por TEXT NOT NULL,
      dividido_entre TEXT NOT NULL,
      dia INTEGER NOT NULL,
      inicio TEXT NOT NULL,
      ativo INTEGER NOT NULL DEFAULT 1,
      criado_por TEXT,
      updated_at TEXT NOT NULL,
      deleted INTEGER NOT NULL DEFAULT 0,
      pendente INTEGER NOT NULL DEFAULT 0)''';

  static const _schema = [
    '''CREATE TABLE casas (
      id TEXT PRIMARY KEY,
      nome TEXT NOT NULL,
      codigo_convite TEXT NOT NULL,
      criado_por TEXT NOT NULL,
      admin_id TEXT,
      updated_at TEXT NOT NULL,
      deleted INTEGER NOT NULL DEFAULT 0,
      pendente INTEGER NOT NULL DEFAULT 0)''',
    '''CREATE TABLE moradores (
      id TEXT PRIMARY KEY,
      casa_id TEXT NOT NULL,
      nome TEXT NOT NULL,
      cor INTEGER NOT NULL DEFAULT 0,
      usuario_id TEXT,
      chave_pix TEXT,
      updated_at TEXT NOT NULL,
      deleted INTEGER NOT NULL DEFAULT 0,
      pendente INTEGER NOT NULL DEFAULT 0)''',
    '''CREATE TABLE gastos (
      id TEXT PRIMARY KEY,
      casa_id TEXT NOT NULL,
      descricao TEXT NOT NULL,
      valor_centavos INTEGER NOT NULL,
      categoria TEXT NOT NULL,
      pago_por TEXT NOT NULL,
      dividido_entre TEXT NOT NULL,
      data TEXT NOT NULL,
      criado_por TEXT,
      recorrencia_id TEXT,
      updated_at TEXT NOT NULL,
      deleted INTEGER NOT NULL DEFAULT 0,
      pendente INTEGER NOT NULL DEFAULT 0)''',
    _tabelaRecorrencias,
    '''CREATE TABLE pagamentos (
      id TEXT PRIMARY KEY,
      casa_id TEXT NOT NULL,
      de_id TEXT NOT NULL,
      para_id TEXT NOT NULL,
      valor_centavos INTEGER NOT NULL,
      data TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted INTEGER NOT NULL DEFAULT 0,
      pendente INTEGER NOT NULL DEFAULT 0)''',
    'CREATE TABLE meta (chave TEXT PRIMARY KEY, valor TEXT)',
    'CREATE INDEX gastos_casa ON gastos (casa_id)',
    'CREATE INDEX pagamentos_casa ON pagamentos (casa_id)',
    'CREATE INDEX moradores_casa ON moradores (casa_id)',
  ];

  /// Um arquivo por usuário, para contas diferentes não se misturarem.
  static Future<Database> abrir(String usuarioId) async {
    final caminho = p.join(await getDatabasesPath(), 'apesync_$usuarioId.db');
    return openDatabase(
      caminho,
      version: 3,
      onCreate: (db, _) async {
        for (final sql in _schema) {
          await db.execute(sql);
        }
      },
      onUpgrade: (db, de, para) async {
        if (de < 2) {
          // v2: administrador da casa. Zera a marca do download das casas
          // para baixar de novo já com o admin_id.
          await db.execute('ALTER TABLE casas ADD COLUMN admin_id TEXT');
          await db.delete('meta',
              where: 'chave LIKE ?', whereArgs: ['pull_casas_%']);
        }
        if (de < 3) {
          // v3: chave PIX dos moradores e gastos fixos.
          await db.execute('ALTER TABLE moradores ADD COLUMN chave_pix TEXT');
          await db.execute('ALTER TABLE gastos ADD COLUMN recorrencia_id TEXT');
          await db.execute(_tabelaRecorrencias);
        }
      },
    );
  }

  /// Apaga do celular tudo de uma casa (quando o usuário sai ou é removido).
  static Future<void> apagarCasa(Database db, String casaId) =>
      db.transaction((t) async {
        for (final tabela in tabelas.where((t) => t != 'casas')) {
          await t.delete(tabela, where: 'casa_id = ?', whereArgs: [casaId]);
        }
        await t.delete('casas', where: 'id = ?', whereArgs: [casaId]);
        await t.delete('meta',
            where: 'chave LIKE ?', whereArgs: ['pull_%_$casaId']);
      });

  /// Descarta uma alteração local que o servidor recusou (sem permissão) e
  /// força baixar a tabela de novo, para voltar à versão do servidor.
  static Future<void> descartar(
      Database db, String tabela, String id, String casaId) async {
    await db.delete(tabela, where: 'id = ?', whereArgs: [id]);
    await db.delete('meta',
        where: 'chave = ?', whereArgs: ['pull_${tabela}_$casaId']);
  }

  // ---------------- conversão local <-> Supabase ----------------

  /// Linha do SQLite -> JSON para o Supabase.
  static Map<String, Object?> paraRemoto(
      String tabela, Map<String, Object?> l) {
    final r = Map<String, Object?>.from(l)..remove('pendente');
    r['deleted'] = l['deleted'] == 1;
    // Linha antiga (antes do administrador): deixa o servidor decidir.
    if (tabela == 'casas' && r['admin_id'] == null) r.remove('admin_id');
    if (tabela == 'gastos' || tabela == 'recorrencias') {
      r['dividido_entre'] = jsonDecode(l['dividido_entre'] as String);
    }
    if (tabela == 'recorrencias') r['ativo'] = l['ativo'] == 1;
    return r;
  }

  /// JSON do Supabase -> linha do SQLite (já sincronizada).
  static Map<String, Object?> deRemoto(String tabela, Map<String, dynamic> r) {
    final l = Map<String, Object?>.from(r)..remove('synced_at');
    l['deleted'] = r['deleted'] == true ? 1 : 0;
    l['pendente'] = 0;
    if (tabela == 'gastos' || tabela == 'recorrencias') {
      l['dividido_entre'] = jsonEncode(r['dividido_entre']);
    }
    if (tabela == 'recorrencias') l['ativo'] = r['ativo'] == true ? 1 : 0;
    return l;
  }

  // ---------------- meta (marcas do último download) ----------------

  static Future<String?> lerMeta(Database db, String chave) async {
    final r = await db.query('meta', where: 'chave = ?', whereArgs: [chave]);
    return r.isEmpty ? null : r.first['valor'] as String?;
  }

  static Future<void> gravarMeta(Database db, String chave, String valor) =>
      db.insert('meta', {'chave': chave, 'valor': valor},
          conflictAlgorithm: ConflictAlgorithm.replace);

  static Future<int> contarPendentes(Database db) async {
    var total = 0;
    for (final t in tabelas) {
      total += Sqflite.firstIntValue(await db
              .rawQuery('SELECT COUNT(*) FROM $t WHERE pendente = 1')) ??
          0;
    }
    return total;
  }
}
