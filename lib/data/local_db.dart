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
    'tarefas',
    'tarefas_feitas',
  ];

  static const _tabelaTarefas = '''CREATE TABLE tarefas (
      id TEXT PRIMARY KEY,
      casa_id TEXT NOT NULL,
      titulo TEXT NOT NULL,
      tipo TEXT NOT NULL,
      responsavel_id TEXT,
      rodizio TEXT NOT NULL,
      repeticao TEXT NOT NULL,
      dias_semana TEXT NOT NULL,
      dia_mes INTEGER,
      proxima TEXT NOT NULL,
      concluida INTEGER NOT NULL DEFAULT 0,
      criado_por TEXT,
      updated_at TEXT NOT NULL,
      deleted INTEGER NOT NULL DEFAULT 0,
      pendente INTEGER NOT NULL DEFAULT 0)''';

  static const _tabelaTarefasFeitas = '''CREATE TABLE tarefas_feitas (
      id TEXT PRIMARY KEY,
      casa_id TEXT NOT NULL,
      tarefa_id TEXT NOT NULL,
      titulo TEXT NOT NULL,
      data_prevista TEXT NOT NULL,
      responsavel_id TEXT,
      feita_por TEXT NOT NULL,
      feita_em TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted INTEGER NOT NULL DEFAULT 0,
      pendente INTEGER NOT NULL DEFAULT 0)''';

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
    _tabelaTarefas,
    _tabelaTarefasFeitas,
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
  static Future<String> _caminho(String usuarioId) async =>
      p.join(await getDatabasesPath(), 'apesync_$usuarioId.db');

  /// Apaga o arquivo inteiro do usuário (conta excluída).
  static Future<void> excluir(String usuarioId) async =>
      deleteDatabase(await _caminho(usuarioId));

  static Future<Database> abrir(String usuarioId) async {
    return openDatabase(
      await _caminho(usuarioId),
      version: 4,
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
        if (de < 4) {
          // v4: tarefas da casa e histórico.
          await db.execute(_tabelaTarefas);
          await db.execute(_tabelaTarefasFeitas);
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
  /// Colunas que no Supabase são listas (arrays) e no SQLite viram JSON.
  static const _listas = {
    'gastos': ['dividido_entre'],
    'recorrencias': ['dividido_entre'],
    'tarefas': ['rodizio', 'dias_semana'],
  };

  /// Colunas sim/não (no Supabase boolean, no SQLite 0/1). `deleted` vale
  /// para todas as tabelas.
  static const _simNao = {
    'recorrencias': ['ativo'],
    'tarefas': ['concluida'],
  };

  static Map<String, Object?> paraRemoto(
      String tabela, Map<String, Object?> l) {
    final r = Map<String, Object?>.from(l)..remove('pendente');
    // Linha antiga (antes do administrador): deixa o servidor decidir.
    if (tabela == 'casas' && r['admin_id'] == null) r.remove('admin_id');
    for (final c in _listas[tabela] ?? const <String>[]) {
      r[c] = jsonDecode(l[c] as String);
    }
    for (final c in ['deleted', ...?_simNao[tabela]]) {
      r[c] = l[c] == 1;
    }
    return r;
  }

  /// JSON do Supabase -> linha do SQLite (já sincronizada).
  static Map<String, Object?> deRemoto(String tabela, Map<String, dynamic> r) {
    final l = Map<String, Object?>.from(r)..remove('synced_at');
    l['pendente'] = 0;
    for (final c in _listas[tabela] ?? const <String>[]) {
      l[c] = jsonEncode(r[c]);
    }
    for (final c in ['deleted', ...?_simNao[tabela]]) {
      l[c] = r[c] == true ? 1 : 0;
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
      total += Sqflite.firstIntValue(await db
              .rawQuery('SELECT COUNT(*) FROM $t WHERE pendente = 1')) ??
          0;
    }
    return total;
  }
}
