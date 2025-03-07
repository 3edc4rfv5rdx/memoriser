// main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'globals.dart';
import 'settings.dart';
import 'additem.dart';

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
  myPrint("Item inserted: $title");
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
  myPrint("Item updated: $id - $title");
}

Future<void> deleteItem(int id) async {
  await db.delete(
    'items',
    where: 'id = ?',
    whereArgs: [id],
  );
  myPrint("Item deleted: $id");
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
  home: HomePage(),
  debugShowCheckedModeBanner: false,
);

// StatefulWidget implementation for HomePage
class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  int? _selectedItemId; // Track the selected item

  @override
  void initState() {
    super.initState();
    _refreshItems();
  }

  Future<void> _refreshItems() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final items = await getItems();
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (e) {
      myPrint('Error loading items: $e');
      setState(() {
        _items = [];
        _isLoading = false;
      });
    }
  }

  void _showContextMenu(BuildContext context, Map<String, dynamic> item) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(100, 100, 100, 100),  // This will be positioned near the tap
      items: <PopupMenuEntry>[
        PopupMenuItem(
          child: ListTile(
            leading: Icon(Icons.edit, color: clText),
            title: Text(lw('Edit'), style: TextStyle(color: clText)),
            onTap: () {
              Navigator.pop(context); // Close the menu
              // Navigate to edit page
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => EditItemPage(
                        item: item,
                        onSave: (id, title, content, tags) async {
                          await updateItem(
                            id,
                            title,
                            content,
                            tags: tags,
                          );
                          _refreshItems();
                        },
                      )
                  )
              );
            },
          ),
        ),
        PopupMenuItem(
          child: ListTile(
            leading: Icon(Icons.delete, color: Colors.red),
            title: Text(lw('Delete'), style: TextStyle(color: clText)),
            onTap: () {
              Navigator.pop(context); // Close the menu

              // Use the showCustomDialog function for delete confirmation
              showCustomDialog(
                title: 'Delete Item',
                content: 'Are you sure you want to delete this item?',
                actions: [
                  {
                    'label': 'Cancel',
                    'value': false,
                    'isDestructive': false,
                  },
                  {
                    'label': 'Delete',
                    'value': true,
                    'isDestructive': true,
                    'onPressed': () async {
                      await deleteItem(item['id']);
                      _refreshItems();
                    },
                  },
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    globalContext = context;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: clUpBar,
        foregroundColor: clText,
        title: Text('Memorizer'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            // Close the app when X button is pressed from main screen
            Navigator.of(context).canPop()
                ? Navigator.of(context).pop()
                : SystemNavigator.pop();
          },
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.menu),
            color: clMenu,
            onSelected: (String result) {
              if (result == 'settings') {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => SettingsPage(
                          rebuildApp: () {
                            // Function to rebuild the app
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (context) => memorizerApp()),
                            );
                          },
                        )
                    )
                ).then((_) => _refreshItems());
              } else if (result == 'about') {
                _showAbout();
              } else if (result == 'help') {
                okInfo(lw('Help information will be shown here'));
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'settings',
                child: Text(
                  lw('Settings'),
                  style: TextStyle(color: clText),
                ),
              ),
              PopupMenuItem<String>(
                value: 'about',
                child: Text(
                  lw('About'),
                  style: TextStyle(color: clText),
                ),
              ),
              PopupMenuItem<String>(
                value: 'help',
                child: Text(
                  lw('Help'),
                  style: TextStyle(color: clText),
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? Center(
        child: Text(
          lw('No items yet. Press + to add.'),
          style: TextStyle(
            color: clText,
            fontSize: fsMedium,
          ),
        ),
      )
          : ListView.builder(
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
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
                      color: clText,  // Changed from clUpBar to clText
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
            tileColor: _selectedItemId == item['id'] ? clSel : clFill,
            leading: hasPriority
                ? Icon(Icons.star, color: Colors.amber)
                : null,
            trailing: hasReminder
                ? Icon(Icons.alarm, color: clText)
                : null,
            onTap: () {
              // Just select the item and highlight it
              setState(() {
                _selectedItemId = item['id'];
              });
            },
            onLongPress: () {
              // Show context menu with Edit and Delete options
              _showContextMenu(context, item);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: clUpBar,
        foregroundColor: clText,
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => EditItemPage(
                  onSave: (id, title, content, tags) async {
                    await insertItem(
                      title,
                      content,
                      tags: tags,
                    );
                  },
                )
            ),
          );
          // Always refresh after returning
          _refreshItems();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

void _showAbout() {
  String txt = lw('Memorizer');
  txt += '\n\n';
  txt += '${lw('Version')}: $progVersion\n\n';
  txt += '(c): $progAuthor 2025\n';
  txt += '\n';
  txt += lw('Long press to HELP');
  okInfo(txt);
}
