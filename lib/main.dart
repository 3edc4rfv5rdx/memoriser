// main.dart
import 'dart:async'; // Для Timer
import 'dart:convert';
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
    version: 12, // Increased from 11 to 12 for monthly field
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
          photo TEXT DEFAULT NULL,
          yearly INTEGER DEFAULT 0,
          monthly INTEGER DEFAULT 0,
          daily INTEGER DEFAULT 0,
          daily_times TEXT DEFAULT NULL,
          daily_days INTEGER DEFAULT 127,
          daily_sound TEXT DEFAULT NULL,
          sound TEXT DEFAULT NULL
        )
      ''');
    },
    onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 6) {
        // Migration for version 6 - recreate table with time field
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

        // Transfer data from old table to new (time will be NULL)
        await db.execute('''
          INSERT INTO items_new(id, title, content, tags, priority, date, 
                               remind, created, remove, hidden, photo)
          SELECT id, title, content, tags, priority, date, 
                 remind, created, remove, hidden, photo
          FROM items
        ''');

        // Drop old table and rename new one
        await db.execute('DROP TABLE items');
        await db.execute('ALTER TABLE items_new RENAME TO items');

        myPrint("Database upgraded to version 6: Added 'time' field after 'date'");
      }

      if (oldVersion < 7) {
        // Migration for version 7 - add yearly field
        await db.execute('ALTER TABLE items ADD COLUMN yearly INTEGER DEFAULT 0');
        myPrint("Database upgraded to version 7: Added 'yearly' field");
      }

      if (oldVersion < 8) {
        // Migration for version 8 - convert single photo paths to JSON arrays
        myPrint("Starting migration to version 8: Converting photo paths to JSON arrays");
        final items = await db.query('items', columns: ['id', 'photo']);
        int convertedCount = 0;
        for (var item in items) {
          final photoPath = item['photo'];
          if (photoPath != null && (photoPath as String).isNotEmpty) {
            // Check if it's already a JSON array
            if (!photoPath.startsWith('[')) {
              final jsonArray = jsonEncode([photoPath]);
              await db.update(
                'items',
                {'photo': jsonArray},
                where: 'id = ?',
                whereArgs: [item['id']],
              );
              convertedCount++;
            }
          }
        }
        myPrint("Database upgraded to version 8: Converted $convertedCount photo paths to JSON arrays");
      }

      if (oldVersion < 9) {
        // Migration for version 9 - move photos to item folders
        myPrint("Starting migration to version 9: Moving photos to item folders");
        await _migratePhotosToItemFolders(db);
      }

      if (oldVersion < 10) {
        // Migration for version 10 - add daily reminder fields
        await db.execute('ALTER TABLE items ADD COLUMN daily INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE items ADD COLUMN daily_times TEXT DEFAULT NULL');
        await db.execute('ALTER TABLE items ADD COLUMN daily_days INTEGER DEFAULT 127');
        await db.execute('ALTER TABLE items ADD COLUMN daily_sound TEXT DEFAULT NULL');
        myPrint("Database upgraded to version 10: Added daily reminder fields");
      }

      if (oldVersion < 11) {
        // Migration for version 11 - add sound field for one-time reminders
        await db.execute('ALTER TABLE items ADD COLUMN sound TEXT DEFAULT NULL');
        myPrint("Database upgraded to version 11: Added sound field");
      }

      if (oldVersion < 12) {
        // Migration for version 12 - add monthly field for monthly repeating reminders
        await db.execute('ALTER TABLE items ADD COLUMN monthly INTEGER DEFAULT 0');
        myPrint("Database upgraded to version 12: Added 'monthly' field");
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

// Migration function to move photos to item folders
Future<void> _migratePhotosToItemFolders(Database db) async {
  try {
    // Ensure storage paths are initialized
    if (photoDirectory == null) {
      await initStoragePaths();
    }
    if (photoDirectory == null) {
      myPrint("Cannot migrate photos: photoDirectory is null");
      return;
    }

    final items = await db.query('items', columns: ['id', 'photo']);
    int migratedCount = 0;

    for (var item in items) {
      final itemId = item['id'] as int;
      final photoPaths = parsePhotoPaths(item['photo']);

      if (photoPaths.isEmpty) continue;

      // Create item folder
      final itemDir = Directory('${photoDirectory!.path}/item_$itemId');
      if (!await itemDir.exists()) {
        await itemDir.create(recursive: true);
      }

      List<String> newPaths = [];
      for (var oldPath in photoPaths) {
        final oldFile = File(oldPath);
        if (await oldFile.exists()) {
          final fileName = oldPath.split('/').last;
          final newPath = '${itemDir.path}/$fileName';

          // Move file to item folder
          try {
            await oldFile.copy(newPath);
            await oldFile.delete();
            newPaths.add(newPath);
            myPrint("Migrated photo: $oldPath -> $newPath");
          } catch (e) {
            myPrint("Error migrating photo $oldPath: $e");
            // Keep old path if migration fails
            newPaths.add(oldPath);
          }
        }
      }

      // Update database with new paths
      if (newPaths.isNotEmpty) {
        final newPhotoData = jsonEncode(newPaths);
        await db.update(
          'items',
          {'photo': newPhotoData},
          where: 'id = ?',
          whereArgs: [itemId],
        );
        migratedCount++;
      }
    }

    myPrint("Database upgraded to version 9: Migrated photos for $migratedCount items");
  } catch (e) {
    myPrint("Error during photo migration: $e");
  }
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
    String whereClause = whereConditions.isEmpty ? "" : "WHERE ${whereConditions.join(' AND ')}";

    // Определяем множитель направления сортировки (-1 для DESC, 1 для ASC)
    // SQLite не позволяет использовать DESC/ASC в выражениях CASE,
    // поэтому используем множитель для изменения направления сортировки
    final dateFactor = newestFirst == "true" ? "-1" : "1";
    final createdFactor = newestFirst == "true" ? "-1" : "1";

    // Формируем ORDER BY как строку с правильным синтаксисом SQLite
    // Вместо использования DESC/ASC в выражениях, умножаем значения на -1 для обратной сортировки
    String orderByClause =
        "CASE WHEN date = $todayDate THEN 1 WHEN date IS NOT NULL AND date > 0 THEN 2 ELSE 3 END ASC, " "priority DESC, " "CASE WHEN date = $todayDate THEN 0 WHEN date IS NOT NULL AND date > 0 THEN $dateFactor * date ELSE 0 END, " "CASE WHEN date IS NULL OR date = 0 THEN $createdFactor * created ELSE 0 END";

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

// Function to remove expired reminders with remove flag set AND update yearly events
Future<void> removeExpiredItems() async {
  try {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayInt = dateTimeToYYYYMMDD(today);

    // FIRST update yearly events
    await updateYearlyEvents(todayInt!);

    // THEN update monthly events
    await updateMonthlyEvents(todayInt);

    // THEN get expired records (NOT yearly, NOT monthly) with remove flag to delete their photos first
    final expiredItems = await mainDb.query(
      'items',
      where: 'date IS NOT NULL AND date < ? AND remove = 1 AND yearly = 0 AND monthly = 0',
      whereArgs: [todayInt],
    );

    myPrint('Found ${expiredItems.length} expired items to delete');

    // Delete photo folders for expired items
    int deletedFolders = 0;
    for (var item in expiredItems) {
      final itemId = item['id'] as int;
      try {
        await deleteItemPhotoDir(itemId);
        deletedFolders++;
      } catch (e) {
        myPrint('Error deleting photo folder for item $itemId: $e');
      }
    }

    // Now delete the expired records from database
    final count = await mainDb.rawDelete(
        'DELETE FROM items WHERE date IS NOT NULL AND date < ? AND remove = 1 AND yearly = 0 AND monthly = 0',
        [todayInt]
    );

    if (count > 0) {
      myPrint('Deleted $count expired items');
      if (deletedFolders > 0) {
        myPrint('Deleted $deletedFolders photo folders');
      }
    }
  } catch (e) {
    myPrint('Error removing expired items: $e');
  }
}

// New function to update yearly events
Future<void> updateYearlyEvents(int today) async {
  try {
    // Find all yearly events with past dates
    final yearlyEvents = await mainDb.query(
      'items',
      where: 'yearly = 1 AND date < ?',
      whereArgs: [today],
    );

    myPrint('Found ${yearlyEvents.length} yearly events to update');

    for (var event in yearlyEvents) {
      try {
        final eventId = event['id'] as int;
        final oldDateInt = event['date'] as int;
        final oldDate = yyyymmddToDateTime(oldDateInt);

        if (oldDate == null) {
          myPrint('Invalid date for yearly event $eventId: $oldDateInt');
          continue;
        }

        // Update year to next year
        final newDate = DateTime(oldDate.year + 1, oldDate.month, oldDate.day);
        final newDateInt = dateTimeToYYYYMMDD(newDate);

        if (newDateInt != null) {
          await mainDb.update(
            'items',
            {'date': newDateInt},
            where: 'id = ?',
            whereArgs: [eventId],
          );

          myPrint('Updated yearly event $eventId: ${oldDate.year} -> ${newDate.year}');
        }
      } catch (e) {
        myPrint('Error updating yearly event ${event['id']}: $e');
      }
    }

    if (yearlyEvents.isNotEmpty) {
      myPrint('Updated ${yearlyEvents.length} yearly events to next year');
    }
  } catch (e) {
    myPrint('Error updating yearly events: $e');
  }
}

// Function to update monthly events
Future<void> updateMonthlyEvents(int today) async {
  try {
    // Find all monthly events with past dates
    final monthlyEvents = await mainDb.query(
      'items',
      where: 'monthly = 1 AND date < ?',
      whereArgs: [today],
    );

    myPrint('Found ${monthlyEvents.length} monthly events to update');

    for (var event in monthlyEvents) {
      try {
        final eventId = event['id'] as int;
        final oldDateInt = event['date'] as int;
        final oldDate = yyyymmddToDateTime(oldDateInt);

        if (oldDate == null) {
          myPrint('Invalid date for monthly event $eventId: $oldDateInt');
          continue;
        }

        // Calculate next month
        int targetDay = oldDate.day;
        int newYear = oldDate.year;
        int newMonth = oldDate.month + 1;

        // Handle year rollover
        if (newMonth > 12) {
          newMonth = 1;
          newYear++;
        }

        // Handle month-end edge cases (e.g., Jan 31 -> Feb 28/29)
        int daysInNewMonth = DateTime(newYear, newMonth + 1, 0).day;
        int actualDay = targetDay > daysInNewMonth ? daysInNewMonth : targetDay;

        final newDate = DateTime(newYear, newMonth, actualDay);
        final newDateInt = dateTimeToYYYYMMDD(newDate);

        if (newDateInt != null) {
          await mainDb.update(
            'items',
            {'date': newDateInt},
            where: 'id = ?',
            whereArgs: [eventId],
          );

          myPrint('Updated monthly event $eventId: ${oldDate.toString().substring(0, 10)} -> ${newDate.toString().substring(0, 10)}');
        }
      } catch (e) {
        myPrint('Error updating monthly event ${event['id']}: $e');
      }
    }

    if (monthlyEvents.isNotEmpty) {
      myPrint('Updated ${monthlyEvents.length} monthly events to next month');
    }
  } catch (e) {
    myPrint('Error updating monthly events: $e');
  }
}

// Update the main() function:
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Use FFI only on desktop platforms
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  await initDatabases();
  // Initialize storage directory paths
  await initStoragePaths();
  // Cleanup orphaned temp photo directories
  await cleanupOrphanedTempDirs();
  // Initialize default settings
  await initDefaultSettings();

  // Cleanup expired reminders marked for removal
  await removeExpiredItems();

  final themeName =
      await getSetting("Color theme") ?? defSettings["Color theme"];
  setThemeColors(themeName);
  // Load localization
  final languageSetting =
      await getSetting("Language") ?? defSettings["Language"];
  await readLocale(languageSetting.toLowerCase());
  // Initialize notification system
  await SimpleNotifications.initNotifications();

  // НОВОЕ: Перепланировать все напоминания при каждом запуске приложения
  try {
    myPrint('Rescheduling all reminders on app startup...');
    await SimpleNotifications.rescheduleAllReminders();
    myPrint('Reminders rescheduled successfully on startup');
  } catch (e) {
    myPrint('Error rescheduling reminders on startup: $e');
    // Не показываем ошибку пользователю при запуске, только логируем
  }

  await initLogging();

  // TEST: Add test logs immediately after initLogging
  myPrint('=== LOGGING TEST START ===');
  myPrint('xvDebug value: $xvDebug');
  myPrint('=== LOGGING TEST END ===');

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
  const HomePage({super.key});

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
  bool _isInYearlyFolder = false;
  bool _isInNotesFolder = false;
  bool _isInDailyFolder = false;
  bool _isInMonthlyFolder = false;

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

  void _enterNotesFolder() {
    setState(() {
      _isInNotesFolder = true;
      _isInYearlyFolder = false; // Убеждаемся что другие папки закрыты
      _isInDailyFolder = false;
      xvFilter = 'notes:true'; // Устанавливаем фильтр на заметки
    });
    _refreshItems();
    _updateFilterStatus();
  }

  void _exitNotesFolder() {
    setState(() {
      _isInNotesFolder = false;
      xvFilter = ''; // Очищаем фильтр
    });
    _refreshItems();
    _updateFilterStatus();
  }

  void _enterYearlyFolder() {
    setState(() {
      _isInYearlyFolder = true;
      _isInNotesFolder = false;
      _isInDailyFolder = false;
      xvFilter = 'yearly:true'; // Устанавливаем фильтр на ежегодные
    });
    _refreshItems();
    _updateFilterStatus();
  }

  void _exitYearlyFolder() {
    setState(() {
      _isInYearlyFolder = false;
      xvFilter = ''; // Очищаем фильтр
    });
    _refreshItems();
    _updateFilterStatus();
  }

  void _enterDailyFolder() {
    setState(() {
      _isInDailyFolder = true;
      _isInYearlyFolder = false;
      _isInNotesFolder = false;
      xvFilter = 'daily:true';
    });
    _refreshItems();
    _updateFilterStatus();
  }

  void _exitDailyFolder() {
    setState(() {
      _isInDailyFolder = false;
      xvFilter = '';
    });
    _refreshItems();
    _updateFilterStatus();
  }

  void _enterMonthlyFolder() {
    setState(() {
      _isInMonthlyFolder = true;
      _isInYearlyFolder = false;
      _isInNotesFolder = false;
      _isInDailyFolder = false;
      xvFilter = 'monthly:true';
    });
    _refreshItems();
    _updateFilterStatus();
  }

  void _exitMonthlyFolder() {
    setState(() {
      _isInMonthlyFolder = false;
      xvFilter = '';
    });
    _refreshItems();
    _updateFilterStatus();
  }

  Map<String, dynamic> _createYearlyFolderItem() {
    return {
      'id': -2, // Специальный ID для виртуального элемента
      'isVirtual': true,
      'type': 'yearly_folder',
      'title': lw('Yearly Events'),
      'content': '',
      'tags': '',
      'priority': 0,
      'date': null,
      'time': null,
      'remind': 0,
      'yearly': 0,
      'hidden': 0,
      'photo': null,
    };
  }

  Map<String, dynamic> _createNotesFolderItem() {
    return {
      'id': -3, // Специальный ID для виртуального элемента
      'isVirtual': true,
      'type': 'notes_folder',
      'title': lw('Notes'),
      'content': '',
      'tags': '',
      'priority': 0,
      'date': null,
      'time': null,
      'remind': 0,
      'yearly': 0,
      'hidden': 0,
      'photo': null,
    };
  }

  Map<String, dynamic> _createDailyFolderItem() {
    return {
      'id': -4, // Специальный ID для виртуального элемента
      'isVirtual': true,
      'type': 'daily_folder',
      'title': lw('Daily Reminders'),
      'content': '',
      'tags': '',
      'priority': 0,
      'date': null,
      'time': null,
      'remind': 0,
      'yearly': 0,
      'hidden': 0,
      'photo': null,
    };
  }

  Map<String, dynamic> _createMonthlyFolderItem() {
    return {
      'id': -5, // Special ID for virtual element (next after daily=-4)
      'isVirtual': true,
      'type': 'monthly_folder',
      'title': lw('Monthly Events'),
      'content': '',
      'tags': '',
      'priority': 0,
      'date': null,
      'time': null,
      'remind': 0,
      'yearly': 0,
      'monthly': 0,
      'hidden': 0,
      'photo': null,
    };
  }

  Future<int> _getYearlyItemsCount() async {
    try {
      // Подсчитываем количество ежегодных записей
      final count = await mainDb.rawQuery(
        'SELECT COUNT(*) as count FROM items WHERE yearly = 1 AND ${xvHiddenMode ? 'hidden = 1' : '(hidden = 0 OR hidden IS NULL)'}',
      );

      return count.isNotEmpty ? (count.first['count'] as int? ?? 0) : 0;
    } catch (e) {
      myPrint('Error counting yearly items: $e');
      return 0;
    }
  }

  Future<int> _getNotesItemsCount() async {
    try {
      // Подсчитываем количество записей без времени, не ежегодных и не daily
      final count = await mainDb.rawQuery(
        'SELECT COUNT(*) as count FROM items WHERE time IS NULL AND yearly != 1 AND (daily != 1 OR daily IS NULL) AND ${xvHiddenMode ? 'hidden = 1' : '(hidden = 0 OR hidden IS NULL)'}',
      );

      return count.isNotEmpty ? (count.first['count'] as int? ?? 0) : 0;
    } catch (e) {
      myPrint('Error counting notes items: $e');
      return 0;
    }
  }

  Future<int> _getDailyItemsCount() async {
    try {
      // Подсчитываем количество записей с ежедневными напоминаниями
      final count = await mainDb.rawQuery(
        'SELECT COUNT(*) as count FROM items WHERE daily = 1 AND ${xvHiddenMode ? 'hidden = 1' : '(hidden = 0 OR hidden IS NULL)'}',
      );

      return count.isNotEmpty ? (count.first['count'] as int? ?? 0) : 0;
    } catch (e) {
      myPrint('Error counting daily items: $e');
      return 0;
    }
  }

  Future<int> _getMonthlyItemsCount() async {
    try {
      // Count monthly reminder records
      final count = await mainDb.rawQuery(
        'SELECT COUNT(*) as count FROM items WHERE monthly = 1 AND ${xvHiddenMode ? 'hidden = 1' : '(hidden = 0 OR hidden IS NULL)'}',
      );

      return count.isNotEmpty ? (count.first['count'] as int? ?? 0) : 0;
    } catch (e) {
      myPrint('Error counting monthly items: $e');
      return 0;
    }
  }

  void _showPhotoGallery(List<String> photoPaths) {
    if (photoPaths.isEmpty) return;

    // Filter to only valid paths
    final validPaths = photoPaths.where((path) {
      final file = File(path);
      return file.existsSync();
    }).toList();

    if (validPaths.isEmpty) {
      // All photos are missing
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

    // Show gallery dialog
    showDialog(
      context: navigatorKey.currentContext!,
      barrierColor: Colors.black87,
      builder: (BuildContext dialogContext) {
        return _PhotoGalleryDialog(
          photoPaths: validPaths,
          onClose: () => Navigator.of(dialogContext).pop(),
        );
      },
    );
  }

// Updated _checkReminders function in _HomePageState:
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
        orderBy: 'remind DESC, priority DESC', // Reminders first, then by priority
      );

      myPrint('Found ${items.length} events for today');

      if (items.isEmpty) {
        okInfoBarBlue(lw('No events for today'));
        return;
      }

      // Format text for dialog
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

        // Add formatting for reminders and yearly/monthly events
        bool isReminder = item['remind'] == 1;
        bool isYearly = item['yearly'] == 1;
        bool isMonthly = item['monthly'] == 1;
        String priorityStars = '';

        // Add stars for priority
        int priority = item['priority'] ?? 0;
        if (priority > 0) {
          priorityStars = ' ${'★' * (priority > 3 ? 3 : priority)}';
        }

        // Add time if available
        String timeStr = '';
        final itemTime = item['time'] as int?;
        if (itemTime != null) {
          final timeString = timeIntToString(itemTime);
          if (timeString != null) {
            timeStr = ' @ $timeString';
          }
        }

        // Format entry with yearly/monthly indicator
        if (isReminder) {
          String prefix = isYearly ? '• 🔄 🔔 ' : isMonthly ? '• 📅 🔔 ' : '• 🔔 ';
          message.write('$prefix$title$timeStr$priorityStars\n');
        } else {
          String prefix = isYearly ? '• 🔄 ' : isMonthly ? '• 📅 ' : '• ';
          message.write('$prefix$title$timeStr$priorityStars\n');
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
      _isInYearlyFolder = false;
      _isInNotesFolder = false;
      _isInDailyFolder = false;
      _isInMonthlyFolder = false;
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

  Widget _buildVirtualItem(Map<String, dynamic> item) {
    final type = item['type'] as String;

    if (type == 'yearly_folder') {
      return GestureDetector(
        onLongPress: () => showHelp(130),
        child: ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.refresh, color: clText, size: 20),
          ),
          title: Text(
            lw('Yearly Events'),
            style: TextStyle(
              fontWeight: fwBold,
              color: clText,
              fontSize: fsMedium,
            ),
          ),
          subtitle: FutureBuilder<int>(
            future: _getYearlyItemsCount(),
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return Text(
                '$count ${lw('items')}',
                style: TextStyle(color: clText, fontStyle: FontStyle.italic),
              );
            },
          ),
          trailing: Icon(Icons.folder_open, color: Colors.green),
          tileColor: clFill,
          onTap: () {
            _enterYearlyFolder();

            if (xvHiddenMode) {
              resetHiddenModeTimer();
            }
          },
        ),
      );
    } else if (type == 'notes_folder') {
      return GestureDetector(
        onLongPress: () => showHelp(132),
        child: ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.note, color: clText, size: 20),
          ),
          title: Text(
            lw('Notes'),
            style: TextStyle(
              fontWeight: fwBold,
              color: clText,
              fontSize: fsMedium,
            ),
          ),
          subtitle: FutureBuilder<int>(
            future: _getNotesItemsCount(),
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return Text(
                '$count ${lw('items')}',
                style: TextStyle(color: clText, fontStyle: FontStyle.italic),
              );
            },
          ),
          trailing: Icon(Icons.folder_open, color: Colors.blue),
          tileColor: clFill,
          onTap: () {
            _enterNotesFolder();

            if (xvHiddenMode) {
              resetHiddenModeTimer();
            }
          },
        ),
      );
    } else if (type == 'daily_folder') {
      return GestureDetector(
        onLongPress: () => showHelp(133),
        child: ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.orange,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.today, color: clText, size: 20),
          ),
          title: Text(
            lw('Daily Reminders'),
            style: TextStyle(
              fontWeight: fwBold,
              color: clText,
              fontSize: fsMedium,
            ),
          ),
          subtitle: FutureBuilder<int>(
            future: _getDailyItemsCount(),
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return Text(
                '$count ${lw('items')}',
                style: TextStyle(color: clText, fontStyle: FontStyle.italic),
              );
            },
          ),
          trailing: Icon(Icons.folder_open, color: Colors.orange),
          tileColor: clFill,
          onTap: () {
            _enterDailyFolder();

            if (xvHiddenMode) {
              resetHiddenModeTimer();
            }
          },
        ),
      );
    } else if (type == 'monthly_folder') {
      return GestureDetector(
        onLongPress: () => showHelp(134), // New help ID
        child: ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.purple,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.calendar_month, color: clText, size: 20),
          ),
          title: Text(
            lw('Monthly Events'),
            style: TextStyle(
              fontWeight: fwBold,
              color: clText,
              fontSize: fsMedium,
            ),
          ),
          subtitle: FutureBuilder<int>(
            future: _getMonthlyItemsCount(),
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return Text(
                '$count ${lw('items')}',
                style: TextStyle(color: clText, fontStyle: FontStyle.italic),
              );
            },
          ),
          trailing: Icon(Icons.folder_open, color: Colors.purple),
          tileColor: clFill,
          onTap: () {
            _enterMonthlyFolder();

            if (xvHiddenMode) {
              resetHiddenModeTimer();
            }
          },
        ),
      );
    }

    return SizedBox.shrink();
  }

  Future<void> _refreshItems() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final items = await getItems();

      // Добавляем виртуальные элементы
      List<Map<String, dynamic>> finalItems = [];

      if (_isInYearlyFolder) {
        // В папке Yearly - только ежегодные записи
        final yearlyItems = items.where((item) => item['yearly'] == 1).toList();
        finalItems.addAll(yearlyItems);

      } else if (_isInNotesFolder) {
        // В папке Notes - только записи без времени, не ежегодные и не daily
        final notesItems = items.where((item) =>
        item['time'] == null && item['yearly'] != 1 && item['daily'] != 1).toList();
        finalItems.addAll(notesItems);

      } else if (_isInDailyFolder) {
        // В папке Daily - только записи с ежедневными напоминаниями
        final dailyItems = items.where((item) => item['daily'] == 1).toList();
        finalItems.addAll(dailyItems);

      } else if (_isInMonthlyFolder) {
        // In Monthly folder - only monthly reminder records
        final monthlyItems = items.where((item) => item['monthly'] == 1).toList();
        finalItems.addAll(monthlyItems);

      } else {
        // На главном уровне - сначала обычные записи (исключаем yearly, daily и monthly)
        final normalItems = items.where((item) =>
        item['yearly'] != 1 && item['daily'] != 1 && item['monthly'] != 1 && item['time'] != null).toList();
        finalItems.addAll(normalItems);

        // Виртуальные папки в КОНЦЕ списка
        // Order: Notes → Daily → Monthly → Yearly
        final notesCount = await _getNotesItemsCount();
        if (notesCount > 0) {
          finalItems.add(_createNotesFolderItem());
        }

        final dailyCount = await _getDailyItemsCount();
        if (dailyCount > 0) {
          finalItems.add(_createDailyFolderItem());
        }

        final monthlyCount = await _getMonthlyItemsCount();
        if (monthlyCount > 0) {
          finalItems.add(_createMonthlyFolderItem());
        }

        final yearlyCount = await _getYearlyItemsCount();
        if (yearlyCount > 0) {
          finalItems.add(_createYearlyFolderItem());
        }
      }

      setState(() {
        _items = finalItems;
        _isLoading = false;
      });
      _updateFilterStatus();
    } catch (e) {
      myPrint('Error loading items: $e');
      setState(() {
        _items = [];
        _isLoading = false;
      });
    }
  }

  // Copy item function
  Future<void> _copyItem(int itemId) async {
    try {
      // Get item data from database
      final items = await mainDb.query(
        'items',
        where: 'id = ?',
        whereArgs: [itemId],
      );

      if (items.isEmpty) {
        okInfoBarRed(lw('Item not found'));
        return;
      }

      final originalItem = items.first;

      // Prepare new item data with "copy-" prefix
      String originalTitle = originalItem['title'] as String? ?? '';
      String newTitle = 'copy-$originalTitle';

      // Insert new item with all fields copied (without photos)
      final newItemId = await mainDb.insert('items', {
        'title': newTitle,
        'content': originalItem['content'],
        'tags': originalItem['tags'],
        'priority': originalItem['priority'],
        'date': originalItem['date'],
        'time': originalItem['time'],
        'remind': originalItem['remind'], // Copy reminder flag
        'created': dateTimeToYYYYMMDD(DateTime.now()),
        'remove': originalItem['remove'],
        'hidden': originalItem['hidden'],
        'yearly': originalItem['yearly'],
        'monthly': originalItem['monthly'],
        'daily': originalItem['daily'], // Copy daily flag
        'daily_times': originalItem['daily_times'],
        'daily_days': originalItem['daily_days'],
        'daily_sound': originalItem['daily_sound'],
        'sound': originalItem['sound'],
        'photo': null, // Don't copy photos
      });

      // Schedule reminders for copied item
      if (originalItem['remind'] == 1 && originalItem['date'] != null) {
        final date = yyyymmddToDateTime(originalItem['date'] as int);
        if (date != null) {
          await SimpleNotifications.scheduleSpecificReminder(
            newItemId,
            date,
            originalItem['time'] as int?,
          );
        }
      }

      if (originalItem['daily'] == 1) {
        final dailyTimes = parseDailyTimes(originalItem['daily_times']);
        await SimpleNotifications.updateDailyReminders(
          newItemId,
          true,
          dailyTimes,
          originalItem['daily_days'] as int? ?? 127,
          newTitle,
        );
      }

      _refreshItems();
      okInfoBarGreen(lw('Item copied'));
    } catch (e) {
      myPrint('Error copying item: $e');
      okInfoBarRed(lw('Failed to copy item'));
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
          leading: Icon(Icons.copy, color: clText),
          title: Text(lw('Copy'), style: TextStyle(color: clText)),
          onTap: () {
            Navigator.pop(context); // Close the menu
            _copyItem(item['id']);
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
                    // Delete item photo folder
                    await deleteItemPhotoDir(item['id']);

                    // Cancel specific reminder if it exists
                    await SimpleNotifications.cancelSpecificReminder(item['id']);

                    // Delete item from database
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
          onLongPress: () => showHelp(20),
          onTap: _handleMultipleTap,
          child: Row(
            children: [
              Text(
                _isInYearlyFolder ? lw('Yearly') :
                _isInNotesFolder ? lw('Notes') :
                _isInDailyFolder ? lw('Daily') :
                _isInMonthlyFolder ? lw('Monthly') :
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
          onLongPress: () => showHelp(21),
          child: IconButton(
            icon: Icon((_isInYearlyFolder || _isInNotesFolder || _isInDailyFolder || _isInMonthlyFolder) ? Icons.arrow_back : Icons.close),
            onPressed: () async {
              if (_isInYearlyFolder) {
                _exitYearlyFolder();
              } else if (_isInNotesFolder) {
                _exitNotesFolder();
              } else if (_isInDailyFolder) {
                _exitDailyFolder();
              } else if (_isInMonthlyFolder) {
                _exitMonthlyFolder();
              } else {
                await vacuumDatabases();
                Navigator.of(context).canPop()
                    ? Navigator.of(context).pop()
                    : SystemNavigator.pop();
              }
            },
          ),
        ),
        actions: [
          // Кнопка проверки напоминаний
          GestureDetector(
            onLongPress: () => showHelp(40),
            child: IconButton(
              icon: Icon(Icons.notifications),
              tooltip: lw('Check reminders'),
              onPressed: _checkReminders,
            ),
          ),
          // Индикатор состояния фильтра
          GestureDetector(
            onLongPress: () => showHelp(22),
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
          // Меню
          GestureDetector(
            onLongPress: () => showHelp(25),
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
                  Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (context) => FiltersScreen()),
                  ).then((needsRefresh) {
                    if (needsRefresh == true) {
                      _refreshItems();
                    }
                  });
                } else if (result == 'tag_filter') {
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
                      child: Text(
                        lw('Clear all filters'),
                        style: TextStyle(color: clText),
                      ),
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'filters',
                    child: GestureDetector(
                      onLongPress: () => showHelp(23),
                      child: Text(
                        lw('Filters'),
                        style: TextStyle(color: clText),
                      ),
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'tag_filter',
                    child: GestureDetector(
                      onLongPress: () => showHelp(24),
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
                      child: Text(lw('About'), style: TextStyle(color: clText)),
                    ),
                  ),
                ];

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
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? Center(
        child: Text(
          _isInYearlyFolder
              ? lw('No yearly events yet.')
              : _isInNotesFolder
              ? lw('No notes yet.')
              : _isInDailyFolder
              ? lw('No daily reminders yet.')
              : xvHiddenMode
              ? lw('No private items yet. Press + to add.')
              : lw('No items yet. Press + to add.'),
          style: TextStyle(color: clText, fontSize: fsMedium),
        ),
      )
          : ListView.builder(
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];

          // Обработка виртуальных элементов
          if (item['isVirtual'] == true) {
            return _buildVirtualItem(item);
          }

          // Остальной код ListView.builder остается без изменений
          final priorityValue = item['priority'] ?? 0;
          final hasDate = item['date'] != null && item['date'] != 0;
          final hasTime = item['time'] != null;
          final isReminder = item['remind'] == 1;
          final isYearly = item['yearly'] == 1;
          final isMonthly = item['monthly'] == 1;
          final photoPaths = parsePhotoPaths(item['photo']);
          final hasPhoto = photoPaths.isNotEmpty;
          final photoCount = photoPaths.length;

          final todayDate = dateTimeToYYYYMMDD(DateTime.now());
          final isToday = hasDate && item['date'] == todayDate;

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

          String? formattedTime;
          if (hasTime) {
            formattedTime = timeIntToString(item['time']);
            if (formattedTime == null) {
              myPrint('Warning: Could not format time: ${item['time']}');
            }
          }

          final String content = item['content'] ?? '';
          final String tags = item['tags'] ?? '';

          return Dismissible(
            key: Key('item_${item['id']}'),
            background: Container(
              color: clUpBar,
              alignment: Alignment.centerLeft,
              padding: EdgeInsets.only(left: 20),
              child: Icon(
                Icons.edit,
                color: clText,
                size: 30,
              ),
            ),
            secondaryBackground: Container(
              color: clRed,
              alignment: Alignment.centerRight,
              padding: EdgeInsets.only(right: 20),
              child: Icon(
                Icons.delete,
                color: Colors.white,
                size: 30,
              ),
            ),
            confirmDismiss: (direction) async {
              if (direction == DismissDirection.startToEnd) {
                Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EditItemPage(itemId: item['id']),
                  ),
                ).then((updated) {
                  if (updated == true) {
                    _refreshItems();
                  }
                });

                if (xvHiddenMode) {
                  resetHiddenModeTimer();
                }

                return false;

              } else if (direction == DismissDirection.endToStart) {
                final shouldDelete = await showCustomDialog(
                  title: lw('Delete Item'),
                  content: lw('Are you sure you want to delete this item?'),
                  actions: [
                    {'label': lw('Cancel'), 'value': false, 'isDestructive': false},
                    {'label': lw('Delete'), 'value': true, 'isDestructive': true},
                  ],
                );

                if (shouldDelete == true) {
                  try {
                    // Delete item photo folder
                    await deleteItemPhotoDir(item['id']);

                    await SimpleNotifications.cancelSpecificReminder(item['id']);

                    await mainDb.delete(
                      'items',
                      where: 'id = ?',
                      whereArgs: [item['id']],
                    );

                    _refreshItems();

                    if (xvHiddenMode) {
                      resetHiddenModeTimer();
                    }

                    return true;
                  } catch (e) {
                    myPrint('Error deleting item: $e');
                    okInfoBarRed(lw('Error deleting item'));
                    return false;
                  }
                } else {
                  return false;
                }
              }
              return false;
            },
            child: ListTile(
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
                        if (hasTime && formattedTime != null) ...[
                          SizedBox(width: 8),
                          Icon(Icons.notifications_active, color: clRed, size: 16),
                          SizedBox(width: 2),
                          Text(
                            formattedTime,
                            style: TextStyle(
                              fontSize: fsMedium,
                              color: clRed,
                              fontWeight: fwBold,
                            ),
                          ),
                        ],
                      ],
                    ),
                ],
              ),
              tileColor: _selectedItemId == item['id']
                  ? clSel
                  : isToday
                  ? Color(0x22FF0000)
                  : clFill,
              leading: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (xvHiddenMode)
                    Icon(Icons.lock, color: clText, size: 16),
                  if (priorityValue > 0) ...[
                    if (xvHiddenMode) SizedBox(height: 2),
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
                  if (isYearly && hasDate) ...[
                    SizedBox(height: 2),
                    Icon(
                      Icons.refresh,
                      color: isToday ? clRed : clText,
                      size: 16,
                    ),
                  ],
                  if (isMonthly && hasDate) ...[
                    SizedBox(height: 2),
                    Icon(
                      Icons.calendar_month,
                      color: isToday ? clRed : Colors.purple,
                      size: 16,
                    ),
                  ],
                ],
              ),
              trailing: hasPhoto
                  ? Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconButton(
                          icon: Icon(Icons.photo, color: isToday ? clRed : clText),
                          onPressed: () => _showPhotoGallery(photoPaths),
                        ),
                        if (photoCount > 1)
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              padding: EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: clUpBar,
                                shape: BoxShape.circle,
                              ),
                              constraints: BoxConstraints(
                                minWidth: 18,
                                minHeight: 18,
                              ),
                              child: Text(
                                photoCount.toString(),
                                style: TextStyle(
                                  color: clText,
                                  fontSize: 10,
                                  fontWeight: fwBold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    )
                  : null,
              onTap: () {
                setState(() {
                  _selectedItemId = item['id'];
                });

                if (xvHiddenMode) {
                  resetHiddenModeTimer();
                }
              },
              onLongPress: () {
                _showContextMenu(context, item);

                if (xvHiddenMode) {
                  resetHiddenModeTimer();
                }
              },
            ),
          );
        },
      ),
      floatingActionButton: GestureDetector(
        onLongPress: () => showHelp(29),
        child: FloatingActionButton(
          backgroundColor: xvHiddenMode ? Color(0xFFf29238) : clUpBar,
          foregroundColor: clText,
          onPressed: () async {
            if (xvHiddenMode) {
              resetHiddenModeTimer();
            }

            final result = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (context) => EditItemPage(),
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

// Photo Gallery Dialog Widget
class _PhotoGalleryDialog extends StatefulWidget {
  final List<String> photoPaths;
  final VoidCallback onClose;

  const _PhotoGalleryDialog({
    required this.photoPaths,
    required this.onClose,
  });

  @override
  _PhotoGalleryDialogState createState() => _PhotoGalleryDialogState();
}

class _PhotoGalleryDialogState extends State<_PhotoGalleryDialog> {
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final photoCount = widget.photoPaths.length;

    return Dialog(
      backgroundColor: clFill,
      insetPadding: EdgeInsets.symmetric(
        horizontal: screenSize.width * 0.05,
        vertical: screenSize.height * 0.05,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // AppBar with counter
          AppBar(
            backgroundColor: clUpBar,
            foregroundColor: clText,
            title: Text(
              photoCount > 1
                  ? '${lw('Photo')} ${_currentPage + 1} / $photoCount'
                  : lw('Photo'),
            ),
            leading: IconButton(
              icon: Icon(Icons.close),
              onPressed: widget.onClose,
            ),
          ),
          // Photo viewer
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxHeight: screenSize.height * 0.75,
                maxWidth: screenSize.width * 0.9,
              ),
              child: photoCount == 1
                  ? _buildSinglePhoto(widget.photoPaths[0])
                  : _buildPhotoPageView(),
            ),
          ),
          // Page indicators (dots) for multiple photos
          if (photoCount > 1)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(photoCount, (index) {
                  return Container(
                    margin: EdgeInsets.symmetric(horizontal: 4),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: index == _currentPage ? clUpBar : clText.withValues(alpha: 0.3),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSinglePhoto(String path) {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 5.0,
      constrained: true,
      scaleEnabled: true,
      panEnabled: true,
      boundaryMargin: EdgeInsets.all(20.0),
      child: Image.file(
        File(path),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return _buildErrorWidget(error);
        },
      ),
    );
  }

  Widget _buildPhotoPageView() {
    return PageView.builder(
      controller: _pageController,
      itemCount: widget.photoPaths.length,
      onPageChanged: (index) {
        setState(() {
          _currentPage = index;
        });
      },
      itemBuilder: (context, index) {
        return InteractiveViewer(
          minScale: 0.5,
          maxScale: 5.0,
          constrained: true,
          scaleEnabled: true,
          panEnabled: true,
          boundaryMargin: EdgeInsets.all(20.0),
          child: Image.file(
            File(widget.photoPaths[index]),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return _buildErrorWidget(error);
            },
          ),
        );
      },
    );
  }

  Widget _buildErrorWidget(Object error) {
    myPrint('Error loading image: $error');
    return Container(
      padding: EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error, size: 64, color: clRed),
          SizedBox(height: 16),
          Text(
            'Error loading image:\n$error',
            style: TextStyle(color: clText),
            textAlign: TextAlign.center,
          ),
        ],
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
