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
}