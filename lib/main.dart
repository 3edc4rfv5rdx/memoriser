// main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:intl/intl.dart';
import 'globals.dart';
import 'settings.dart';
import 'additem.dart';

// Initialize databases
Future<void> initDatabases() async {
  final databasesPath = await getDatabasesPath();

  // Initialize main database with all columns in the create statement
  mainDb = await openDatabase(
    join(databasesPath, mainDbFile),
    version: 2, // Using version 2 for the updated schema
    onCreate: (mainDb, version) {
      return mainDb.execute('''
        CREATE TABLE IF NOT EXISTS items(
          id INTEGER PRIMARY KEY, 
          title TEXT, 
          content TEXT, 
          tags TEXT, 
          priority INTEGER, 
          date INTEGER, 
          remind INTEGER, 
          created INTEGER
        )
      ''');
    },
  );

  // Initialize settings database
  settDb = await openDatabase(
    join(databasesPath, settDbFile),
    version: 1,
    onCreate: (mainDb, version) {
      return mainDb.execute(
        'CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT)',
      );
    },
  );

  // Initialize default settings
  await initDefaultSettings();

  // Initialize theme colors
  final themeName = await getSetting("Color theme") ?? defSettings["Color theme"];
  setThemeColors(themeName);
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
      result = await mainDb.query(
          'items',
          where: 'tags LIKE ?',
          whereArgs: ['%$tagFilter%'],
          orderBy: orderByClause
      );
    } else {
      result = await mainDb.query('items', orderBy: orderByClause);
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
  return await mainDb.query(
      'items',
      where: 'remind = 1 AND date > ?',
      whereArgs: [now],
      orderBy: 'date ASC'
  );
}

void main() async {
  // Initialize FFI for Linux and other desktop platforms
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  WidgetsFlutterBinding.ensureInitialized();
  await initDatabases();
  // Загрузка локализации
  final languageSetting = await getSetting("Language") ?? defSettings["Language"];
  await readLocale(languageSetting.toLowerCase());

  runApp(memorizerApp());
}

Widget memorizerApp() => MaterialApp(
  title: lw('Memorizer'),
  theme: getAppTheme(),
  home: HomePage(),
  debugShowCheckedModeBanner: false,
  scaffoldMessengerKey: scaffoldMessengerKey,
  navigatorKey: navigatorKey,
  navigatorObservers: [routeObserver],
  onGenerateRoute: (settings) {
    // Обеспечиваем доступность ключей для всех маршрутов
    myPrint("Generating route: ${settings.name}");
    return null;
  },
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
      position: RelativeRect.fromLTRB(100, 100, 100, 100),
      color: clMenu, // Set the background color to clMenu to match the theme
      items: <PopupMenuEntry>[
        PopupMenuItem(
          child: ListTile(
            leading: Icon(Icons.edit, color: clText),
            title: Text(lw('Edit'), style: TextStyle(color: clText)),
            onTap: () {
              Navigator.pop(context); // Close the menu
              // Navigate to edit page
              Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                      builder: (context) => EditItemPage(
                        item: item,
                      )
                  )
              ).then((updated) {
                if (updated == true) {
                  _refreshItems();
                }
              });
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
                title: lw('Delete Item'),
                content: lw('Are you sure you want to delete this item?'),
                actions: [
                  {
                    'label': lw('Cancel'),
                    'value': false,
                    'isDestructive': false,
                  },
                  {
                    'label': lw('Delete'),
                    'value': true,
                    'isDestructive': true,
                    'onPressed': () async {
                      await mainDb.delete(
                        'items',
                        where: 'id = ?',
                        whereArgs: [item['id']],
                      );
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
        title: Text(lw('Memorizer')),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () async {
            // Vacuum the databases before closing
            await vacuumDatabases();
            // Close the app when X button is pressed from main screen
            Navigator.of(context).canPop()
                ? Navigator.of(context).pop()
                : SystemNavigator.pop();
          },
        ),
        actions: [
          // Using a Container with alignment to position the menu button at the bottom
          Container(
            alignment: Alignment.bottomRight,
            margin: EdgeInsets.only(bottom: 4),  // Small margin to avoid being too close to the edge
            child: PopupMenuButton<String>(
              icon: Icon(Icons.menu),
              color: clMenu,
              // This controls where the menu appears relative to the button
              offset: Offset(0, 30),  // Offset to position menu below the AppBar
              onSelected: (String result) {
                if (result == 'settings') {
                  // Показываем экран настроек и обрабатываем результат после возврата
                  Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                          builder: (context) => buildSettingsScreen()
                      )
                  ).then((needsRefresh) {
                    // Обновляем текущий экран в любом случае
                    _refreshItems();

                    // Если вернулось true, можем выполнить дополнительные действия
                    if (needsRefresh == true) {
                      // При необходимости можно добавить дополнительные действия
                    }
                  });
                } else if (result == 'about') {
                  _showAbout();
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
              ],
            ),
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
          final priorityValue = item['priority'] ?? 0;
          final hasDate = item['date'] != null;
          final isReminder = item['remind'] == 1;

          // Format date for display if it exists
          String? formattedDate;
          if (hasDate) {
            final eventDate = DateTime.fromMillisecondsSinceEpoch(item['date']);
            formattedDate = DateFormat('yyyy-MM-dd').format(eventDate);
          }

          return ListTile(
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    item['title'],
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: clText,
                    ),
                  ),
                ),
                // Display priority as stars
                if (priorityValue > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                        priorityValue > 5 ? 5 : priorityValue,
                            (i) => Icon(Icons.star, color: clUpBar, size: 16)
                    ),
                  ),
              ],
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
                      color: clText,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                // Add date information if available
                if (hasDate)
                  Row(
                    children: [
                      Icon(
                          isReminder ? Icons.alarm : Icons.event,
                          color: isReminder ? Colors.red : clText,
                          size: 14
                      ),
                      SizedBox(width: 4),
                      Text(
                        formattedDate!,
                        style: TextStyle(
                          fontSize: fsNormal,
                          color: isReminder ? Colors.red : clText,
                          fontWeight: isReminder ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            tileColor: _selectedItemId == item['id'] ? clSel : clFill,
            leading: priorityValue > 0
                ? Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: clUpBar,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                priorityValue.toString(),
                style: TextStyle(
                  color: clText,
                  fontWeight: FontWeight.bold,
                  fontSize: fsSmall,
                ),
              ),
            )
                : null,
            trailing: isReminder
                ? Icon(Icons.notifications_active, color: Colors.red)
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
          final result = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
                builder: (context) => EditItemPage()
            ),
          );

          if (result == true) {
            _refreshItems();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

void _showAbout() {
  String txt = 'Memorizer';
  txt += '\n\n';
  txt += lw('Version') + ': $progVersion\n\n';
  txt += '(c): $progAuthor 2025\n';
  txt += '\n';
  txt += lw('Long press to HELP');
  okInfo(txt);
}