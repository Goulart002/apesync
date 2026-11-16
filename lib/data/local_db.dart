import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Banco LOCAL (SQLite) do celular. É a fonte da verdade da interface:
/// as telas leem e escrevem só aqui, com ou sem internet.
/// Cada tabela espelha a do Supabase e tem a coluna extra `pendente`
/// (1 = alteração feita no celular que ainda não subiu para o servidor).
class LocalDb {
  static const tabelas = ['casas', 'moradores', 'gastos', 'pagamentos'];

  static const _schema = [
    '''CREATE TABLE casas (
      id TEXT PRIMARY KEY,
      nome TEXT NOT NULL,
      codigo_convite TEXT NOT NULL,
      criado_por TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted INTEGER NOT NULL DEFAULT 0,
      pendente INTEGER NOT NULL DEFAULT 0)''',
    '''CREATE TABLE moradores (
      id TEXT PRIMARY KEY,
      casa_id TEXT NOT NULL,
      nome TEXT NOT NULL,
      cor INTEGER NOT NULL DEFAULT 0,
      usuario_id TEXT,
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
      updated_at TEXT NOT NULL,
      deleted INTEGER NOT NULL DEFAULT 0,
      pendente INTEGER NOT NULL DEFAULT 0)''',
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
      version: 1,
      onCreate: (db, _) async {
        for (final sql in _schema) {
          await db.execute(sql);
        }
      },
    );
  }

  // ---------------- conversão local <-> Supabase ----------------

  /// Linha do SQLite -> JSON para o Supabase.
  static Map<String, Object?> paraRemoto(String tabela, Map<String, Object?> l) {
    final r = Map<String, Object?>.from(l)..remove('pendente');
    r['deleted'] = l['deleted'] == 1;
    if (tabela == 'gastos') {
      r['dividido_entre'] = jsonDecode(l['dividido_entre'] as String);
    }
    return r;
  }

  /// JSON do Supabase -> linha do SQLite (já sincronizada).
  static Map<String, Object?> deRemoto(String tabela, Map<String, dynamic> r) {
    final l = Map<String, Object?>.from(r)..remove('synced_at');
    l['deleted'] = r['deleted'] == true ? 1 : 0;
    l['pendente'] = 0;
    if (tabela == 'gastos') {
      l['dividido_entre'] = jsonEncode(r['dividido_entre']);
    }
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
      total += Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM $t WHERE pendente = 1')) ??
          0;
    }
    return total;
  }
}
