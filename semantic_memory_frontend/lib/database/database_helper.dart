import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';


class DatabaseHelper {

  static final DatabaseHelper instance = DatabaseHelper._init();

  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {

    if (_database != null) return _database!;

    _database = await _initDB("semantic_memory.db");

    return _database!;
  }

  Future<Database> _initDB(String filePath) async {

    final dbPath = await getDatabasesPath();

    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
      CREATE TABLE document_embeddings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT,
        chunk_text TEXT,
        embedding TEXT,
        chunk_index INTEGER
      )
      ''');
    }
  }

  Future _createDB(Database db, int version) async {

    await db.execute('''
    CREATE TABLE embeddings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      file_path TEXT UNIQUE,
      embedding TEXT,
      indexed_at INTEGER
    )
    ''');

    await db.execute('''
    CREATE TABLE document_embeddings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      file_path TEXT,
      chunk_text TEXT,
      embedding TEXT,
      chunk_index INTEGER
    )
    ''');
  }
  

  Future<List<Map<String, dynamic>>> getAllEmbeddings() async {
    final db = await instance.database;
    return await db.query("embeddings");
  }

  /// Lean query — returns ONLY file_path column from the image index.
  /// Never fetches the embedding column, preventing OOM when listing images.
  Future<List<String>> getAllImagePaths() async {
    final db = await instance.database;
    final rows = await db.rawQuery('SELECT file_path FROM embeddings');
    return rows.map((r) => r['file_path'] as String).toList();
  }

  /// Lean query — returns one row per unique document (file_path + first chunk_text).
  /// Never fetches the embedding column, preventing OOM when listing documents.
  Future<List<Map<String, dynamic>>> getDistinctDocumentPaths() async {
    final db = await instance.database;
    final rows = await db.rawQuery('''
      SELECT file_path, chunk_text
      FROM document_embeddings
      WHERE chunk_index = 0
      GROUP BY file_path
      ORDER BY file_path ASC
    ''');
    return rows
        .map((r) => {
              'path': r['file_path'] as String,
              'chunk': r['chunk_text'] as String? ?? '',
            })
        .toList();
  }

  Future<void> insertEmbedding(String path, List<double> embedding) async {

    final db = await instance.database;

    await db.insert(
      "embeddings",
      {
        "file_path": path,
        "embedding": embedding.join(","),
        "indexed_at": DateTime.now().millisecondsSinceEpoch
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
  Future<bool> isIndexed(String path) async {

  final db = await instance.database;

  final result = await db.query(
    "embeddings",
    where: "file_path = ?",
    whereArgs: [path],
  );

  return result.isNotEmpty;
  }

  Future<bool> isDocumentIndexed(String path) async {
    final db = await instance.database;
    final result = await db.query(
      "document_embeddings",
      where: "file_path = ?",
      whereArgs: [path],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<void> insertDocumentEmbedding(
    String path,
    String chunk,
    List embedding,
    int index
  ) async {

    final db = await database;

    await db.insert(
      "document_embeddings",
      {
        "file_path": path,
        "chunk_text": chunk,
        "embedding": jsonEncode(embedding),
        "chunk_index": index
      },
    );
  }

  Future<List<Map<String, dynamic>>> getAllDocumentEmbeddings() async {
    final db = await instance.database;
    return await db.query("document_embeddings");
  }

  Future<int> getDocumentEmbeddingsCount() async {
    final db = await instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM document_embeddings');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Map<String, dynamic>>> getPaginatedDocumentEmbeddings(int limit, int offset) async {
    final db = await instance.database;
    return await db.query(
      "document_embeddings",
      limit: limit,
      offset: offset,
      orderBy: "id ASC",
    );
  }

  Future<void> clearDocumentEmbeddings() async {
    final db = await instance.database;
    await db.delete("document_embeddings");
  }

  Future<void> deleteEmbeddingByPath(String path) async {
    final db = await instance.database;
    await db.delete(
      "embeddings",
      where: "file_path = ?",
      whereArgs: [path],
    );
  }

  Future<void> deleteDocumentEmbeddingByPath(String path) async {
    final db = await instance.database;
    await db.delete(
      "document_embeddings",
      where: "file_path = ?",
      whereArgs: [path],
    );
  }

  /// Keyword-based fallback: searches chunk_text and file_path using SQL LIKE.
  /// Used when the in-memory vector index hasn't finished loading yet.
  Future<List<Map<String, dynamic>>> searchDocumentsByKeyword(
    String query, {
    int limit = 10,
  }) async {
    final db = await instance.database;
    final words = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .toList();

    if (words.isEmpty) return [];

    // Build a WHERE clause that ANDs all non-trivial words
    final conditions =
        words.map((_) => '(LOWER(chunk_text) LIKE ? OR LOWER(file_path) LIKE ?)').join(' AND ');
    final args = words.expand((w) => ['%$w%', '%$w%']).toList();

    final rows = await db.rawQuery(
      '''
      SELECT file_path, chunk_text
      FROM document_embeddings
      WHERE chunk_index != -1 AND $conditions
      LIMIT $limit
      ''',
      args,
    );

    // Deduplicate by file_path, keeping the first (highest-rank) chunk
    final Map<String, Map<String, dynamic>> deduped = {};
    for (final row in rows) {
      final path = row['file_path'] as String;
      if (!deduped.containsKey(path)) {
        deduped[path] = {
          'path': path,
          'chunk': row['chunk_text'] as String,
          'score': 0.0,
          'type': 'document',
          'isKeywordResult': true,
        };
      }
    }
    return deduped.values.toList();
  }

  /// Path-based fallback: finds indexed images whose file path contains any query word.
  Future<List<Map<String, dynamic>>> searchImagesByPath(
    String query, {
    int limit = 10,
  }) async {
    final db = await instance.database;
    final words = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .toList();

    if (words.isEmpty) return [];

    final conditions = words.map((_) => 'LOWER(file_path) LIKE ?').join(' OR ');
    final args = words.map((w) => '%$w%').toList();

    final rows = await db.rawQuery(
      '''
      SELECT file_path
      FROM embeddings
      WHERE $conditions
      LIMIT $limit
      ''',
      args,
    );

    return rows
        .map((r) => {
              'path': r['file_path'] as String,
              'score': 0.0,
              'type': 'image',
              'isKeywordResult': true,
            })
        .toList();
  }
}