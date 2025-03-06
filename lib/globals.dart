import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

// Global database instances
late Database db;
late Database settingsDb;
late BuildContext globalContext;

// App theme
final appTheme = ThemeData(
  primarySwatch: Colors.blue,
  visualDensity: VisualDensity.adaptivePlatformDensity,
);

// Initialize databases
Future<void> initDatabases() async {
  final databasesPath = await getDatabasesPath();

  // Initialize main database
  db = await openDatabase(
    join(databasesPath, 'memorizer.db'),
    version: 1,
    onCreate: (db, version) {
      return db.execute(
        'CREATE TABLE IF NOT EXISTS items(id INTEGER PRIMARY KEY, title TEXT, content TEXT, tags TEXT, priority INTEGER, reminder INTEGER, created INTEGER)',
      );
    },
  );

  // Initialize settings database
  settingsDb = await openDatabase(
    join(databasesPath, 'settings.db'),
    version: 1,
    onCreate: (db, version) {
      return db.execute(
          'CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT)',
      );
    },
  );
}

// Settings functions (universal across the app)
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

// Navigation helpers
void navigateToScreen(Widget screen) {
  Navigator.push(
    globalContext,
    MaterialPageRoute(builder: (context) => screen),
  );
}

void navigateBack() {
  Navigator.pop(globalContext);
}

// UI helpers
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