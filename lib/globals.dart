// globals.dart
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:convert'; // Для работы с JSON (json.decode)
import 'package:flutter/services.dart'; // Для доступа к rootBundle

// Глобальные ключи для доступа к основным компонентам Flutter
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

const String progVersion = '0.0.250311';
const String progAuthor = 'Eugen';

const String localesFile = 'assets/locales.json';
const String helpFile = 'assets/help.json';
const String mainDbFile = 'memorizer.db';  // Changed from mainDbFile
const String settDbFile = 'settings.db';

late Database mainDb;
late Database settDb;
late BuildContext globalContext;

bool xvDebug = true;
String xvTagFilter = '';
String xvFilter = '';

// Font sizes
const double fsSmall = 11;
const double fsNormal = 12;
const double fsMedium = 14;
const double fsLarge = 16;
const double fsXLarge = 18;
const double fsHeader = 22;
const double fsSHeader = 24;

// Theme names
const List<String> appTHEMES = ['Light', 'Dark', 'Blue', 'Green'];

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
  [ Color(0xFF000000),  // clText - black
    Color(0xFFF5EFD5),  // clBgrnd - pale mustard
    Color(0xFFE6C94C),  // clUpBar - mustard
    Color(0xFFF9F3E3),  // clFill - light mustard
    Color(0xFFFFCC80),  // clSel - light orange
    Color(0xFFADD8E6),],  // clMenu - light blue
    // Theme 1 - Dark
  [ Color(0xFFFFFFFF),  // clText - white
    Color(0xFF212121),  // clBgrnd - dark gray
    Color(0xFF424242),  // clUpBar - medium gray
    Color(0xFF303030),  // clFill - darker gray
    Color(0xFF616161),  // clSel - lighter gray
    Color(0xFF263238),],  // clMenu - dark blue-gray
    // Theme 2 - Blue
  [ Color(0xFF000000),  // clText - black
    Color(0xFFE3F2FD),  // clBgrnd - very light blue
    Color(0xFF2196F3),  // clUpBar - blue
    Color(0xFFBBDEFB),  // clFill - light blue
    Color(0xFF90CAF9),  // clSel - medium light blue
    Color(0xFFCFD8DC),],  // clMenu - blue-gray
    // Green theme, 3
  [ Color(0xFF121E0A),      // text - темно-зеленый
    Color(0xFFF3F7ED),      // fon clBgrnd - светлый фисташковый
    Color(0xFF97BA60),      // upBar - глубокий оливковый
    Color(0xFFFFFFFF),      // fill
    Color(0x4D4C6B3D),      // selected - оливковый с прозрачностью
    Color(0xFFD4E2C6),],    // menu - шалфейный
];

// Default settings
Map<String, dynamic> defSettings = {
  "Language": "en",
  "Color theme": "Light",
  "Newest first": "true",
  "Last items": "0",
  "Notification time": "10:00",
  "Auto-backup": "false",
};

const ymdDateFormat = 'yyyy-MM-dd';

// Карта поддерживаемых языков с их названиями
Map<String, String> langNames = {
  'en': 'English',
  'ru': 'Русский',
  'ua': 'Українська',
};

// Кеш переводов для текущего языка
Map<String, String> _uiLocale = {};
// Текущая локаль
String currentLocale = 'en';

// Функция проверки поддерживаемого языка
bool isLanguageSupported(String locale) {
  return langNames.containsKey(locale.toLowerCase());
}

String lw(String text) {
  if (currentLocale == 'en') {return text;}
  return _uiLocale[text] ?? text;
}

// Чтение локализаций из файла
Future<void> readLocale(String locale) async {
  locale = locale.toLowerCase();
  // Проверяем, что язык поддерживается
  if (!isLanguageSupported(locale)) {
    myPrint('Language $locale not supported, using English instead');
    currentLocale = 'en';
  } else {
    currentLocale = locale;
  }

  // Для английского языка кеш не нужен
  if (currentLocale == 'en') {
    _uiLocale = {};
    return;
  }

  try {
    // Загружаем JSON файл с локализациями
    final jsonString = await rootBundle.loadString(localesFile);
    final Map<String, dynamic> allTranslations = json.decode(jsonString);
    // Создаем пустой кеш
    _uiLocale = {};
    // Заполняем кеш переводами для текущей локали
    allTranslations.forEach((key, value) {
      if (value is Map && value.containsKey(currentLocale)) {
        _uiLocale[key] = value[currentLocale];
      }
    });
  } catch (e) {
    myPrint('Error loading translations: $e');
    _uiLocale = {};
  }
}

void myPrint(String msg) {if (xvDebug) print('>>> $msg');}

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

