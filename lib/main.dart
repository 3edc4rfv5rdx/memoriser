import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'globals.dart';

// Include the database functions directly in main.dart until db_service.dart is created
// Item database functions
Future<void> insertItem(String title, String content, {String tags = '', int priority = 0, int? reminder}) async {
  await db.insert(
    'items',
    {
      'title': title,
      'content': content,
      'tags': tags,
      'priority': priority,
      'reminder': reminder,
      'created': DateTime.now().millisecondsSinceEpoch,
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<List<Map<String, dynamic>>> getItems({String? tagFilter}) async {
  if (tagFilter != null && tagFilter.isNotEmpty) {
    return await db.query(
        'items',
        where: 'tags LIKE ?',
        whereArgs: ['%$tagFilter%'],
        orderBy: 'priority DESC, created DESC'
    );
  }
  return await db.query('items', orderBy: 'priority DESC, created DESC');
}

Future<List<Map<String, dynamic>>> getItemsWithReminders() async {
  final now = DateTime.now().millisecondsSinceEpoch;
  return await db.query(
      'items',
      where: 'reminder IS NOT NULL AND reminder > ?',
      whereArgs: [now],
      orderBy: 'reminder ASC'
  );
}

Future<void> updateItem(int id, String title, String content, {String? tags, int? priority, int? reminder}) async {
  final Map<String, dynamic> updates = {
    'title': title,
    'content': content,
  };

  if (tags != null) updates['tags'] = tags;
  if (priority != null) updates['priority'] = priority;
  if (reminder != null) updates['reminder'] = reminder;

  await db.update(
    'items',
    updates,
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

void main() async {
  // Initialize FFI for Linux and other desktop platforms
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  WidgetsFlutterBinding.ensureInitialized();
  await initDatabases();
  runApp(memorizerApp());
}

// Main app widget as a function
Widget memorizerApp() => MaterialApp(
  title: 'Memorizer',
  theme: appTheme,
  home: homePage(),
);

// Home page as a function
Widget homePage() => Builder(
    builder: (context) {
      globalContext = context;

      return Scaffold(
        appBar: buildAppBar('Memorizer'),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: getItems(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

            final items = snapshot.data!;

            return ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final hasPriority = item['priority'] > 0;
                final hasReminder = item['reminder'] != null;

                return ListTile(
                  title: Text(item['title']),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item['content']),
                      if (item['tags'].toString().isNotEmpty)
                        Text('Tags: ${item['tags']}',
                            style: TextStyle(fontSize: 12, color: Colors.blue)),
                    ],
                  ),
                  leading: hasPriority ? Icon(Icons.star, color: Colors.amber) : null,
                  trailing: hasReminder ? Icon(Icons.alarm) : null,
                  onTap: () {
                    // Item tap functionality
                  },
                );
              },
            );
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            // Add new item functionality
          },
          child: const Icon(Icons.add),
        ),
      );
    }
);