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
  try {
    // Get sort order from settings
    final newestFirst = await getSetting("Newest first") ?? defSettings["Newest first"];
    myPrint('Newest first setting: $newestFirst');

    // Determine sort order based on setting
    final sortOrder = newestFirst == "true" ? "DESC" : "ASC";
    String orderByClause = 'priority DESC, created ${sortOrder}';
    myPrint('Order by clause: $orderByClause');

    List<Map<String, dynamic>> result;
    if (tagFilter != null && tagFilter.isNotEmpty) {
      myPrint('Filtering by tag: $tagFilter');
      result = await db.query(
          'items',
          where: 'tags LIKE ?',
          whereArgs: ['%$tagFilter%'],
          orderBy: orderByClause
      );
    } else {
      result = await db.query('items', orderBy: orderByClause);
    }

    myPrint('Retrieved items count: ${result.length}');
    if (result.isNotEmpty) {
      myPrint('First item: ${result.first}');
    }

    return result;
  } catch (e) {
    myPrint('Error loading items: $e');
    return []; // Return empty list instead of throwing error
  }
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

void setState(VoidCallback fn) {
  fn();
  globalContext = globalContext;
}

// final itemsKey = GlobalKey<State>();

// Home page as a function
// Home page as a function
Widget homePage() => Builder(
    builder: (context) {
      globalContext = context;
      final scaffoldKey = GlobalKey<ScaffoldState>();
      final itemsKey = GlobalKey();

      return Scaffold(
        key: scaffoldKey,
        appBar: AppBar(
          backgroundColor: clUpBar,
          foregroundColor: clText,
          title: Text('Memorizer'),
          actions: [
            IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () {
                scaffoldKey.currentState?.openDrawer();
              },
            ),
          ],
        ),
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
              ListTile(
                title: Text('About'),
                onTap: () {
                  Navigator.pop(context);
                  _showAbout();
                },
                onLongPress: () {
                  Navigator.pop(context);
                  // Здесь будет показ справки
                  okInfo(lw('Help information will be shown here'));
                },
              ),
            ],
          ),
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          key: itemsKey,
          future: getItems(),
          builder: (context, itemsSnapshot) {
            if (!itemsSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final items = itemsSnapshot.data!;

            if (items.isEmpty) {
              return Center(
                child: Text(
                  lw('No items yet. Press + to add.'),
                  style: TextStyle(
                    color: clText,
                    fontSize: fsMedium,
                  ),
                ),
              );
            }

            return ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final hasPriority = item['priority'] > 0;
                final hasReminder = item['reminder'] != null;

                return ListTile(
                  title: Text(
                    item['title'],
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: clText,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['content'],
                        style: TextStyle(color: clText),
                      ),
                      if (item['tags'].toString().isNotEmpty)
                        Text(
                          'Tags: ${item['tags']}',
                          style: TextStyle(
                            fontSize: fsNormal,
                            color: clUpBar,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                  tileColor: clFill,
                  selectedTileColor: clSel,
                  leading: hasPriority
                      ? Icon(Icons.star, color: Colors.amber)
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasReminder)
                        Icon(Icons.alarm, color: clText),
                      IconButton(
                        icon: Icon(Icons.edit, color: clText),
                        onPressed: () {
                          // Edit item functionality
                          navigateToScreen(editItemPage(item));
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.delete, color: clText),
                        onPressed: () {
                          // Delete item confirmation
                          showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                backgroundColor: clFill,
                                title: Text(
                                  lw('Delete Item'),
                                  style: TextStyle(color: clText),
                                ),
                                content: Text(
                                  lw('Are you sure you want to delete this item?'),
                                  style: TextStyle(color: clText),
                                ),
                                actions: [
                                  TextButton(
                                    child: Text(
                                      lw('Cancel'),
                                      style: TextStyle(color: clUpBar),
                                    ),
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                    },
                                  ),
                                  TextButton(
                                    child: Text(
                                      lw('Delete'),
                                      style: TextStyle(color: Colors.red),
                                    ),
                                    onPressed: () async {
                                      await deleteItem(item['id']);
                                      Navigator.of(context).pop();
                                      // Refresh the list
                                      setState(() {});
                                    },
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                  onTap: () {
                    // Item tap functionality - view details
                    navigateToScreen(editItemPage(item));
                  },
                  onLongPress: () {
                    // Toggle priority
                    updateItem(
                      item['id'],
                      item['title'],
                      item['content'],
                      priority: item['priority'] > 0 ? 0 : 1,
                    ).then((_) {
                      // Refresh the list
                      setState(() {});
                    });
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
            navigateToScreen(editItemPage(null));
          },
          child: const Icon(Icons.add),
        ),
      );
    }
);


void _showAbout() {
  String txt = lw('Memorizer');
  txt += '\n\n';
  txt += '${lw('Version')}: $progVersion\n\n';
  txt += '(c): $progAuthor 2025\n';
  txt += '\n';
  txt += lw('Long press to HELP');
  okInfo(txt);
}

Widget editItemPage(Map<String, dynamic>? item) => Builder(
    builder: (context) {
      final isEditing = item != null;
      final titleController = TextEditingController(
        text: isEditing ? item['title'] : '',
      );
      final contentController = TextEditingController(
        text: isEditing ? item['content'] : '',
      );
      final tagsController = TextEditingController(
        text: isEditing ? item['tags'] : '',
      );

      return Scaffold(
        appBar: AppBar(
          backgroundColor: clUpBar,
          foregroundColor: clText,
          title: Text(
            isEditing ? lw('Edit Item') : lw('New Item'),
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.save),
              onPressed: () async {
                if (titleController.text.trim().isEmpty) {
                  okInfo(lw('Title cannot be empty'));
                  return;
                }

                if (isEditing) {
                  await updateItem(
                    item['id'],
                    titleController.text.trim(),
                    contentController.text.trim(),
                    tags: tagsController.text.trim(),
                  );
                } else {
                  await insertItem(
                    titleController.text.trim(),
                    contentController.text.trim(),
                    tags: tagsController.text.trim(),
                  );
                }

                Navigator.pop(context);
              },
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextField(
                controller: titleController,
                style: TextStyle(color: clText),
                decoration: InputDecoration(
                  labelText: lw('Title'),
                  labelStyle: TextStyle(color: clText),
                  fillColor: clFill,
                  filled: true,
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: contentController,
                style: TextStyle(color: clText),
                decoration: InputDecoration(
                  labelText: lw('Content'),
                  labelStyle: TextStyle(color: clText),
                  fillColor: clFill,
                  filled: true,
                  border: OutlineInputBorder(),
                ),
                maxLines: 5,
              ),
              SizedBox(height: 16),
              TextField(
                controller: tagsController,
                style: TextStyle(color: clText),
                decoration: InputDecoration(
                  labelText: lw('Tags (comma separated)'),
                  labelStyle: TextStyle(color: clText),
                  fillColor: clFill,
                  filled: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      );
    }
);