// Initialize default settings if not already set
Future<void> initDefaultSettings() async {
  for (var entry in defSettings.entries) {
    final value = await getSetting(entry.key);
    if (value == null) {
      await saveSetting(entry.key, entry.value);
    }
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
        title: Text(title, style: TextStyle(color: clText)),
        content: Text(content, style: TextStyle(color: clText)),
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

// Function to show a red SnackBar
void okInfoBarRed(String message, {Duration? duration}) {
  myPrint("Showing red SnackBar: $message");
  scaffoldMessengerKey.currentState?.clearSnackBars();
  scaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: TextStyle(
          fontSize: fsSmall,
          color: Colors.white,
        ),
      ),
      backgroundColor: Colors.red,
      duration: duration ?? Duration(seconds: 7),
      behavior: SnackBarBehavior.floating,
      dismissDirection: DismissDirection.none,
    ),
  );
}

// Function to show a green SnackBar
void okInfoBarGreen(String message, {Duration? duration}) {
  myPrint("Showing green SnackBar: $message");
  scaffoldMessengerKey.currentState?.clearSnackBars();
  scaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: TextStyle(
          fontSize: fsSmall,
          color: Colors.white,
        ),
      ),
      backgroundColor: Colors.green,
      duration: duration ?? Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      dismissDirection: DismissDirection.none,
    ),
  );
}

// Function to show a blue SnackBar
void okInfoBarBlue(String message, {Duration? duration}) {
  myPrint("Showing blue SnackBar: $message");
  scaffoldMessengerKey.currentState?.clearSnackBars();
  scaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: TextStyle(
          fontSize: fsSmall,
          color: Colors.white,
        ),
      ),
      backgroundColor: Colors.blue,
      duration: duration ?? Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      dismissDirection: DismissDirection.none,
    ),
  );
}

void okInfoBarOrange(String message, {Duration? duration}) {
  myPrint("Showing green SnackBar: $message");
  scaffoldMessengerKey.currentState?.clearSnackBars();
  scaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: TextStyle(
          fontSize: fsSmall,
          color: Colors.black,
        ),
      ),
      backgroundColor: Colors.orange,
      duration: duration ?? Duration(seconds: 4),
      behavior: SnackBarBehavior.floating,
      dismissDirection: DismissDirection.none,
    ),
  );
}

// Function to show a purple SnackBar
void okInfoBarPurple(String message) {
  scaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: TextStyle(
          fontSize: fsSmall,
          color: clFill,
        ),
      ),
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.purple,
      duration: Duration(days: 3),
      dismissDirection: DismissDirection.none,
      action: SnackBarAction(
        label: '[ Ok ]',
        onPressed: () {
          scaffoldMessengerKey.currentState?.hideCurrentSnackBar();
        },
      ),
    ),
  );
}

// Отладочная функция для проверки состояния ключа
bool isScaffoldMessengerKeyInitialized() {
  bool isInitialized = scaffoldMessengerKey.currentState != null;
  myPrint("ScaffoldMessengerKey initialized: $isInitialized");
  return isInitialized;
}

// Функция для отображения справки по ID
void showHelp(int id) async {
  try {
    // Загружаем JSON файл с текстами справки
    final jsonString = await rootBundle.loadString(helpFile);
    final Map<String, dynamic> helpTexts = json.decode(jsonString);
    final String helpId = id.toString();
    String helpText = '';
    // Получаем текст справки для текущего языка
    if (helpTexts.containsKey(helpId)) {
      final Map<String, dynamic> helpEntry = helpTexts[helpId];
      if (helpEntry.containsKey(currentLocale)) {
        helpText = helpEntry[currentLocale];
      } else if (helpEntry.containsKey('en')) {
        // Если нет перевода для текущего языка, используем английский
        helpText = helpEntry['en'];
      } else {
        helpText = 'Help text not available';
      }
    } else {
      helpText = 'Help ID:$helpId not found';
    }
    // Отображаем диалог с текстом справки
    showCustomDialog(
      title: lw('Help'),
      content: helpText,
      actions: [
        {
          'label': lw('Ok'),
          'value': null,
          'isDestructive': false,
        },
      ],
    );
    myPrint('Showing help for ID: $helpId');
  } catch (e) {
    myPrint('Error showing help: $e');
    okInfo(lw('Error loading help') + ': $e');
  }
}

// Convert language codes used in the app to proper locale codes
String getLocaleCode(String language) {
  // Dictionary for exceptions where country code differs from language code
  final Map<String, String> exceptions = {
    'ua': 'uk',  // Ukrainian
    'gr': 'el',  // Greek
    'cn': 'zh',  // Chinese
    'jp': 'ja',  // Japanese
    'se': 'sv',  // Swedish
    'dk': 'da',  // Danish
    'cz': 'cs',  // Czech
  };

  // Make sure input is lowercase to match our exception map keys
  String langCode = language.toLowerCase();
  return exceptions[langCode] ?? langCode;
}
