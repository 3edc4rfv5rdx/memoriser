// main.dart
import 'dart:async'; // For Timer
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

  // Store onUpgrade callback for reuse in backup restore
  mainDbOnUpgrade = _mainDbOnUpgrade;

  mainDb = await openDatabase(
    join(databasesPath, mainDbFile),
    version: mainDbVersion,
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
          sound TEXT DEFAULT NULL,
          fullscreen INTEGER DEFAULT 0,
          active INTEGER DEFAULT 1,
          period INTEGER DEFAULT 0,
          period_to INTEGER DEFAULT NULL,
          period_days INTEGER DEFAULT 127,
          loop_sound INTEGER DEFAULT 1
        )
      ''');
    },
    onUpgrade: _mainDbOnUpgrade,
  );

  settDb = await openDatabase(
    join(databasesPath, settDbFile),
    version: settDbVersion,
    onCreate: (db, version) {
      return db.execute(
        'CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT)',
      );
    },
  );
}

Future<void> _mainDbOnUpgrade(Database db, int oldVersion, int newVersion) async {
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

      if (oldVersion < 13) {
        // Migration for version 13 - add fullscreen field for fullscreen alert windows
        await db.execute('ALTER TABLE items ADD COLUMN fullscreen INTEGER DEFAULT 0');
        myPrint("Database upgraded to version 13: Added 'fullscreen' field");
      }

      if (oldVersion < 14) {
        // Migration for version 14 - add active field for quick reminder activation/deactivation
        await db.execute('ALTER TABLE items ADD COLUMN active INTEGER DEFAULT 1');
        myPrint("Database upgraded to version 14: Added 'active' field");
      }

      if (oldVersion < 15) {
        // Migration for version 15 - add period reminder fields
        await db.execute('ALTER TABLE items ADD COLUMN period INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE items ADD COLUMN period_to INTEGER DEFAULT NULL');
        await db.execute('ALTER TABLE items ADD COLUMN period_days INTEGER DEFAULT 127');
        myPrint("Database upgraded to version 15: Added period reminder fields");
      }

      if (oldVersion < 16) {
        // Migration for version 16 - add loop_sound field for repeating sound on fullscreen alerts
        await db.execute('ALTER TABLE items ADD COLUMN loop_sound INTEGER DEFAULT 1');
        myPrint("Database upgraded to version 16: Added 'loop_sound' field");
      }
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

// Function to get filter status text
// Optimized getItems() using SQL for sorting and LIMIT
// Fixed getItems() with correct SQL syntax

Future<List<Map<String, dynamic>>> getItems() async {
  try {
    // Get sort order from settings
    final newestFirst = await getSetting("Newest first") ?? defSettings["Newest first"];
    myPrint('Newest first setting: $newestFirst');

    // Get last items limit from settings
    final lastItemsStr = await getSetting("Last items") ?? defSettings["Last items"];
    final lastItems = int.tryParse(lastItemsStr) ?? 0;
    myPrint('Last items setting: $lastItems');

    // Get today's date in YYYYMMDD format
    final todayDate = dateTimeToYYYYMMDD(DateTime.now());
    myPrint('Today date: $todayDate');

    // Initial WHERE values
    List<String> whereConditions = [];
    List<dynamic> whereArgs = [];

    // Add hidden filter condition
    if (xvHiddenMode) {
      whereConditions.add('hidden = 1');
    } else {
      whereConditions.add('(hidden = 0 OR hidden IS NULL)');
    }

    // Tag Cloud filter: AND logic (items must have ALL selected tags)
    if (xvTagFilter.isNotEmpty) {
      myPrint('Tag filter is active: $xvTagFilter');

      // Split tag string into individual tags
      List<String> tagFilters = xvTagFilter.split(',').map((tag) => tag.trim()).toList();

      if (xvHiddenMode) {
        for (String tag in tagFilters) {
          String obfuscatedTag = obfuscateText(tag);
          // Exact tag match: wrap in commas, trim spaces around commas
          whereConditions.add("(',' || REPLACE(tags, ', ', ',') || ',') LIKE ?");
          whereArgs.add('%,$obfuscatedTag,%');
        }
      } else {
        for (String tag in tagFilters) {
          // Exact tag match: wrap in commas, trim spaces around commas
          whereConditions.add("(',' || REPLACE(tags, ', ', ',') || ',') LIKE ?");
          whereArgs.add('%,$tag,%');
        }
      }
    }

    // Virtual folder SQL filtering — filter by type directly in SQL
    bool isVirtualFolder = false;
    const virtualFolderFilters = {
      'notes:true', 'yearly:true', 'daily:true', 'monthly:true', 'period:true'
    };
    if (virtualFolderFilters.contains(xvFilter)) {
      isVirtualFolder = true;
      switch (xvFilter) {
        case 'yearly:true':
          whereConditions.add('yearly = 1');
          break;
        case 'daily:true':
          whereConditions.add('daily = 1');
          break;
        case 'monthly:true':
          whereConditions.add('monthly = 1');
          break;
        case 'period:true':
          whereConditions.add('period = 1');
          break;
        case 'notes:true':
          whereConditions.add('time IS NULL AND yearly != 1 AND (daily != 1 OR daily IS NULL) AND (monthly != 1 OR monthly IS NULL) AND (period != 1 OR period IS NULL)');
          break;
      }
    }

    // Parse user-set filter string
    if (xvFilter.isNotEmpty && !isVirtualFolder) {
      myPrint('Main filter is active: $xvFilter');

      // Split filter string into parts
      List<String> filterParts = xvFilter.split('|');

      for (String part in filterParts) {
        // Split on first colon only to handle values containing colons
        final colonIndex = part.indexOf(':');
        if (colonIndex < 0) continue;

        String key = part.substring(0, colonIndex);
        String value = part.substring(colonIndex + 1);

        switch (key) {
          case 'dateFrom':
            if (value.isNotEmpty) {
              try {
                final date = DateFormat(ymdDateFormat).parse(value);
                final dateValue = dateTimeToYYYYMMDD(date);
                // Include period items where period_to >= dateFrom
                whereConditions.add('(date IS NOT NULL AND (date >= ? OR (period_to IS NOT NULL AND period_to >= ?)))');
                whereArgs.add(dateValue);
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
              if (value.toLowerCase() == 'true') {
                // Match any reminder type: one-time, daily, or period
                whereConditions.add('(remind = 1 OR daily = 1 OR period = 1)');
              } else {
                whereConditions.add('(remind != 1 OR remind IS NULL) AND (daily != 1 OR daily IS NULL) AND (period != 1 OR period IS NULL)');
              }
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
                  String obfuscatedTag = obfuscateText(tag);
                  tagConditions.add("(',' || REPLACE(tags, ', ', ',') || ',') LIKE ?");
                  whereArgs.add('%,$obfuscatedTag,%');
                } else {
                  tagConditions.add("(',' || REPLACE(tags, ', ', ',') || ',') LIKE ?");
                  whereArgs.add('%,$tag,%');
                }
              }

              // Filters screen tags: OR logic (items with ANY of the tags)
              if (tagConditions.isNotEmpty) {
                whereConditions.add('(${tagConditions.join(' OR ')})');
              }
            }
            break;
        }
      }
    }

    // Build final WHERE clause
    String whereClause = whereConditions.isEmpty ? "" : "WHERE ${whereConditions.join(' AND ')}";

    // Define sort direction multiplier (-1 for DESC, 1 for ASC)
    // SQLite doesn't allow DESC/ASC in CASE expressions,
    // so we use a multiplier to change sort direction
    final dateFactor = newestFirst == "true" ? "-1" : "1";
    final createdFactor = newestFirst == "true" ? "-1" : "1";

    // Build ORDER BY string with correct SQLite syntax
    // Instead of using DESC/ASC in expressions, multiply values by -1 for reverse sort
    String orderByClause =
        "CASE WHEN date = $todayDate THEN 1 WHEN date IS NOT NULL AND date > 0 THEN 2 ELSE 3 END ASC, " "priority DESC, " "CASE WHEN date = $todayDate THEN 0 WHEN date IS NOT NULL AND date > 0 THEN $dateFactor * date ELSE 0 END, " "CASE WHEN date IS NULL OR date = 0 THEN $createdFactor * created ELSE 0 END";

    // Build full SQL query
    String sqlQuery = "SELECT * FROM items $whereClause ORDER BY $orderByClause";

    // Apply LIMIT only on main screen, not inside virtual folders
    if (lastItems > 0 && !isVirtualFolder) {
      sqlQuery += " LIMIT $lastItems";
    }

    // Execute query
    List<Map<String, dynamic>> result = await mainDb.rawQuery(sqlQuery, whereArgs);

    // Process obfuscated records if in hidden mode
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
      where: 'date IS NOT NULL AND date < ? AND remove = 1 AND (yearly = 0 OR yearly IS NULL) AND (monthly = 0 OR monthly IS NULL) AND (period = 0 OR period IS NULL)',
      whereArgs: [todayInt],
    );

    myPrint('Found ${expiredItems.length} expired items to delete');

    // Delete photo folders and cancel alarms for expired items
    int deletedFolders = 0;
    for (var item in expiredItems) {
      final itemId = item['id'] as int;
      try {
        await deleteItemPhotoDir(itemId);
        await SimpleNotifications.cancelSpecificReminder(itemId);
        await SimpleNotifications.cancelAllDailyReminders(itemId);
        await SimpleNotifications.cancelPeriodReminders(itemId);
        deletedFolders++;
      } catch (e) {
        myPrint('Error cleaning up expired item $itemId: $e');
      }
    }

    // Now delete the expired records from database
    final count = await mainDb.rawDelete(
        'DELETE FROM items WHERE date IS NOT NULL AND date < ? AND remove = 1 AND (yearly = 0 OR yearly IS NULL) AND (monthly = 0 OR monthly IS NULL) AND (period = 0 OR period IS NULL)',
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

        // Advance year until date is >= today (handles multi-year gaps)
        var newDate = oldDate;
        final todayDate = yyyymmddToDateTime(today)!;
        while (newDate.isBefore(todayDate)) {
          newDate = DateTime(newDate.year + 1, newDate.month, newDate.day);
        }
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

        // Advance month until date is >= today (handles multi-month gaps)
        // Extract original day directly from YYYYMMDD to preserve day 31 etc.
        int targetDay = oldDateInt % 100;
        int newYear = oldDate.year;
        int newMonth = oldDate.month;
        final todayDate = yyyymmddToDateTime(today)!;
        DateTime newDate = oldDate;
        while (newDate.isBefore(todayDate)) {
          newMonth++;
          if (newMonth > 12) {
            newMonth = 1;
            newYear++;
          }
          int daysInNewMonth = DateTime(newYear, newMonth + 1, 0).day;
          int actualDay = targetDay > daysInNewMonth ? daysInNewMonth : targetDay;
          newDate = DateTime(newYear, newMonth, actualDay);
        }
        // Store with original target day to preserve intent (e.g. 31)
        final newDateInt = newYear * 10000 + newMonth * 100 + targetDay;

        await mainDb.update(
          'items',
          {'date': newDateInt},
          where: 'id = ?',
          whereArgs: [eventId],
        );

        myPrint('Updated monthly event $eventId: $oldDateInt -> $newDateInt');
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
  // Load debug logs setting from DB (overrides hardcoded default)
  final debugLogsValue = await getSetting("Debug logs") ?? defSettings["Debug logs"];
  xvDebug = debugLogsValue == "true";
  // Initialize notification system
  await SimpleNotifications.initNotifications();

  // Reminders are preserved in Android AlarmManager - no need to reschedule on every app start
  // Rescheduling happens only when:
  // 1. User changes reminder settings
  // 2. User restores from backup
  // 3. Device reboots (handled by BootReceiver)

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
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  int? _selectedItemId; // Track the selected item
  String _filterStatus = '(All) ';

  // Variables for multiple tap handling
  int _tapCount = 0;
  Timer? _tapTimer;
  bool _isInYearlyFolder = false;
  bool _isInNotesFolder = false;
  bool _isInDailyFolder = false;
  bool _isInMonthlyFolder = false;
  bool _isInPeriodFolder = false;
  String _savedUserFilter = ''; // Preserve user filter when entering virtual folders

  @override
  void initState() {
    super.initState();
    _refreshItems();
    _updateFilterStatus(); // Update filter status on startup
  }

  @override
  void dispose() {
    _tapTimer?.cancel();
    super.dispose();
  }

  void _enterVirtualFolder({
    bool notes = false, bool yearly = false, bool daily = false,
    bool monthly = false, bool period = false,
  }) {
    setState(() {
      _savedUserFilter = xvFilter;
      _isInNotesFolder = notes;
      _isInYearlyFolder = yearly;
      _isInDailyFolder = daily;
      _isInMonthlyFolder = monthly;
      _isInPeriodFolder = period;
      xvFilter = notes ? 'notes:true' : yearly ? 'yearly:true' : daily ? 'daily:true' : monthly ? 'monthly:true' : 'period:true';
    });
    _refreshItems();
    _updateFilterStatus();
  }

  void _exitVirtualFolder() {
    setState(() {
      _isInNotesFolder = false;
      _isInYearlyFolder = false;
      _isInDailyFolder = false;
      _isInMonthlyFolder = false;
      _isInPeriodFolder = false;
      xvFilter = _savedUserFilter; // Restore user filter
      _savedUserFilter = '';
    });
    _refreshItems();
    _updateFilterStatus();
  }

  Map<String, dynamic> _createYearlyFolderItem() {
    return {
      'id': -2, // Special ID for virtual element
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
      'id': -3, // Special ID for virtual element
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
      'id': -4, // Special ID for virtual element
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

  // Count items matching type condition, respecting active tag filter
  Future<int> _getFolderItemsCount(String typeCondition) async {
    try {
      String hiddenCond = xvHiddenMode ? 'hidden = 1' : '(hidden = 0 OR hidden IS NULL)';
      String where = '$typeCondition AND $hiddenCond';
      List<dynamic> args = [];

      // Apply active tag filter to folder counts
      if (xvTagFilter.isNotEmpty) {
        List<String> tags = xvTagFilter.split(',').map((t) => t.trim()).toList();
        for (String tag in tags) {
          String searchTag = xvHiddenMode ? obfuscateText(tag) : tag;
          where += " AND (',' || REPLACE(tags, ', ', ',') || ',') LIKE ?";
          args.add('%,$searchTag,%');
        }
      }

      final count = await mainDb.rawQuery(
        'SELECT COUNT(*) as count FROM items WHERE $where', args,
      );
      return count.isNotEmpty ? (count.first['count'] as int? ?? 0) : 0;
    } catch (e) {
      myPrint('Error counting items ($typeCondition): $e');
      return 0;
    }
  }

  Future<int> _getYearlyItemsCount() => _getFolderItemsCount('yearly = 1');
  Future<int> _getNotesItemsCount() => _getFolderItemsCount(
    'time IS NULL AND yearly != 1 AND (daily != 1 OR daily IS NULL) AND (monthly != 1 OR monthly IS NULL) AND (period != 1 OR period IS NULL)');
  Future<int> _getDailyItemsCount() => _getFolderItemsCount('daily = 1');
  Future<int> _getMonthlyItemsCount() => _getFolderItemsCount('monthly = 1');

  Map<String, dynamic> _createPeriodFolderItem() {
    return {
      'id': -6,
      'isVirtual': true,
      'type': 'period_folder',
      'title': lw('Periods'),
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

  Future<int> _getPeriodItemsCount() => _getFolderItemsCount('period = 1');

  // Format period date range for display (e.g. "15 - 20" or "2026-02-15 - 2026-02-20")
  String _formatPeriodRange(int? dateFrom, int? dateTo) {
    if (dateFrom == null && dateTo == null) return '—';
    String fromStr;
    String toStr;
    if (dateFrom != null && dateFrom > 31) {
      fromStr = dateIntToStr(dateFrom);
    } else {
      fromStr = (dateFrom ?? 0).toString();
    }
    if (dateTo != null && dateTo > 31) {
      toStr = dateIntToStr(dateTo);
    } else {
      toStr = (dateTo ?? 0).toString();
    }
    return '$fromStr — $toStr';
  }

  void _showPhotoGallery(List<String> photoPaths, {int? itemId}) {
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
              final targetId = itemId ?? _selectedItemId;
              if (targetId != null) {
                await mainDb.update(
                  'items',
                  {'photo': null},
                  where: 'id = ?',
                  whereArgs: [targetId],
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

  // Multiple tap handler
  void _handleMultipleTap() {
    _tapCount++;

    if (_tapCount == 1) {
      // On first tap, start the timer
      _tapTimer?.cancel();
      _tapTimer = Timer(Duration(milliseconds: 800), () {
        // If timer expired, reset counter
        _tapCount = 0;
      });
    } else if (_tapCount >= 4) {
      // On fourth tap, enter hidden mode
      _tapCount = 0;
      _tapTimer?.cancel();
      _showPinDialog();
    }
  }

  // _showPinDialog method uses this.context
  void _showPinDialog() async {
    // Check if PIN is already set
    bool hasPIN = await isPinSet();

    if (hasPIN) {
      // If PIN is set, show login dialog
      _showEnterPinDialog();
    } else {
      // If PIN is not set, show create PIN dialog
      _showCreatePinDialog();
    }
  }

  // Dialog for creating a new PIN code
  void _showCreatePinDialog() {
    final TextEditingController pinController = TextEditingController();
    final FocusNode focusNode = FocusNode();

    showDialog(
      context: this.context,
      barrierDismissible: false,
      builder: (dialogContext) {
        // Use Future.delayed for reliable focus setting
        Future.delayed(Duration.zero, () {
          if (dialogContext.mounted) {
            FocusScope.of(dialogContext).requestFocus(focusNode);
          }
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
                // Add autofocus property
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
                // Get PIN from controller
                final pin = pinController.text;

                // Verify PIN is 4 digits
                if (pin.length == 4 && int.tryParse(pin) != null) {
                  Navigator.pop(dialogContext);

                  // Save PIN code
                  await saveNewPin(pin);

                  // Activate hidden records mode
                  setState(() {
                    xvHiddenMode = true;
                    currentPin = pin;
                  });

                  // Refresh items list to show hidden ones
                  _refreshItems();

                  // Start auto-logout timer
                  resetHiddenModeTimer();

                  // Show confirmation
                  okInfoBarGreen(lw('Private mode activated'));
                } else {
                  // Show error if PIN format is invalid
                  okInfoBarRed(lw('PIN must be 4 digits'));
                }
              },
            ),
          ],
        );
      },
    );
  }

  // Dialog for entering existing PIN code
  void _showEnterPinDialog() {
    String enteredPin = '';
    final TextEditingController pinController = TextEditingController();
    final FocusNode focusNode = FocusNode();

    showDialog(
      context: this.context,
      barrierDismissible: false,
      builder: (dialogContext) {
        // Use Future.delayed instead of addPostFrameCallback
        Future.delayed(Duration.zero, () {
          if (dialogContext.mounted) {
            FocusScope.of(dialogContext).requestFocus(focusNode);
          }
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
                // Verify PIN code
                if (await verifyPin(enteredPin)) {
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }

                  // Activate hidden records mode
                  setState(() {
                    xvHiddenMode = true;
                    currentPin = enteredPin;
                  });

                  // Refresh items list to show hidden ones
                  _refreshItems();

                  // Start auto-logout timer
                  resetHiddenModeTimer();

                  // Show confirmation
                  okInfoBarGreen(lw('Private mode activated'));
                } else {
                  // Show error if PIN is incorrect
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }
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
      _savedUserFilter = '';
      _isInYearlyFolder = false;
      _isInNotesFolder = false;
      _isInDailyFolder = false;
      _isInMonthlyFolder = false;
      _isInPeriodFolder = false;
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
            _enterVirtualFolder(yearly: true);

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
            _enterVirtualFolder(notes: true);

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
            _enterVirtualFolder(daily: true);

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
            _enterVirtualFolder(monthly: true);

            if (xvHiddenMode) {
              resetHiddenModeTimer();
            }
          },
        ),
      );
    } else if (type == 'period_folder') {
      return GestureDetector(
        onLongPress: () => showHelp(135),
        child: ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.teal,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.date_range, color: clText, size: 20),
          ),
          title: Text(
            lw('Periods'),
            style: TextStyle(
              fontWeight: fwBold,
              color: clText,
              fontSize: fsMedium,
            ),
          ),
          subtitle: FutureBuilder<int>(
            future: _getPeriodItemsCount(),
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return Text(
                '$count ${lw('items')}',
                style: TextStyle(color: clText, fontStyle: FontStyle.italic),
              );
            },
          ),
          trailing: Icon(Icons.folder_open, color: Colors.teal),
          tileColor: clFill,
          onTap: () {
            _enterVirtualFolder(period: true);

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

      // Add virtual elements
      List<Map<String, dynamic>> finalItems = [];

      if (_isInYearlyFolder) {
        // Yearly folder - sort by date/time ASC (nearest first)
        // SQL already filters by yearly=1
        final yearlyItems = items.toList();
        yearlyItems.sort((a, b) {
          final dateA = a['date'] as int? ?? 99999999;
          final dateB = b['date'] as int? ?? 99999999;
          if (dateA != dateB) return dateA.compareTo(dateB);
          final timeA = a['time'] as int? ?? 0;
          final timeB = b['time'] as int? ?? 0;
          return timeA.compareTo(timeB);
        });
        finalItems.addAll(yearlyItems);

      } else if (_isInNotesFolder) {
        // Notes folder - sort by created date (respect "Newest first" setting)
        // SQL already filters notes type
        final notesItems = items.toList();
        final newestFirst = await getSetting("Newest first") ?? defSettings["Newest first"];
        notesItems.sort((a, b) {
          final dateA = a['date'] as int?;
          final dateB = b['date'] as int?;
          final hasDateA = dateA != null && dateA > 0;
          final hasDateB = dateB != null && dateB > 0;
          // Items with date come first, items without date go to the bottom
          if (hasDateA && !hasDateB) return -1;
          if (!hasDateA && hasDateB) return 1;
          if (hasDateA && hasDateB) {
            // Both have dates: sort by date (respect "Newest first" setting)
            if (dateA != dateB) {
              return newestFirst == "true"
                  ? dateB!.compareTo(dateA!)
                  : dateA!.compareTo(dateB!);
            }
          }
          if (!hasDateA && !hasDateB) {
            // Both without date: sort alphabetically by title
            final titleA = (a['title'] as String?) ?? '';
            final titleB = (b['title'] as String?) ?? '';
            return titleA.toLowerCase().compareTo(titleB.toLowerCase());
          }
          // Same date: sort alphabetically by title
          final titleA = (a['title'] as String?) ?? '';
          final titleB = (b['title'] as String?) ?? '';
          return titleA.toLowerCase().compareTo(titleB.toLowerCase());
        });
        finalItems.addAll(notesItems);

      } else if (_isInDailyFolder) {
        // Daily folder - sort by first daily time ASC
        final dailyItems = items.toList();
        dailyItems.sort((a, b) {
          final timesA = parseDailyTimes(a['daily_times']);
          final timesB = parseDailyTimes(b['daily_times']);
          final firstA = timesA.isNotEmpty ? timesA.first : '99:99';
          final firstB = timesB.isNotEmpty ? timesB.first : '99:99';
          return firstA.compareTo(firstB);
        });
        finalItems.addAll(dailyItems);

      } else if (_isInMonthlyFolder) {
        // Monthly folder - sort by date ASC (nearest first), then time ASC
        final monthlyItems = items.toList();
        monthlyItems.sort((a, b) {
          final dateA = a['date'] as int? ?? 99999999;
          final dateB = b['date'] as int? ?? 99999999;
          if (dateA != dateB) return dateA.compareTo(dateB);
          final timeA = a['time'] as int? ?? 0;
          final timeB = b['time'] as int? ?? 0;
          return timeA.compareTo(timeB);
        });
        finalItems.addAll(monthlyItems);

      } else if (_isInPeriodFolder) {
        // Period folder - sort by date (from) ASC, then time ASC
        final periodItems = items.toList();
        periodItems.sort((a, b) {
          final dateA = a['date'] as int? ?? 99999999;
          final dateB = b['date'] as int? ?? 99999999;
          if (dateA != dateB) return dateA.compareTo(dateB);
          final timeA = a['time'] as int? ?? 0;
          final timeB = b['time'] as int? ?? 0;
          return timeA.compareTo(timeB);
        });
        finalItems.addAll(periodItems);

      } else {
        // Main level - exclude yearly, daily, monthly, and period items
        final normalItems = items.where((item) =>
        item['yearly'] != 1 && item['daily'] != 1 && item['monthly'] != 1 && item['period'] != 1 && item['time'] != null).toList();
        finalItems.addAll(normalItems);

        // Virtual folders at the END of the list
        // Order: Notes → Daily → Periods → Monthly → Yearly
        final notesCount = await _getNotesItemsCount();
        if (notesCount > 0) {
          finalItems.add(_createNotesFolderItem());
        }

        final dailyCount = await _getDailyItemsCount();
        if (dailyCount > 0) {
          finalItems.add(_createDailyFolderItem());
        }

        final periodCount = await _getPeriodItemsCount();
        if (periodCount > 0) {
          finalItems.add(_createPeriodFolderItem());
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

  // Toggle reminder active/inactive
  Future<void> _toggleReminderActive(int itemId, bool newActiveState) async {
    try {
      // Update active field in database
      await mainDb.update(
        'items',
        {'active': newActiveState ? 1 : 0},
        where: 'id = ?',
        whereArgs: [itemId],
      );

      // Get item data to check reminder types
      final items = await mainDb.query(
        'items',
        where: 'id = ?',
        whereArgs: [itemId],
      );

      if (items.isEmpty) return;
      final item = items.first;

      final hasRemind = item['remind'] == 1;
      final hasDaily = item['daily'] == 1;
      final hasPeriod = item['period'] == 1;
      final dateInt = item['date'] as int?;
      final date = dateInt != null ? yyyymmddToDateTime(dateInt) : null;
      final time = item['time'] as int?;
      final dailyTimes = parseDailyTimes(item['daily_times']);
      final dailyDays = (item['daily_days'] as int?) ?? dayAllDays;
      final title = (item['title'] as String?) ?? '';

      if (newActiveState) {
        // Activate: reschedule reminders
        if (hasRemind && date != null) {
          await SimpleNotifications.updateSpecificReminder(itemId, true, date, time);
          myPrint('Reminder reactivated for item $itemId');
        }
        if (hasDaily && dailyTimes.isNotEmpty) {
          await SimpleNotifications.updateDailyReminders(itemId, true, dailyTimes, dailyDays, title);
          myPrint('Daily reminders reactivated for item $itemId');
        }
        if (hasPeriod) {
          final periodFrom = item['date'] as int?;
          final periodTo = item['period_to'] as int?;
          final periodDays = (item['period_days'] as int?) ?? dayAllDays;
          await SimpleNotifications.updatePeriodReminders(itemId, true, periodFrom, periodTo, time, periodDays, title);
          myPrint('Period reminders reactivated for item $itemId');
        }
        okInfoBarGreen(lw('Reminder activated'));
      } else {
        // Deactivate: cancel all reminders
        if (hasRemind) {
          await SimpleNotifications.updateSpecificReminder(itemId, false, null, null);
          myPrint('Reminder cancelled for item $itemId');
        }
        if (hasDaily) {
          await SimpleNotifications.updateDailyReminders(itemId, false, [], dayAllDays, title);
          myPrint('Daily reminders cancelled for item $itemId');
        }
        if (hasPeriod) {
          await SimpleNotifications.cancelPeriodReminders(itemId);
          myPrint('Period reminders cancelled for item $itemId');
        }
        okInfoBarGreen(lw('Reminder deactivated'));
      }

      // Refresh UI
      _refreshItems();
    } catch (e) {
      myPrint('Error toggling reminder active state: $e');
      okInfoBarRed(lw('Error'));
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
      await mainDb.insert('items', {
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
        'active': 0, // Set inactive - user will activate manually
        'fullscreen': originalItem['fullscreen'], // Copy fullscreen flag
        'period': originalItem['period'],
        'period_to': originalItem['period_to'],
        'period_days': originalItem['period_days'],
        'loop_sound': originalItem['loop_sound'],
        'photo': null, // Don't copy photos
      });

      // Don't schedule reminders for copied item - it's a draft template
      // User will edit and save it, which will trigger scheduling

      _refreshItems();
      okInfoBarGreen(lw('Item copied'));
    } catch (e) {
      myPrint('Error copying item: $e');
      okInfoBarRed(lw('Failed to copy item'));
    }
  }

  Offset _lastTapPosition = Offset.zero;

  void _showContextMenu(BuildContext context, Map<String, dynamic> item) {
    List<PopupMenuEntry> menuItems = [
      PopupMenuItem(
        child: ListTile(
          leading: Icon(Icons.edit, color: clText),
          title: Text(lw('Edit'), style: TextStyle(color: clText)),
          onTap: () {
            Navigator.pop(context); // Close the menu
            // Navigate to edit page, pass only ID
            Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder:
                    (context) => EditItemPage(
                      itemId: item['id'], // Pass only ID
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

                    // Cancel all reminders for this item
                    await SimpleNotifications.cancelSpecificReminder(item['id']);
                    await SimpleNotifications.cancelAllDailyReminders(item['id']);
                    await SimpleNotifications.cancelPeriodReminders(item['id']);

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

    // If in hidden mode, add exit option
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
      position: RelativeRect.fromLTRB(
        _lastTapPosition.dx,
        _lastTapPosition.dy,
        _lastTapPosition.dx,
        _lastTapPosition.dy,
      ),
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
                _isInPeriodFolder ? lw('Periods') :
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
            icon: Icon((_isInYearlyFolder || _isInNotesFolder || _isInDailyFolder || _isInMonthlyFolder || _isInPeriodFolder) ? Icons.arrow_back : Icons.close),
            onPressed: () async {
              if (_isInYearlyFolder || _isInNotesFolder || _isInDailyFolder || _isInMonthlyFolder || _isInPeriodFolder) {
                _exitVirtualFolder();
              } else {
                await vacuumDatabases();
                if (!mounted) return;
                // ignore: use_build_context_synchronously
                if (Navigator.of(context).canPop()) {
                  // ignore: use_build_context_synchronously
                  Navigator.of(context).pop();
                } else {
                  SystemNavigator.pop();
                }
              }
            },
          ),
        ),
        actions: [
          // Check reminders button
          GestureDetector(
            onLongPress: () => showHelp(40),
            child: IconButton(
              icon: Icon(Icons.notifications),
              tooltip: lw('Check reminders'),
              onPressed: _checkReminders,
            ),
          ),
          // Filter status indicator
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
          // Menu
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
                  // Exit virtual folder before opening filters
                  final wasInVirtualFolder = _isInYearlyFolder || _isInNotesFolder || _isInDailyFolder || _isInMonthlyFolder || _isInPeriodFolder;
                  if (wasInVirtualFolder) {
                    _exitVirtualFolder();
                  }
                  Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (context) => FiltersScreen()),
                  ).then((needsRefresh) {
                    if (needsRefresh == true) {
                      _refreshItems();
                    }
                  });
                } else if (result == 'tag_filter') {
                  // Exit virtual folder before opening tag filter
                  if (_isInYearlyFolder || _isInNotesFolder || _isInDailyFolder || _isInMonthlyFolder || _isInPeriodFolder) {
                    _exitVirtualFolder();
                  }
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
              : _isInMonthlyFolder
              ? lw('No monthly events yet.')
              : _isInPeriodFolder
              ? lw('No period reminders yet.')
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

          // Handle virtual elements
          if (item['isVirtual'] == true) {
            return _buildVirtualItem(item);
          }

          // Rest of ListView.builder code remains unchanged
          final priorityValue = item['priority'] ?? 0;
          final hasDate = item['date'] != null && item['date'] != 0;
          final hasTime = item['time'] != null;
          final isReminder = item['remind'] == 1;
          final isYearly = item['yearly'] == 1;
          final isMonthly = item['monthly'] == 1;
          final isDaily = item['daily'] == 1;
          final isPeriod = item['period'] == 1;
          final isActive = item['active'] == 1;
          final hasAnyReminder = isReminder || isDaily || isPeriod;
          final photoPaths = parsePhotoPaths(item['photo']);
          final hasPhoto = photoPaths.isNotEmpty;
          final photoCount = photoPaths.length;

          // Parse daily times for display
          final dailyTimes = isDaily ? parseDailyTimes(item['daily_times']) : <String>[];
          final dailyTimesFormatted = dailyTimes.isNotEmpty
              ? dailyTimes.join(', ')
              : null;

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

                    // Cancel all reminders for this item
                    await SimpleNotifications.cancelSpecificReminder(item['id']);
                    await SimpleNotifications.cancelAllDailyReminders(item['id']);
                    await SimpleNotifications.cancelPeriodReminders(item['id']);

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
            child: Listener(
              onPointerDown: (event) {
                _lastTapPosition = event.position;
              },
              child: ListTile(
              // Leading: checkbox on title level (for reminders only)
              leading: hasAnyReminder
                  ? SizedBox(
                      width: 32,
                      height: 32,
                      child: Checkbox(
                        value: isActive,
                        activeColor: Colors.green,
                        checkColor: clText,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        onChanged: (value) async {
                          await _toggleReminderActive(item['id'], value ?? false);
                        },
                      ),
                    )
                  : null,
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      item['title'] ?? '',
                      style: TextStyle(
                        fontWeight: fwBold,
                        color: isToday ? clRed : clText,
                      ),
                    ),
                  ),
                  // Priority stars on the right
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
                  // Content with inline icons
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (xvHiddenMode) ...[
                        Icon(Icons.lock, color: clText, size: 14),
                        SizedBox(width: 4),
                      ],
                      if (isYearly) ...[
                        Icon(Icons.refresh, color: Colors.green, size: 14),
                        SizedBox(width: 4),
                      ],
                      if (isMonthly) ...[
                        Icon(Icons.calendar_month, color: Colors.purple, size: 14),
                        SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(content, style: TextStyle(color: isToday ? clRed : clText)),
                      ),
                    ],
                  ),
                  if (tags.isNotEmpty)
                    Text(
                      'Tags: $tags',
                      style: TextStyle(
                        fontSize: fsNormal,
                        color: isToday ? clRed : clText,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  if (hasDate && formattedDate != null && !isPeriod)
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
                  // Daily reminder days
                  if (isDaily)
                    Row(
                      children: [
                        Icon(Icons.calendar_today, color: Colors.blue, size: 16),
                        SizedBox(width: 4),
                        Text(
                          getDaysCompact((item['daily_days'] as int?) ?? dayAllDays),
                          style: TextStyle(
                            fontSize: fsMedium,
                            color: Colors.blue,
                            fontWeight: fwBold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  // Daily reminder times
                  if (isDaily && dailyTimesFormatted != null)
                    Row(
                      children: [
                        Icon(Icons.access_time, color: Colors.blue, size: 16),
                        SizedBox(width: 4),
                        Text(
                          dailyTimesFormatted,
                          style: TextStyle(
                            fontSize: fsMedium,
                            color: Colors.blue,
                            fontWeight: fwBold,
                          ),
                        ),
                      ],
                    ),
                  // Period reminder: date range
                  if (isPeriod) ...[
                    Row(
                      children: [
                        Icon(Icons.date_range, color: Colors.teal, size: 16),
                        SizedBox(width: 4),
                        Text(
                          _formatPeriodRange(item['date'] as int?, item['period_to'] as int?),
                          style: TextStyle(
                            fontSize: fsMedium,
                            color: Colors.teal,
                            fontWeight: fwBold,
                          ),
                        ),
                        if (hasTime && formattedTime != null) ...[
                          SizedBox(width: 8),
                          Icon(Icons.access_time, color: Colors.teal, size: 16),
                          SizedBox(width: 2),
                          Text(
                            formattedTime,
                            style: TextStyle(
                              fontSize: fsMedium,
                              color: Colors.teal,
                              fontWeight: fwBold,
                            ),
                          ),
                        ],
                      ],
                    ),
                    Row(
                      children: [
                        Icon(Icons.calendar_today, color: Colors.teal, size: 16),
                        SizedBox(width: 4),
                        Text(
                          getDaysCompact((item['period_days'] as int?) ?? dayAllDays),
                          style: TextStyle(
                            fontSize: fsMedium,
                            color: Colors.teal,
                            fontWeight: fwBold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              tileColor: _selectedItemId == item['id']
                  ? clSel
                  : isToday
                  ? Color(0x22FF0000)
                  : clFill,
              trailing: hasPhoto
                  ? Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconButton(
                          icon: Icon(Icons.photo, color: isToday ? clRed : clText),
                          onPressed: () => _showPhotoGallery(photoPaths, itemId: item['id']),
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
            '${lw('Error loading image')}:\n$error',
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
