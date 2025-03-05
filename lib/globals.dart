import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

// Global variables
late Database db;
late Database settingsDb;
late BuildContext globalContext;

// Theme settings
final appTheme = ThemeData(
  primarySwatch: Colors.blue,
  visualDensity: VisualDensity.adaptivePlatformDensity,
);

// Database functions
Future<void> initDatabases() async {
  final databasesPath = await getDatabasesPath();
  
  // Initialize main database
  db = await openDatabase(
    join(databasesPath, 'memorizer.db'),
    version: 1,
    onCreate: (db, version) {
      return db.execute(
        'CREATE TABLE items(id INTEGER PRIMARY KEY, title TEXT, content TEXT, created_at INTEGER)',
      );
    },
  );
  
  // Initialize settings database
  settingsDb = await openDatabase(
    join(databasesPath, 'settings.db'),
    version: 1,
    onCreate: (db, version) {
      return db.execute(
        'CREATE TABLE settings(id INTEGER PRIMARY KEY, key TEXT UNIQUE, value TEXT)',
      );
    },
  );
}

// Item database functions
Future<void> insertItem(String title, String content) async {
  await db.insert(
    'items',
    {
      'title': title,
      'content': content,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<List<Map<String, dynamic>>> getItems() async {
  return await db.query('items', orderBy: 'created_at DESC');
}

Future<void> updateItem(int id, String title, String content) async {
  await db.update(
    'items',
    {
      'title': title,
      'content': content,
    },
    where: 'id = ?',
    whereArgs: [id],
  );
}

Future<void> deleteItem(int id) async {
  await db.delete(
    'items',
    where: 'id = ?',
    whereArgs: [id],
  );
}

// Settings database functions
Future<void> saveSetting(String key, String value) async {
  await settingsDb.insert(
    'settings',
    {'key': key, 'value': value},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<String?> getSetting(String key) async {
  final List<Map<String, dynamic>> result = await settingsDb.query(
    'settings',
    columns: ['value'],
    where: 'key = ?',
    whereArgs: [key],
  );
  
  return result.isNotEmpty ? result.first['value'] as String : null;
}

// Navigation functions
void navigateToScreen(Widget screen) {
  Navigator.push(
    globalContext,
    MaterialPageRoute(builder: (context) => screen),
  );
}

void navigateBack() {
  Navigator.pop(globalContext);
}

// UI helper functions
AppBar buildAppBar(String title) {
  return AppBar(
    title: Text(title),
    leading: IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => navigateBack(),
    ),
    actions: [
      IconButton(
        icon: const Icon(Icons.menu),
        onPressed: () {
          // Menu functionality
        },
      ),
    ],
  );
}

FloatingActionButton buildAddButton(Function() onPressed) {
  return FloatingActionButton(
    onPressed: onPressed,
    child: const Icon(Icons.add),
  );
}
