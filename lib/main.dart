// main.dart
import 'dart:async'; // Для Timer
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'additem.dart';
import 'filters.dart';
import 'globals.dart';
import 'reminders.dart';
import 'settings.dart';
import 'tagscloud.dart';

// Initialize databases
Future<void> initDatabases() async {
  final databasesPath = await getDatabasesPath();

  mainDb = await openDatabase(
    join(databasesPath, mainDbFile),
    version: 6, // Увеличиваем версию с 5 до 6 для добавления поля time
    onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS items(
          id INTEGER PRIMARY KEY, 
          title TEXT DEFAULT NULL, 
          content TEXT DEFAULT NULL, 
          tags TEXT DEFAULT NULL, 
          priority INTEGER DEFAULT 0, 
          date INTEGER DEFAULT NULL, 
          time INTEGER DEFAULT NULL,
          remind INTEGER DEFAULT 0, 
          created INTEGER DEFAULT 0,
          remove INTEGER DEFAULT 0,
          hidden INTEGER DEFAULT 0,
          photo TEXT DEFAULT NULL
        )
      ''');
    },
    onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 6) {
        // Миграция с пересозданием таблицы для вставки поля time после date
        await db.execute('''
          CREATE TABLE items_new(
            id INTEGER PRIMARY KEY, 
            title TEXT DEFAULT NULL, 
            content TEXT DEFAULT NULL, 
            tags TEXT DEFAULT NULL, 
            priority INTEGER DEFAULT 0, 
            date INTEGER DEFAULT NULL, 
            time INTEGER DEFAULT NULL,
            remind INTEGER DEFAULT 0, 
            created INTEGER DEFAULT 0,
            remove INTEGER DEFAULT 0,
            hidden INTEGER DEFAULT 0,
            photo TEXT DEFAULT NULL
          )
        ''');

        // Перенос данных из старой таблицы в новую (time будет NULL)
        await db.execute('''
          INSERT INTO items_new(id, title, content, tags, priority, date, 
                               remind, created, remove, hidden, photo)
          SELECT id, title, content, tags, priority, date, 
                 remind, created, remove, hidden, photo
          FROM items
        ''');

        // Удаляем старую таблицу и переименовываем новую
        await db.execute('DROP TABLE items');
        await db.execute('ALTER TABLE items_new RENAME TO items');

        myPrint("Database upgraded to version 6: Added 'time' field after 'date'");
      }
    },
  );

  settDb = await openDatabase(
    join(databasesPath, settDbFile),
    version: 2,
    onCreate: (db, version) {
      return db.execute(
        'CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT)',
      );
    },
  );
}

// Функция для получения текста состояния фильтра
Future<String> getFilterStatusText() async {
  bool hasTagFilter = xvTagFilter.isNotEmpty;

  // Получаем значение настройки Last items
  final lastItemsStr =
      await getSetting("Last items") ?? defSettings["Last items"];
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

// Оптимизированная функция getItems() с использованием SQL для сортировки и LIMIT
// Исправленная функция getItems() с корректным SQL-синтаксисом

Future<List<Map<String, dynamic>>> getItems() async {
  try {
    // Get sort order from settings
    final newestFirst = await getSetting("Newest first") ?? defSettings["Newest first"];
    myPrint('Newest first setting: $newestFirst');

    // Get last items limit from settings
    final lastItemsStr = await getSetting("Last items") ?? defSettings["Last items"];
    final lastItems = int.tryParse(lastItemsStr) ?? 0;
    myPrint('Last items setting: $lastItems');

    // Определяем сегодняшнюю дату в формате YYYYMMDD
    final todayDate = dateTimeToYYYYMMDD(DateTime.now());
    myPrint('Today date: $todayDate');

    // Начальные значения для WHERE
    List<String> whereConditions = [];
    List<dynamic> whereArgs = [];

    // Добавляем условие для фильтрации по hidden
    if (xvHiddenMode) {
      whereConditions.add('hidden = 1');
    } else {
      whereConditions.add('(hidden = 0 OR hidden IS NULL)');
    }

    // Обработка тег-фильтра
    if (xvTagFilter.isNotEmpty) {
      myPrint('Tag filter is active: $xvTagFilter');

      // Разбиваем строку тегов на отдельные теги
      List<String> tagFilters = xvTagFilter.split(',').map((tag) => tag.trim()).toList();

      if (xvHiddenMode) {
        // В скрытом режиме обфусцируем теги перед поиском
        for (String tag in tagFilters) {
          // Обфусцируем тег для поиска в базе данных
          String obfuscatedTag = obfuscateText(tag);
          whereConditions.add('tags LIKE ?');
          whereArgs.add('%$obfuscatedTag%');
        }
      } else {
        // В обычном режиме ищем как есть
        for (String tag in tagFilters) {
          whereConditions.add('tags LIKE ?');
          whereArgs.add('%$tag%');
        }
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
                final date = DateFormat(ymdDateFormat).parse(value);
                final dateValue = dateTimeToYYYYMMDD(date);
                whereConditions.add('(date IS NOT NULL AND date >= ?)');
                whereArgs.add(dateValue);
              } catch (e) {
                myPrint('Error parsing dateFrom: $e');
              }
            }
            break;

          case 'dateTo':
            if (value.isNotEmpty) {
              try {
                final date = DateFormat(ymdDateFormat).parse(value);
                final dateValue = dateTimeToYYYYMMDD(date);
                whereConditions.add('(date IS NOT NULL AND date <= ?)');
                whereArgs.add(dateValue);
              } catch (e) {
                myPrint('Error parsing dateTo: $e');
              }
            }
            break;

          case 'priority':
            if (value.isNotEmpty) {
              try {
                final priorityValue = int.parse(value);
                whereConditions.add('priority = ?');
                whereArgs.add(priorityValue);
              } catch (e) {
                myPrint('Error parsing priority: $e');
              }
            }
            break;

          case 'hasReminder':
            if (value.isNotEmpty) {
              final hasReminder = value.toLowerCase() == 'true' ? 1 : 0;
              whereConditions.add('remind = ?');
              whereArgs.add(hasReminder);
            }
            break;

          case 'tags':
            if (value.isNotEmpty) {
              // Split by comma to handle multiple tags in filter
              List<String> tagFilters = value.split(',').map((tag) => tag.trim()).toList();

              // For each tag, add a LIKE condition
              List<String> tagConditions = [];
              for (String tag in tagFilters) {
                if (xvHiddenMode) {
                  // In hidden mode, obfuscate tags before searching
                  String obfuscatedTag = obfuscateText(tag);
                  tagConditions.add('tags LIKE ?');
                  whereArgs.add('%$obfuscatedTag%');
                } else {
                  // In normal mode, search as-is
                  tagConditions.add('tags LIKE ?');
                  whereArgs.add('%$tag%');
                }
              }

              // Use OR between tag conditions if there are multiple tags
              if (tagConditions.isNotEmpty) {
                whereConditions.add('(${tagConditions.join(' OR ')})');
              }
            }
            break;
        }
      }
    }

    // Собираем окончательный WHERE
    String whereClause = whereConditions.isEmpty ? "" : "WHERE " + whereConditions.join(' AND ');

    // Определяем множитель направления сортировки (-1 для DESC, 1 для ASC)
    // SQLite не позволяет использовать DESC/ASC в выражениях CASE,
    // поэтому используем множитель для изменения направления сортировки
    final dateFactor = newestFirst == "true" ? "-1" : "1";
    final createdFactor = newestFirst == "true" ? "-1" : "1";

    // Формируем ORDER BY как строку с правильным синтаксисом SQLite
    // Вместо использования DESC/ASC в выражениях, умножаем значения на -1 для обратной сортировки
    String orderByClause =
        "CASE WHEN date = $todayDate THEN 1 WHEN date IS NOT NULL AND date > 0 THEN 2 ELSE 3 END ASC, " +
            "priority DESC, " +
            "CASE WHEN date = $todayDate THEN 0 WHEN date IS NOT NULL AND date > 0 THEN ${dateFactor} * date ELSE 0 END, " +
            "CASE WHEN date IS NULL OR date = 0 THEN ${createdFactor} * created ELSE 0 END";

    // Формируем полный SQL-запрос
    String sqlQuery = "SELECT * FROM items $whereClause ORDER BY $orderByClause";

    // Добавляем LIMIT, если нужно
    if (lastItems > 0) {
      sqlQuery += " LIMIT $lastItems";
    }

    // Выполняем запрос
    List<Map<String, dynamic>> result = await mainDb.rawQuery(sqlQuery, whereArgs);

    // Обработка обфускированных записей, если мы в режиме скрытых записей
    if (xvHiddenMode) {
      result = result.map((item) => processItemForView(item)).toList();
    }

    myPrint('Retrieved items count: ${result.length}');
    myPrint('Today items count: ${result.where((item) => item['date'] == todayDate).length}');
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
  final today = DateTime.now();
  final todayInt = int.parse(DateFormat('yyyyMMdd').format(today));

  return await mainDb.query(
    'items',
    where: 'remind = 1 AND (date IS NULL OR date >= ?)',
    whereArgs: [todayInt],
    orderBy: 'date ASC',
  );
}

// Function to remove expired reminders with remove flag set
Future<void> removeExpiredItems() async {
  try {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayInt = dateTimeToYYYYMMDD(today);

    // Оптимизированный SQL-запрос с проверкой NULL в начале
    final count = await mainDb.rawDelete(
        'DELETE FROM items WHERE date IS NOT NULL AND date < ? AND remove = 1',
        [todayInt]
    );

    if (count > 0) {
      myPrint('Удалено $count просроченных записей');
    }
  } catch (e) {
    myPrint('Ошибка при удалении просроченных записей: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Используем FFI только на десктопных платформах
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  await initDatabases();
  // Инициализируем пути к директориям хранения
  await initStoragePaths();
  // Initialize default settings
  await initDefaultSettings();

  // Cleanup expired reminders marked for removal
  await removeExpiredItems();

  final themeName =
      await getSetting("Color theme") ?? defSettings["Color theme"];
  setThemeColors(themeName);
  // Загрузка локализации
  final languageSetting =
      await getSetting("Language") ?? defSettings["Language"];
  await readLocale(languageSetting.toLowerCase());
  // Инициализация системы уведомлений
  await SimpleNotifications.initNotifications();
  // Проверяем, включены ли напоминания перед планированием
  final enableReminders =
      await getSetting("Enable reminders") ?? defSettings["Enable reminders"];
  if (enableReminders == "true") {
    // Планируем ежедневную проверку напоминаний
    await SimpleNotifications.scheduleReminderCheck();
    myPrint('Напоминания включены, запланирована ежедневная проверка');
  } else {
    myPrint('Напоминания отключены, планирование пропущено');
  }

  await initLogging();

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
  supportedLocales:
      langNames.keys.map((key) => Locale(getLocaleCode(key))).toList(),
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

  // Переменные для обработки множественного тапа
  int _tapCount = 0;
  Timer? _tapTimer;

  @override
  void initState() {
    super.initState();
    _refreshItems();
    _updateFilterStatus(); // Обновление статуса фильтра при запуске
  }

  @override
  void dispose() {
    _tapTimer?.cancel();
    super.dispose();
  }

  void _showPhoto(String photoPath) {
    // First check if the file exists
    final file = File(photoPath);
    if (!file.existsSync()) {
      // Show a dialog with a concise message
      showCustomDialog(
        title: lw('Photo Not Found'),
        content: lw('The photo file is missing. Remove the reference?'),
        actions: [
          {'label': lw('Cancel'), 'value': false, 'isDestructive': false},
          {
            'label': lw('Remove'),
            'value': true,
            'isDestructive': true,
            'onPressed': () async {
              if (_selectedItemId != null) {
                await mainDb.update(
                  'items',
                  {'photo': null},
                  where: 'id = ?',
                  whereArgs: [_selectedItemId],
                );
                _refreshItems();
                okInfoBarBlue(lw('Photo reference removed'));
              }
            },
          },
        ],
      );
      return;
    }

    // Original photo display code if file exists
    showDialog(
      context: navigatorKey.currentContext!,
      builder: (BuildContext dialogContext) {
        final screenSize = MediaQuery.of(dialogContext).size;

        return Dialog(
          backgroundColor: clFill,
          // Make dialog use 90% of screen
          insetPadding: EdgeInsets.symmetric(
            horizontal: screenSize.width * 0.05,
            vertical: screenSize.height * 0.05,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                backgroundColor: clUpBar,
                foregroundColor: clText,
                title: Text(lw('Photo')),
                leading: IconButton(
                  icon: Icon(Icons.close),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ),
              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: screenSize.height * 0.8,
                    maxWidth: screenSize.width * 0.9,
                  ),
                  child: SingleChildScrollView(
                    child: Image.file(file, fit: BoxFit.contain),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Improved reminder check function
  Future<void> _checkReminders() async {
    try {
      myPrint('Checking today\'s events...');
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final todayInt = dateTimeToYYYYMMDD(today);

      // Get all items with today's date
      final List<Map<String, dynamic>> items = await mainDb.query(
        'items',
        where: 'date = ?',
        whereArgs: [todayInt],
        orderBy:
            'remind DESC, priority DESC', // Reminders first, then by priority
      );

      myPrint('Found ${items.length} events for today');

      if (items.isEmpty) {
        // Use okInfoBarBlue instead of Orange
        okInfoBarBlue(lw('No events for today'));
        return;
      }

      // Format text for dialog - removed duplicate heading
      StringBuffer message = StringBuffer();

      // Process each item
      for (var item in items) {
        String title = item['title'] ?? '';

        // If hidden and in hidden mode, decode
        if (item['hidden'] == 1 && xvHiddenMode) {
          title = deobfuscateText(title);
        }

        // Skip hidden records if not in hidden mode
        if (item['hidden'] == 1 && !xvHiddenMode) continue;

        // Add formatting for reminders
        bool isReminder = item['remind'] == 1;
        String priorityStars = '';

        // Add stars for priority
        int priority = item['priority'] ?? 0;
        if (priority > 0) {
          priorityStars = ' ' + '★' * (priority > 3 ? 3 : priority);
        }

        // Format entry depending on whether it's a reminder or not
        if (isReminder) {
          message.write('• ! $title$priorityStars\n');
        } else {
          message.write('• $title$priorityStars\n');
        }
      }

      // Show dialog window
      showCustomDialog(
        title: lw('Events for today'),
        content: message.toString(),
        actions: [
          {'label': lw('Ok'), 'value': null, 'isDestructive': false},
        ],
      );

      // Refresh items list after check
      _refreshItems();
    } catch (e) {
      myPrint('Error checking events: $e');
      okInfoBarRed(lw('Error checking events'));
    }
  }

  // Обработчик множественного тапа
  void _handleMultipleTap() {
    _tapCount++;

    if (_tapCount == 1) {
      // При первом тапе запускаем таймер
      _tapTimer?.cancel();
      _tapTimer = Timer(Duration(milliseconds: 800), () {
        // Если таймер истек, сбрасываем счетчик
        _tapCount = 0;
      });
    } else if (_tapCount >= 4) {
      // При четвертом тапе обрабатываем вход в скрытый режим
      _tapCount = 0;
      _tapTimer?.cancel();
      _showPinDialog();
    }
  }

  // Метод _showPinDialog должен использовать this.context
  void _showPinDialog() async {
    // Проверяем, установлен ли уже PIN-код
    bool hasPIN = await isPinSet();

    if (hasPIN) {
      // Если PIN уже установлен, показываем диалог входа
      _showEnterPinDialog();
    } else {
      // Если PIN еще не установлен, показываем диалог создания PIN-кода
      _showCreatePinDialog();
    }
  }

  // Диалог для создания нового PIN-кода
  void _showCreatePinDialog() {
    final TextEditingController pinController = TextEditingController();
    final FocusNode focusNode = FocusNode();

    showDialog(
      context: this.context,
      barrierDismissible: false,
      builder: (dialogContext) {
        // Используем Future.delayed для надежной установки фокуса
        Future.delayed(Duration.zero, () {
          FocusScope.of(dialogContext).requestFocus(focusNode);
        });

        return AlertDialog(
          backgroundColor: clFill,
          title: Text(lw('Create PIN code'), style: TextStyle(color: clText)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                lw('Enter a 4-digit PIN code to access private items'),
                style: TextStyle(color: clText),
              ),
              SizedBox(height: 16),
              TextField(
                controller: pinController,
                focusNode: focusNode,
                autofocus: true,
                // Добавляем autofocus свойство
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: fsLarge, color: clText),
                decoration: InputDecoration(
                  hintText: '****',
                  counterText: '',
                  fillColor: clFill,
                  filled: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: clUpBar,
                foregroundColor: clText,
              ),
              child: Text(lw('Cancel')),
              onPressed: () => Navigator.pop(dialogContext),
            ),
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: clUpBar,
                foregroundColor: clText,
              ),
              child: Text(lw('Save')),
              onPressed: () async {
                // Получаем PIN из контроллера
                final pin = pinController.text;

                // Проверяем, что PIN состоит из 4 цифр
                if (pin.length == 4 && int.tryParse(pin) != null) {
                  Navigator.pop(dialogContext);

                  // Сохраняем PIN-код
                  await saveNewPin(pin);

                  // Активируем режим скрытых записей
                  setState(() {
                    xvHiddenMode = true;
                    currentPin = pin;
                  });

                  // Обновляем список элементов, чтобы отобразить скрытые
                  _refreshItems();

                  // Запускаем таймер автоматического выхода
                  resetHiddenModeTimer();

                  // Показываем подтверждение
                  okInfoBarGreen(lw('Private mode activated'));
                } else {
                  // Показываем ошибку, если PIN неверного формата
                  okInfoBarRed(lw('PIN must be 4 digits'));
                }
              },
            ),
          ],
        );
      },
    );
  }

  // Диалог для ввода существующего PIN-кода
  void _showEnterPinDialog() {
    String enteredPin = '';
    final TextEditingController pinController = TextEditingController();
    final FocusNode focusNode = FocusNode();

    showDialog(
      context: this.context,
      barrierDismissible: false,
      builder: (dialogContext) {
        // Используем Future.delayed вместо addPostFrameCallback
        Future.delayed(Duration.zero, () {
          FocusScope.of(dialogContext).requestFocus(focusNode);
        });
        return AlertDialog(
          backgroundColor: clFill,
          title: Text(lw('Enter PIN code'), style: TextStyle(color: clText)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                lw('Enter your PIN code to access private items'),
                style: TextStyle(color: clText),
              ),
              SizedBox(height: 16),
              TextField(
                controller: pinController,
                focusNode: focusNode,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: fsLarge, color: clText),
                decoration: InputDecoration(
                  hintText: '****',
                  counterText: '',
                  fillColor: clFill,
                  filled: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  enteredPin = value;
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: clUpBar,
                foregroundColor: clText,
              ),
              child: Text(lw('Cancel')),
              onPressed: () => Navigator.pop(dialogContext),
            ),
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: clUpBar,
                foregroundColor: clText,
              ),
              child: Text(lw('Ok')),
              onPressed: () async {
                // Проверяем PIN-код
                if (await verifyPin(enteredPin)) {
                  Navigator.pop(dialogContext);

                  // Активируем режим скрытых записей
                  setState(() {
                    xvHiddenMode = true;
                    currentPin = enteredPin;
                  });

                  // Обновляем список элементов, чтобы отобразить скрытые
                  _refreshItems();

                  // Запускаем таймер автоматического выхода
                  resetHiddenModeTimer();

                  // Показываем подтверждение
                  okInfoBarGreen(lw('Private mode activated'));
                } else {
                  // Показываем ошибку, если PIN неверный
                  Navigator.pop(dialogContext);
                  okInfoBarRed(lw('Incorrect PIN'));
                }
              },
            ),
          ],
        );
      },
    );
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
    List<PopupMenuEntry> menuItems = [
      // В методе _showContextMenu
      PopupMenuItem(
        child: ListTile(
          leading: Icon(Icons.edit, color: clText),
          title: Text(lw('Edit'), style: TextStyle(color: clText)),
          onTap: () {
            Navigator.pop(context); // Close the menu
            // Navigate to edit page, передаем только ID
            Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder:
                    (context) => EditItemPage(
                      itemId: item['id'], // Передаем только ID
                    ),
              ),
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
          leading: Icon(Icons.delete, color: clRed),
          title: Text(lw('Delete'), style: TextStyle(color: clText)),
          onTap: () {
            Navigator.pop(context); // Close the menu

            // Use the showCustomDialog function for delete confirmation
            showCustomDialog(
              title: lw('Delete Item'),
              content: lw('Are you sure you want to delete this item?'),
              actions: [
                {'label': lw('Cancel'), 'value': false, 'isDestructive': false},
                {
                  'label': lw('Delete'),
                  'value': true,
                  'isDestructive': true,
                  'onPressed': () async {
                    // First check if item has a photo
                    final photoPath = item['photo'];

                    // Cancel specific reminder if it exists
                    await SimpleNotifications.cancelSpecificReminder(item['id']);

                    // Delete item from database
                    await mainDb.delete(
                      'items',
                      where: 'id = ?',
                      whereArgs: [item['id']],
                    );

                    // Delete photo file if exists
                    if (isValidPhotoPath(photoPath)) {
                      await deletePhotoFile(photoPath);
                    }

                    _refreshItems();
                  },
                },
              ],
            );
          },
        ),
      ),
    ];

    // Если находимся в режиме скрытых записей, добавляем опцию выхода
    if (xvHiddenMode) {
      menuItems.add(
        PopupMenuItem(
          child: ListTile(
            leading: Icon(Icons.exit_to_app, color: clText),
            title: Text(
              lw('Exit private mode'),
              style: TextStyle(color: clText),
            ),
            onTap: () {
              Navigator.pop(context); // Close the menu
              setState(() {
                xvHiddenMode = false;
                currentPin = '';
              });
              _refreshItems();
              okInfoBarBlue(lw('Left private mode'));
            },
          ),
        ),
      );
    }

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(200, 200, 200, 200),
      color: clMenu,
      // Set the background color to clMenu to match the theme
      items: menuItems,
    );
  }

  @override
  Widget build(BuildContext context) {
    globalContext = context;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: xvHiddenMode ? hidModeColor : clUpBar,
        foregroundColor: clText,
        title: GestureDetector(
          onLongPress: () => showHelp(20), // ID 20 для заголовка
          onTap: _handleMultipleTap, // Добавляем обработчик множественного тапа
          child: Row(
            children: [
              Text(
                lw('Memorizer'),
                style: TextStyle(fontSize: fsLarge, fontWeight: fwBold),
              ),
              if (xvHiddenMode)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Icon(Icons.visibility_off, size: 16),
                ),
            ],
          ),
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
                  ? Navigator.of(context).pop()
                  : SystemNavigator.pop();
            },
          ),
        ),
        actions: [
          // Добавляем кнопку проверки напоминаний
          GestureDetector(
            onLongPress: () => showHelp(40),
            // ID 40 для кнопки проверки напоминаний
            child: IconButton(
              icon: Icon(Icons.notifications),
              tooltip: lw('Check reminders'),
              onPressed: _checkReminders,
            ),
          ),
          // Индикатор состояния фильтра
          GestureDetector(
            onLongPress: () => showHelp(22), // ID 22 для индикатора фильтра
            child: Center(
              child: Text(
                _filterStatus,
                style: TextStyle(
                  color: clText,
                  fontSize: fsNormal,
                  fontWeight: fwBold,
                ),
              ),
            ),
          ),
          // Removed Filter and Tag filter buttons here
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
                      builder: (context) => buildSettingsScreen(),
                    ),
                  ).then((needsRefresh) {
                    _refreshItems();
                  });
                } else if (result == 'about') {
                  _showAbout();
                } else if (result == 'clear_filters') {
                  _clearAllFilters();
                } else if (result == 'filters') {
                  // Added handler for Filters option
                  Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (context) => FiltersScreen()),
                  ).then((needsRefresh) {
                    if (needsRefresh == true) {
                      _refreshItems();
                    }
                  });
                } else if (result == 'tag_filter') {
                  // Added handler for Tag filter option
                  Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (context) => TagsCloudScreen()),
                  ).then((needsRefresh) {
                    if (needsRefresh == true) {
                      _refreshItems();
                    }
                  });
                } else if (result == 'exit_private') {
                  setState(() {
                    xvHiddenMode = false;
                    currentPin = '';
                  });
                  _refreshItems();
                  okInfoBarBlue(lw('Left private mode'));
                }
              },
              itemBuilder: (BuildContext context) {
                List<PopupMenuEntry<String>> menuItems = [
                  PopupMenuItem<String>(
                    value: 'clear_filters',
                    child: GestureDetector(
                      onLongPress: () => showHelp(26),
                      // ID 26 для пункта меню очистки фильтров
                      child: Text(
                        lw('Clear all filters'),
                        style: TextStyle(color: clText),
                      ),
                    ),
                  ),
                  // Added Filter option
                  PopupMenuItem<String>(
                    value: 'filters',
                    child: GestureDetector(
                      onLongPress: () => showHelp(23),
                      // Reusing ID 23 from former filter button
                      child: Text(
                        lw('Filters'),
                        style: TextStyle(color: clText),
                      ),
                    ),
                  ),
                  // Added Tag filter option
                  PopupMenuItem<String>(
                    value: 'tag_filter',
                    child: GestureDetector(
                      onLongPress: () => showHelp(24),
                      // Reusing ID 24 from former tag filter button
                      child: Text(
                        lw('Tag filter'),
                        style: TextStyle(color: clText),
                      ),
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'settings',
                    child: GestureDetector(
                      onLongPress: () => showHelp(27),
                      // ID 27 для пункта меню настроек
                      child: Text(
                        lw('Settings'),
                        style: TextStyle(color: clText),
                      ),
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'about',
                    child: GestureDetector(
                      onLongPress: () => showHelp(28),
                      // ID 28 для пункта меню "О программе"
                      child: Text(lw('About'), style: TextStyle(color: clText)),
                    ),
                  ),
                ];

                // Добавляем опцию выхода из режима скрытых записей, если мы в нем
                if (xvHiddenMode) {
                  menuItems.add(
                    PopupMenuItem<String>(
                      value: 'exit_private',
                      child: Text(
                        lw('Exit private mode'),
                        style: TextStyle(color: clText),
                      ),
                    ),
                  );
                }

                return menuItems;
              },
            ),
          ),
        ],
      ),
      body:
          _isLoading
              ? Center(child: CircularProgressIndicator())
              : _items.isEmpty
              ? Center(
                child: Text(
                  xvHiddenMode
                      ? lw('No private items yet. Press + to add.')
                      : lw('No items yet. Press + to add.'),
                  style: TextStyle(color: clText, fontSize: fsMedium),
                ),
              )
              : ListView.builder(
            itemCount: _items.length,
// В методе build() класса _HomePageState, в части ListView.builder
            itemBuilder: (context, index) {
              final item = _items[index];
              final priorityValue = item['priority'] ?? 0;
              final hasDate = item['date'] != null && item['date'] != 0;
              final hasTime = item['time'] != null; // Проверяем наличие времени
              final isReminder = item['remind'] == 1;
              final hasPhoto = isValidPhotoPath(item['photo']);

              // Проверяем, является ли дата текущей
              final todayDate = dateTimeToYYYYMMDD(DateTime.now());
              final isToday = hasDate && item['date'] == todayDate;

              // Format date for display if it exists
              String? formattedDate;
              if (hasDate) {
                try {
                  final eventDate = yyyymmddToDateTime(item['date']);
                  if (eventDate != null) {
                    formattedDate = DateFormat(ymdDateFormat).format(eventDate);
                  } else {
                    myPrint('Warning: Could not format date: ${item['date']}');
                  }
                } catch (e) {
                  myPrint('Error formatting date: $e');
                }
              }

              // Format time for display if it exists
              String? formattedTime;
              if (hasTime) {
                formattedTime = timeIntToString(item['time']);
                if (formattedTime == null) {
                  myPrint('Warning: Could not format time: ${item['time']}');
                }
              }

              // Safely get content and tags with null checks
              final String content = item['content'] ?? '';
              final String tags = item['tags'] ?? '';

              return ListTile(
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item['title'],
                        style: TextStyle(
                          fontWeight: fwBold,
                          color: isToday ? clRed : clText,
                        ),
                      ),
                    ),
                    // Display priority as stars
                    if (priorityValue > 0)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(
                          priorityValue > 3 ? 3 : priorityValue,
                              (i) => Icon(Icons.star, color: clUpBar, size: 34),
                        ),
                      ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(content, style: TextStyle(color: isToday ? clRed : clText)),
                    if (tags.isNotEmpty)
                      Text(
                        'Tags: $tags',
                        style: TextStyle(
                          fontSize: fsNormal,
                          color: isToday ? clRed : clText,
                          fontStyle: FontStyle.italic,
                        ),
                      ),

                    // Add date and time information if available
                    if (hasDate && formattedDate != null)
                      Row(
                        children: [
                          Icon(Icons.event, color: isToday ? clRed : clText, size: 16),
                          SizedBox(width: 4),
                          Text(
                            formattedDate,
                            style: TextStyle(
                              fontSize: fsMedium,
                              color: isReminder || isToday ? clRed : clText,
                              fontWeight: isReminder || isToday ? fwBold : fwNormal,
                            ),
                          ),

                          // Add time display if available
                          if (hasTime && formattedTime != null) ...[
                            SizedBox(width: 8),
                            Icon(Icons.access_time, color: isToday ? clRed : clText, size: 14),
                            SizedBox(width: 2),
                            Text(
                              formattedTime,
                              style: TextStyle(
                                fontSize: fsMedium,
                                color: isReminder || isToday ? clRed : clText,
                                fontWeight: isReminder || isToday ? fwBold : fwNormal,
                              ),
                            ),
                          ],

                          // Add reminder bell icon next to the date/time with spacing
                          if (isReminder)
                            Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Icon(
                                Icons.notifications_active,
                                color: clRed,
                                size: 16,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
                // Остальной код ListTile остается без изменений...
                tileColor: _selectedItemId == item['id']
                    ? clSel
                    : isToday
                    ? Color(0x22FF0000)
                    : clFill,
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isToday)
                      Padding(
                        padding: const EdgeInsets.only(right: 4.0),
                        child: Icon(Icons.today, color: clRed, size: 16),
                      ),
                    if (xvHiddenMode)
                      Padding(
                        padding: const EdgeInsets.only(right: 4.0),
                        child: Icon(Icons.lock, color: clText, size: 16),
                      ),
                    if (priorityValue > 0)
                      Container(
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
                            fontWeight: fwBold,
                            fontSize: fsSmall,
                          ),
                        ),
                      ),
                  ],
                ),
                trailing: hasPhoto
                    ? IconButton(
                  icon: Icon(Icons.photo, color: isToday ? clRed : clText),
                  onPressed: () => _showPhoto(item['photo']),
                )
                    : null,
                onTap: () {
                  // Just select the item and highlight it
                  setState(() {
                    _selectedItemId = item['id'];
                  });

                  // Сбрасываем таймер автоматического выхода из скрытого режима
                  if (xvHiddenMode) {
                    resetHiddenModeTimer();
                  }
                },
                onLongPress: () {
                  // Show context menu with Edit and Delete options
                  _showContextMenu(context, item);

                  // Сбрасываем таймер автоматического выхода из скрытого режима
                  if (xvHiddenMode) {
                    resetHiddenModeTimer();
                  }
                },
              );
            },
          ),

      floatingActionButton: GestureDetector(
        onLongPress: () => showHelp(29), // ID 29 для кнопки добавления
        child: FloatingActionButton(
          backgroundColor: xvHiddenMode ? Color(0xFFf29238) : clUpBar,
          foregroundColor: clText,
          onPressed: () async {
            // Сбрасываем таймер автоматического выхода из скрытого режима
            if (xvHiddenMode) {
              resetHiddenModeTimer();
            }

            final result = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder:
                    (context) =>
                        EditItemPage(), // Без параметров для новой записи
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
  txt += '${lw('Version')}: $progVersion';
  txt += '\n';
  txt += '${lw('Build number')}: $buildNumber';
  txt += '\n\n';
  txt += '(c): $progAuthor 2025';
  txt += '\n\n';
  txt += lw('Long press on interface elements for help');
  okInfo(txt);
}
