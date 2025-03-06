// main.dart
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'globals.dart';

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
  // Get sort order from settings
  final newestFirst = await getSetting("Newest first") ?? defSettings["Newest first"];

  // Determine sort order based on setting
  final sortOrder = newestFirst == "true" ? "DESC" : "ASC";
  String orderByClause = 'priority DESC, created ${sortOrder}';

  if (tagFilter != null && tagFilter.isNotEmpty) {
    return await db.query(
        'items',
        where: 'tags LIKE ?',
        whereArgs: ['%$tagFilter%'],
        orderBy: orderByClause
    );
  }
  return await db.query('items', orderBy: orderByClause);
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
  theme: getAppTheme(),
  home: homePage(),
);

// Settings screen for theme selection
Widget settingsPage() => Builder(
    builder: (context) {
      return Scaffold(
        appBar: buildAppBar('Settings'),
        body: FutureBuilder<String?>(
          future: getSetting("Color theme"),
          builder: (context, snapshot) {
            final currentTheme = snapshot.hasData
                ? snapshot.data!
                : defSettings["Color theme"];

            return ListView(
              children: [
                ListTile(
                  title: Text('Color Theme'),
                  subtitle: Text(currentTheme),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          backgroundColor: clFill,
                          title: Text('Select Theme'),
                          content: Container(
                            width: double.minPositive,
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: appTHEMES.length,
                              itemBuilder: (BuildContext context, int index) {
                                return ListTile(
                                  title: Text(appTHEMES[index]),
                                  selected: appTHEMES[index] == currentTheme,
                                  selectedTileColor: clSel,
                                  onTap: () async {
                                    // Save the theme name, not the index
                                    await saveSetting("Color theme", appTHEMES[index]);
                                    Navigator.of(context).pop();

                                    // Rebuild the app to apply new theme
                                    Navigator.of(context).pushReplacement(
                                      MaterialPageRoute(builder: (context) => memorizerApp()),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
                // Other settings can be added here
              ],
            );
          },
        ),
      );
    }
);

// Home page as a function
Widget homePage() => Builder(
    builder: (context) {
      globalContext = context;

      return Scaffold(
        appBar: buildAppBar('Memorizer'),
        drawer: Drawer(
          backgroundColor: clMenu,
          child: ListView(
            children: [
              DrawerHeader(
                decoration: BoxDecoration(
                  color: clUpBar,
                ),
                child: Text(
                  'Memorizer',
                  style: TextStyle(
                    color: clText,
                    fontSize: fsHeader,
                  ),
                ),
              ),
              ListTile(
                title: Text('Settings'),
                onTap: () {
                  Navigator.pop(context);
                  navigateToScreen(settingsPage());
                },
              ),
            ],
          ),
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: getItems(),
          builder: (context, itemsSnapshot) {
            if (!itemsSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final items = itemsSnapshot.data!;

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
                            style: TextStyle(fontSize: fsNormal, color: clUpBar)),
                    ],
                  ),
                  tileColor: clFill,
                  selectedTileColor: clSel,
                  textColor: clText,
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
          backgroundColor: clUpBar,
          foregroundColor: clText,
          onPressed: () {
            // Add new item functionality
          },
          child: const Icon(Icons.add),
        ),
      );
    }
);
