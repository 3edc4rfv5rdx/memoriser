// main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:intl/intl.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:io' show Platform;
import 'globals.dart';
import 'settings.dart';
import 'additem.dart';
import 'tagscloud.dart';
import 'filters.dart';


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
    version: 2,
    onCreate: (settDb, version) {
      return settDb.execute(
        'CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT)',
      );
    },
  );
}

// Функция для получения текста состояния фильтра
Future<String> getFilterStatusText() async {
  bool hasTagFilter = xvTagFilter.isNotEmpty;

  // Получаем значение настройки Last items
  final lastItemsStr = await getSetting("Last items") ?? defSettings["Last items"];
  final lastItems = int.tryParse(lastItemsStr) ?? 0;
  bool hasLastItems = lastItems > 0;

  if (xvFilter.isNotEmpty && hasTagFilter) {
    return '(FT) ';
  } else if (hasTagFilter) {
    return '(T) ';
  } else if (xvFilter.isNotEmpty) {
    return '(F) ';
  } else if (hasLastItems) {
    return '($lastItems) ';
  } else {
    return '(All) ';
  }
}

Future<List<Map<String, dynamic>>> getItems() async {
  try {
    // Get sort order from settings
    final newestFirst = await getSetting("Newest first") ?? defSettings["Newest first"];
    myPrint('Newest first setting: $newestFirst');

    // Get last items limit from settings
    final lastItemsStr = await getSetting("Last items") ?? defSettings["Last items"];
    final lastItems = int.tryParse(lastItemsStr) ?? 0;
    myPrint('Last items setting: $lastItems');

    // Determine sort order based on setting
    final sortOrder = newestFirst == "true" ? "DESC" : "ASC";
    String orderByClause = 'priority DESC, created ${sortOrder}';
    myPrint('Order by clause: $orderByClause');

    // Начальные значения для WHERE и параметров
    List<String> whereConditions = [];
    List<dynamic> whereArgs = [];

    // Обработка тег-фильтра
    if (xvTagFilter.isNotEmpty) {
      myPrint('Tag filter is active: $xvTagFilter');

      // Разбиваем строку тегов на отдельные теги
      List<String> tagFilters = xvTagFilter.split(',').map((tag) => tag.trim()).toList();

      for (String tag in tagFilters) {
        whereConditions.add('tags LIKE ?');
        whereArgs.add('%$tag%');
      }
    }

    // Обработка основного фильтра
    if (xvFilter.isNotEmpty) {
      myPrint('Main filter is active: $xvFilter');

      // Разбираем строку фильтра
      List<String> filterParts = xvFilter.split('|');

      for (String part in filterParts) {
        List<String> keyValue = part.split(':');
        if (keyValue.length != 2) continue;

        String key = keyValue[0];
        String value = keyValue[1];

        switch (key) {
          case 'dateFrom':
            if (value.isNotEmpty) {
              try {
                final date = DateFormat('yyyy-MM-dd').parse(value);
                // Начало дня в миллисекундах
                final timestamp = DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;
                whereConditions.add('date >= ?');
                whereArgs.add(timestamp);
              } catch (e) {
                myPrint('Error parsing dateFrom: $e');
              }
            }
            break;

          case 'dateTo':
            if (value.isNotEmpty) {
              try {
                final date = DateFormat('yyyy-MM-dd').parse(value);
                // Конец дня в миллисекундах
                final timestamp = DateTime(date.year, date.month, date.day, 23, 59, 59).millisecondsSinceEpoch;
                whereConditions.add('date <= ?');
                whereArgs.add(timestamp);
              } catch (e) {
                myPrint('Error parsing dateTo: $e');
              }
            }
            break;

          case 'priority':
            if (value.isNotEmpty) {
              final priority = int.tryParse(value);
              if (priority != null) {
                whereConditions.add('priority = ?');
                whereArgs.add(priority);
              }
            }
            break;

          case 'hasReminder':
            if (value.isNotEmpty) {
              final hasReminder = value == 'true' ? 1 : 0;
              whereConditions.add('remind = ?');
              whereArgs.add(hasReminder);
            }
            break;

          case 'tags':
            if (value.isNotEmpty) {
              // Разбиваем строку тегов на отдельные теги
              List<String> tagFilters = value.split(',').map((tag) => tag.trim()).toList();

              for (String tag in tagFilters) {
                whereConditions.add('tags LIKE ?');
                whereArgs.add('%$tag%');
              }
            }
            break;
        }
      }
    }

    // Собираем окончательный WHERE и параметры
    String? whereClause;
    if (whereConditions.isNotEmpty) {
      whereClause = whereConditions.join(' AND ');
      myPrint('WHERE clause: $whereClause');
      myPrint('WHERE args: $whereArgs');
    }

    // Выполняем запрос с учетом фильтров
    List<Map<String, dynamic>> result;
    if (whereClause != null) {
      result = await mainDb.query(
          'items',
          where: whereClause,
          whereArgs: whereArgs,
          orderBy: orderByClause
      );
    } else {
      result = await mainDb.query('items', orderBy: orderByClause);
    }

    // Применяем ограничение на количество записей из настройки "Last items"
    if (lastItems > 0 && result.length > lastItems) {
      myPrint('Limiting results to last $lastItems items');
      result = result.sublist(0, lastItems);
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
  WidgetsFlutterBinding.ensureInitialized();
  // Используем FFI только на десктопных платформах
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  await initDatabases();
  // Initialize default settings
  await initDefaultSettings();
  final themeName = await getSetting("Color theme") ?? defSettings["Color theme"];
  setThemeColors(themeName);
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
  // Add localization delegates
  localizationsDelegates: [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  // Add supported locales with proper locale codes
  supportedLocales: langNames.keys.map((key) =>
      Locale(getLocaleCode(key))
  ).toList(),
  // Set the app locale with proper locale code
  locale: Locale(getLocaleCode(currentLocale)),
  onGenerateRoute: (settings) {
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
  String _filterStatus = '(All) ';

  @override
  void initState() {
    super.initState();
    _refreshItems();
    _updateFilterStatus(); // Обновление статуса фильтра при запуске
  }

  void _clearAllFilters() {
    setState(() {
      xvTagFilter = '';
      xvFilter = '';
    });
    _refreshItems();
    okInfoBarBlue(lw('All filters cleared'));
  }

  Future<void> _updateFilterStatus() async {
    final status = await getFilterStatusText();
    setState(() {
      _filterStatus = status;
    });
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
      _updateFilterStatus(); // Обновляем статус фильтра после обновления элементов
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
        title: GestureDetector(
          onLongPress: () => showHelp(20), // ID 20 для заголовка
          child: Text(lw('Memorizer')),
        ),
        leading: GestureDetector(
          onLongPress: () => showHelp(21), // ID 21 для кнопки закрытия
          child: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () async {
              // Vacuum the databases before closing
              await vacuumDatabases();
              // Close the app when X button is pressed from main screen
              Navigator.of(context).canPop()
                  ? Navigator.of(context).pop() : SystemNavigator.pop();
            },
          ),
        ),
        actions: [
          // Индикатор состояния фильтра
          GestureDetector(
            onLongPress: () => showHelp(22), // ID 22 для индикатора фильтра
            child: Center(
              child: Text(
                _filterStatus,
                style: TextStyle(
                  color: clText,
                  fontSize: fsXLarge,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          // Кнопка фильтра
          GestureDetector(
            onLongPress: () => showHelp(23), // ID 23 для кнопки фильтра
            child: IconButton(
              icon: Icon(Icons.filter_alt),
              tooltip: lw('Filters'),
              onPressed: () {
                Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FiltersScreen(),
                  ),
                ).then((needsRefresh) {
                  if (needsRefresh == true) {
                    _refreshItems();
                  }
                });
              },
            ),
          ),
          // Кнопка тег-фильтра
          GestureDetector(
            onLongPress: () => showHelp(24), // ID 24 для кнопки тег-фильтра
            child: IconButton(
              icon: Icon(Icons.filter_list),
              tooltip: lw('Tag filter'),
              onPressed: () {
                Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TagsCloudScreen(),
                  ),
                ).then((needsRefresh) {
                  if (needsRefresh == true) {
                    _refreshItems();
                  }
                });
              },
            ),
          ),
          // Меню
          GestureDetector(
            onLongPress: () => showHelp(25), // ID 25 для кнопки меню
            child: PopupMenuButton<String>(
              icon: Icon(Icons.menu),
              color: clMenu,
              offset: Offset(0, 30),
              onSelected: (String result) {
                if (result == 'settings') {
                  Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                          builder: (context) => buildSettingsScreen()
                      )
                  ).then((needsRefresh) {
                    _refreshItems();
                  });
                } else if (result == 'about') {
                  _showAbout();
                } else if (result == 'clear_filters') {
                  _clearAllFilters();
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'clear_filters',
                  child: GestureDetector(
                    onLongPress: () => showHelp(26), // ID 26 для пункта меню очистки фильтров
                    child: Text(
                      lw('Clear all filters'),
                      style: TextStyle(color: clText),
                    ),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'settings',
                  child: GestureDetector(
                    onLongPress: () => showHelp(27), // ID 27 для пункта меню настроек
                    child: Text(
                      lw('Settings'),
                      style: TextStyle(color: clText),
                    ),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'about',
                  child: GestureDetector(
                    onLongPress: () => showHelp(28), // ID 28 для пункта меню "О программе"
                    child: Text(
                      lw('About'),
                      style: TextStyle(color: clText),
                    ),
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
                        priorityValue > 3 ? 3 : priorityValue,
                            (i) => Icon(Icons.star, color: clUpBar, size: 34)
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
      floatingActionButton: GestureDetector(
        onLongPress: () => showHelp(29), // ID 29 для кнопки добавления
        child: FloatingActionButton(
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