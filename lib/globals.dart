// globals.dart
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';


const String progVersion = '0.0.250306';
const String progAuthor = 'Eugen';

const String mainDbFile = 'memorizer.db';  // Changed from mainDbFile
const String settDbFile = 'settings.db';

// Global variables
late Database mainDb;
late Database settDb;
late BuildContext globalContext;

bool xvDebug = true;

// Font sizes
const double fsSmall = 10;
const double fsNormal = 12;
const double fsMedium = 14;
const double fsLarge = 16;
const double fsXLarge = 18;
const double fsHeader = 22;

// Theme names
const List<String> appTHEMES = ['Light', 'Dark', 'Blue'];

// Global color variables that will be set based on selected theme
late Color clText;
late Color clBgrnd;
late Color clUpBar;
late Color clFill;
late Color clSel;
late Color clMenu;

// Color themes - array of arrays
List<List<Color>> colorThemes = [
  // Theme 0 - Light (Mustard)
  [
    Color(0xFF000000),  // clText - black
    Color(0xFFF5EFD5),  // clBgrnd - pale mustard
    Color(0xFFE6C94C),  // clUpBar - mustard
    Color(0xFFF9F3E3),  // clFill - light mustard
    Color(0xFFFFCC80),  // clSel - light orange
    Color(0xFFADD8E6),  // clMenu - light blue
  ],
  // Theme 1 - Dark
  [
    Color(0xFFFFFFFF),  // clText - white
    Color(0xFF212121),  // clBgrnd - dark gray
    Color(0xFF424242),  // clUpBar - medium gray
    Color(0xFF303030),  // clFill - darker gray
    Color(0xFF616161),  // clSel - lighter gray
    Color(0xFF263238),  // clMenu - dark blue-gray
  ],
  // Theme 2 - Blue
  [
    Color(0xFF000000),  // clText - black
    Color(0xFFE3F2FD),  // clBgrnd - very light blue
    Color(0xFF2196F3),  // clUpBar - blue
    Color(0xFFBBDEFB),  // clFill - light blue
    Color(0xFF90CAF9),  // clSel - medium light blue
    Color(0xFFCFD8DC),  // clMenu - blue-gray
  ],
];

// Default settings
Map<String, dynamic> defSettings = {
  "Newest first": "true",
  "Color theme": "Light",  // Default to "Light" theme
  "Notification time": "10:00",
  "Auto-backup": "false"
};

void myPrint(String msg) {
  if (xvDebug) print('>>> $msg');
}

// Get theme index from name
int getThemeIndex(String themeName) {
  return appTHEMES.indexOf(themeName);
}

// Set global colors based on theme name
// Максимально упрощенный вариант
void setThemeColors(String themeName) {
  final index = appTHEMES.indexOf(themeName);
  final themeIndex = index >= 0 ? index : 0;
  final colors = colorThemes[themeIndex];
  clText = colors[0];
  clBgrnd = colors[1];
  clUpBar = colors[2];
  clFill = colors[3];
  clSel = colors[4];
  clMenu = colors[5];
}

// App theme - will be set dynamically based on selected color theme
ThemeData getAppTheme() {
  return ThemeData(
    primarySwatch: Colors.blue,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    scaffoldBackgroundColor: clBgrnd,
    appBarTheme: AppBarTheme(
      backgroundColor: clUpBar,
      foregroundColor: clText,
    ),
    cardColor: clFill,
    // Вместо устаревшего dialogBackgroundColor используем DialogTheme
    dialogTheme: DialogTheme(
      backgroundColor: clFill,
    ),
    textTheme: TextTheme(
      bodyMedium: TextStyle(color: clText),
      bodyLarge: TextStyle(color: clText),
      displaySmall: TextStyle(color: clText),
    ),
  );
}

// Initialize databases
Future<void> initDatabases() async {
  final databasesPath = await getDatabasesPath();
  // Initialize main database
  mainDb = await openDatabase(
    join(databasesPath, mainDbFile),
    version: 1,
    onCreate: (mainDb, version) {
      return mainDb.execute(
        'CREATE TABLE IF NOT EXISTS items(id INTEGER PRIMARY KEY, title TEXT, content TEXT, tags TEXT, priority INTEGER, reminder INTEGER, created INTEGER)',
      );
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

// Initialize default settings if not already set
Future<void> initDefaultSettings() async {
  for (var entry in defSettings.entries) {
    final value = await getSetting(entry.key);
    if (value == null) {
      await saveSetting(entry.key, entry.value);
    }
  }
}

// Settings functions
Future<void> saveSetting(String key, String value) async {
  await settDb.insert(
    'settings',
    {'key': key, 'value': value},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
  // Update theme colors if changing theme
  if (key == "Color theme") {
    setThemeColors(value);
  }
}

Future<String?> getSetting(String key) async {
  final List<Map<String, dynamic>> result = await settDb.query(
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
AppBar buildAppBar(String title, {List<Widget>? actions}) {
  return AppBar(
    backgroundColor: clUpBar,
    foregroundColor: clText,
    title: Text(title),
    leading: IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => navigateBack(),
    ),
    actions: actions,
  );
}

String lw(String text) {
  // В будущем здесь будет полноценная локализация
  return text;
}

// Universal AlertDialog function with customizable options
// Universal AlertDialog function with customizable options
Future<dynamic> showCustomDialog({
  required String title,
  required String content,
  List<Map<String, dynamic>>? actions,
  bool barrierDismissible = true,
}) {
  return showDialog(
    context: globalContext,
    barrierDismissible: barrierDismissible,
    builder: (BuildContext context) {
      return AlertDialog(
        backgroundColor: clFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
          side: BorderSide(color: clUpBar, width: 2.0),
        ),
        title: Text(lw(title), style: TextStyle(color: clText)),
        content: Text(lw(content), style: TextStyle(color: clText)),
        actions: actions?.map((action) =>
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: action['isDestructive'] == true ? Colors.red : clUpBar,
                foregroundColor: clText,
              ),
              child: Text(action['label']),
              onPressed: () {
                Navigator.of(context).pop(action['value']);
                if (action['onPressed'] != null) {
                  action['onPressed']();
                }
              },
            )
        ).toList() ?? [
          // Default OK button if no actions provided
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: clUpBar,
              foregroundColor: clText,
            ),
            child: Text(lw('Ok')),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      );
    },
  );
}

// Simple information dialog using the universal dialog
void okInfo(String message) {
  showCustomDialog(
    title: lw('Information'),
    content: message,
  );
}

// Function to vacuum databases for better performance
Future<void> vacuumDatabases() async {
  try {
    myPrint("Running vacuum on the databases");
    await mainDb.execute("VACUUM");
    await settDb.execute("VACUUM");
    myPrint("Vacuum completed successfully");
  } catch (e) {
    myPrint("Error during vacuum: $e");
  }
}

