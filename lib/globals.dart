// globals.dart
import 'dart:async'; // Для Timer
import 'dart:convert'; // Для работы с JSON (json.decode) and base64
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Для доступа к rootBundle
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:intl/intl.dart';

// Глобальные ключи для доступа к основным компонентам Flutter
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

const String progVersion = '0.9.260130';
const int buildNumber = 77;
const String progAuthor = 'Eugen';

const String localesFile = 'assets/locales.json';
const String helpFile = 'assets/help.json';
const String mainDbFile = 'memorizer.db'; // Changed from mainDbFile
const String settDbFile = 'settings.db';

late Database mainDb;
late Database settDb;
late BuildContext globalContext;

// Пути для хранения файлов
late Directory? documentsDirectory;
late Directory? memorizerDirectory;
late Directory? photoDirectory;
late Directory? soundsDirectory;
late Directory? backupDirectory;

bool xvDebug = true;
String xvTagFilter = '';
String xvFilter = '';
bool xvHiddenMode = false;

String currentPin = '';
// Константа для ключа в настройках
const String hiddPinKey = 'hiddpin';
const hidModeColor = Color(0xFFf29238);

// Multi-photo constants
const int maxPhotosPerItem = 10;
const double photoThumbnailSize = 80.0;
const String tempPhotoFolderPrefix = 'temp_';

// Font setups
const double fsSmall = 13;
const double fsNormal = 15;
const double fsMedium = 17;
const double fsLarge = 19;
const fwNormal = FontWeight.normal;
const fwBold = FontWeight.bold;

// Theme names
const List<String> appTHEMES = ['Light', 'Dark', 'Blue', 'Green'];

// Global color variables that will be set based on selected theme
late Color clText;
late Color clBgrnd;
late Color clUpBar;
late Color clFill;
late Color clSel;
late Color clMenu;
const Color clRed = Colors.red;
const Color clWhite = Colors.white;

// Color themes - array of arrays
List<List<Color>> colorThemes = [
  // Theme 0 - Light (Mustard)
  [
    Color(0xFF000000), // clText - black
    Color(0xFFF5EFD5), // clBgrnd - pale mustard
    Color(0xFFE6C94C), // clUpBar - mustard
    Color(0xFFF9F3E3), // clFill - light mustard
    Color(0xFFFFCC80), // clSel - light orange
    Color(0xFFADD8E6),
  ], // clMenu - light blue
  // Theme 1 - Dark
  [
    Color(0xFFFFFFFF), // clText - white
    Color(0xFF212121), // clBgrnd - dark gray
    Color(0xFF424242), // clUpBar - medium gray
    Color(0xFF303030), // clFill - darker gray
    Color(0xFF616161), // clSel - lighter gray
    Color(0xFF263238),
  ], // clMenu - dark blue-gray
  // Theme 2 - Blue
  [
    Color(0xFF000000), // clText - black
    Color(0xFFE3F2FD), // clBgrnd - very light blue
    Color(0xFF2196F3), // clUpBar - blue
    Color(0xFFBBDEFB), // clFill - light blue
    Color(0xFF90CAF9), // clSel - medium light blue
    Color(0xFFCFD8DC),
  ], // clMenu - blue-gray
  // Green theme, 3
  [
    Color(0xFF121E0A), // text - темно-зеленый
    Color(0xFFF3F7ED), // fon clBgrnd - светлый фисташковый
    Color(0xFF97BA60), // upBar - глубокий оливковый
    Color(0xFFFFFFFF), // fill
    Color(0x4D4C6B3D), // selected - оливковый с прозрачностью
    Color(0xFFD4E2C6),
  ], // menu - шалфейный
];

// Default settings
Map<String, dynamic> defSettings = {
  "Language": "en",
  "Color theme": "Light",
  "Newest first": "true",
  "Last items": "0",
  "Enable reminders": "true",
  "Enable daily reminders": "true",
  "Debug logs": "false",
};

bool _logsEnabled = false;
String? _currentLogFile;

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
  if (currentLocale == 'en') {
    return text;
  }
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

void myPrint(String msg) {
  if (xvDebug) {
    // ignore: avoid_print
    print('>>> $msg');

    if (_logsEnabled && _currentLogFile != null) {
      try {
        final timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
        final logFile = File(_currentLogFile!);
        logFile.writeAsStringSync('$timestamp $msg\n', mode: FileMode.append);
      } catch (e) {
        // Ignore errors
      }
    }
  }
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
    appBarTheme: AppBarTheme(backgroundColor: clUpBar, foregroundColor: clText),
    cardColor: clFill,
    // Вместо устаревшего dialogBackgroundColor используем DialogTheme
    dialogTheme: DialogThemeData(backgroundColor: clFill),
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
  await settDb.insert('settings', {
    'key': key,
    'value': value,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
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
        title: Text(
          title,
          style: TextStyle(
            color: clText,
            fontSize: fsLarge,
            fontWeight: fwBold,
          ),
        ),
        content: Text(
          content,
          style: TextStyle(
            color: clText,
            fontSize: fsNormal,
            fontWeight: fwNormal,
          ),
        ),
        actions:
            actions
                ?.map(
                  (action) => TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor:
                          action['isDestructive'] == true
                              ? clRed
                              : clUpBar,
                      foregroundColor: clText,
                    ),
                    child: Text(action['label']),
                    onPressed: () {
                      Navigator.of(context).pop(action['value']);
                      if (action['onPressed'] != null) {
                        action['onPressed']();
                      }
                    },
                  ),
                )
                .toList() ??
            [
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
  showCustomDialog(title: lw('Information'), content: message);
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
        style: TextStyle(fontSize: fsSmall, color: clWhite),
      ),
      backgroundColor: clRed,
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
        style: TextStyle(fontSize: fsSmall, color: clWhite),
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
        style: TextStyle(fontSize: fsSmall, color: clWhite),
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
        style: TextStyle(fontSize: fsSmall, color: Colors.black),
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
        style: TextStyle(fontSize: fsSmall, color: clFill),
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
        {'label': lw('Ok'), 'value': null, 'isDestructive': false},
      ],
    );
    myPrint('Showing help for ID: $helpId');
  } catch (e) {
    myPrint('Error showing help: $e');
    okInfo('${lw('Error loading help')}: $e');
  }
}

// Convert language codes used in the app to proper locale codes
String getLocaleCode(String language) {
  // Dictionary for exceptions where country code differs from language code
  final Map<String, String> exceptions = {
    'ua': 'uk', // Ukrainian
    'gr': 'el', // Greek
    'cn': 'zh', // Chinese
    'jp': 'ja', // Japanese
    'se': 'sv', // Swedish
    'dk': 'da', // Danish
    'cz': 'cs', // Czech
  };

  // Make sure input is lowercase to match our exception map keys
  String langCode = language.toLowerCase();
  return exceptions[langCode] ?? langCode;
}

// Функция для проверки PIN-кода
Future<bool> verifyPin(String enteredPin) async {
  final storedPin = await getSetting(hiddPinKey);

  if (storedPin == null) {
    return false;
  }

  return storedPin == enteredPin;
}

// Функция для сохранения нового PIN-кода
Future<void> saveNewPin(String pin) async {
  await saveSetting(hiddPinKey, pin);
}

// Функция проверки, установлен ли уже PIN-код
Future<bool> isPinSet() async {
  final storedPin = await getSetting(hiddPinKey);
  return storedPin != null;
}

// Функция для обфускации текста - просто Base64
String obfuscateText(String text) {
  if (text.isEmpty) return text;

  // Используем простой Base64 для обфускации
  return base64Encode(utf8.encode(text));
}

String deobfuscateText(String encodedText) {
  if (encodedText.isEmpty) return encodedText;
  try {
    // Проверяем, является ли строка валидным Base64
    if (RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(encodedText)) {
      return utf8.decode(base64Decode(encodedText));
    } else {
      // Если не Base64, возвращаем как есть
      myPrint('Text is not Base64 encoded, returning as is');
      return encodedText;
    }
  } catch (e) {
    myPrint('Error deobfuscating text: $e');
    // Возвращаем оригинальный текст вместо сообщения об ошибке
    return encodedText;
  }
}

// Функция для кодирования/декодирования записи в зависимости от режима
Map<String, dynamic> processItemForView(Map<String, dynamic> item) {
  if (item['hidden'] == 1 && xvHiddenMode) {
    // Деобфускация скрытых записей при просмотре в скрытом режиме
    return {
      ...item,
      'title': deobfuscateText(item['title'] ?? ''),
      'content': deobfuscateText(item['content'] ?? ''),
      'tags': deobfuscateText(item['tags'] ?? ''),
    };
  }
  return item;
}

// Функция для добавления визуальной индикации режима скрытых записей
Color getAppBarColor() {
  return xvHiddenMode ? hidModeColor : clUpBar;
}

void exitHiddenMode(BuildContext context) {
  xvHiddenMode = false;
  currentPin = '';
  okInfoBarBlue(lw('Left private mode'));
  // возвращаемся на главный экран
  Navigator.popUntil(navigatorKey.currentContext!, (route) => route.isFirst);
}

// Таймер для автоматического выхода из режима скрытых записей
Timer? _hiddenModeTimer;

// Функция для сброса таймера автоматического выхода
void resetHiddenModeTimer() {
  _hiddenModeTimer?.cancel();
  if (xvHiddenMode) {
    _hiddenModeTimer = Timer(Duration(minutes: 5), () {
      if (navigatorKey.currentContext != null) {
        exitHiddenMode(navigatorKey.currentContext!);
      }
    });
  }
}

// В globals.dart:

// Основная функция для получения всех тегов с их частотами
Future<List<Map<String, dynamic>>> getTagsWithCounts() async {
  try {
    // Запрашиваем все записи для извлечения тегов
    List<Map<String, dynamic>> allItems = [];

    // В скрытом режиме нам нужны все записи
    if (xvHiddenMode) {
      // Получаем все записи
      final items = await mainDb.query('items');
      // Обрабатываем каждую запись (деобфускация)
      allItems = items.map((item) => processItemForView(item)).toList();
    } else {
      // Обычный режим - получаем только нескрытые записи
      allItems = await mainDb.query(
        'items',
        where: 'hidden = 0 OR hidden IS NULL',
      );
    }

    Map<String, int> tagCounts = {};

    // Считаем встречаемость каждого тега
    for (var item in allItems) {
      final tagsString = item['tags'] as String?;
      if (tagsString != null && tagsString.isNotEmpty) {
        // Разделяем теги по запятой и убираем лишние пробелы
        List<String> itemTags =
            tagsString
                .split(',')
                .map((tag) => tag.trim())
                .where((tag) => tag.isNotEmpty)
                .toList();

        // Подсчитываем вхождения каждого тега
        for (var tag in itemTags) {
          tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
        }
      }
    }

    // Преобразуем Map в список Map
    List<Map<String, dynamic>> result =
        tagCounts.entries.map((entry) {
          return {'name': entry.key, 'count': entry.value};
        }).toList();

    // Сортируем по количеству (по убыванию), затем по имени (по алфавиту)
    result.sort((a, b) {
      // Сначала сравниваем по количеству (по убыванию)
      int countComparison = b['count'].compareTo(a['count']);

      // Если количество одинаковое, сортируем по имени
      if (countComparison == 0) {
        return a['name'].compareTo(b['name']);
      }

      return countComparison;
    });

    return result;
  } catch (e) {
    myPrint('Error getting tags with counts: $e');
    return [];
  }
}

// Вспомогательная функция для получения только имен тегов
Future<List<String>> getAllUniqueTags() async {
  final tagsWithCounts = await getTagsWithCounts();
  return tagsWithCounts.map((tag) => tag['name'] as String).toList();
}

// Function to validate the date format (YYYY-MM-DD)
bool isValidDateFormat(String input) {
  final RegExp dateRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  return dateRegex.hasMatch(input);
}

// Function to check if the date is valid (e.g., not February 30)
bool isValidDate(String input) {
  try {
    final parts = input.split('-');
    if (parts.length != 3) return false;

    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final day = int.parse(parts[2]);

    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day;
  } catch (e) {
    return false;
  }
}

// Function to validate the date input (format and validity)
bool validateDateInput(String input) {
  if (input.isEmpty) {
    return true; // Allow empty date
  }
  if (!isValidDateFormat(input)) {
    return false; // Invalid format
  }
  if (!isValidDate(input)) {
    return false; // Invalid date
  }
  return true; // Date is valid
}

bool isDateFromBeforeDateTo(String dateFrom, String dateTo) {
  try {
    final from = DateTime.parse(dateFrom);
    final to = DateTime.parse(dateTo);
    return from.isBefore(to) || from.isAtSameMomentAs(to);
  } catch (e) {
    return false;
  }
}

// Convert DateTime to YYYYMMDD format (int)
int? dateTimeToYYYYMMDD(DateTime? date) {
  if (date == null) return null;
  int n = int.parse(DateFormat('yyyyMMdd').format(date));
  return n;
}


// Функция для преобразования int YYYYMMDD в DateTime
DateTime? yyyymmddToDateTime(int? yyyymmdd) {
  if (yyyymmdd == null) return null;
  if (yyyymmdd == 0) return null; // Explicitly handle 0 as null

  final dateStr = yyyymmdd.toString().padLeft(8, '0');
  try {
    // Parse and validate the date
    final year = int.parse(dateStr.substring(0, 4));
    final month = int.parse(dateStr.substring(4, 6));
    final day = int.parse(dateStr.substring(6, 8));

    // Check if date is valid
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      myPrint('Invalid date components: year=$year, month=$month, day=$day');
      return null;
    }

    final date = DateTime(year, month, day);
    // Verify the date is valid (handles cases like Feb 30)
    if (date.year != year || date.month != month || date.day != day) {
      myPrint('Date components do not match created date');
      return null;
    }

    return date;
  } catch (e) {
    myPrint('Error parsing date $yyyymmdd: $e');
    return null;
  }
}


Future<void> initStoragePaths() async {
  try {
    // Инициализируем директорию документов
    documentsDirectory = await getDocumentsDirectory();

    if (documentsDirectory != null) {
      // Создаем основную директорию приложения
      memorizerDirectory = Directory('${documentsDirectory!.path}/Memorizer');
      if (!await memorizerDirectory!.exists()) {
        await memorizerDirectory!.create(recursive: true);
      }

      // Создаем директорию для фотографий
      photoDirectory = Directory('${memorizerDirectory!.path}/Photo');
      if (!await photoDirectory!.exists()) {
        await photoDirectory!.create(recursive: true);
      }

      // Create sounds directory in app-private storage (no permissions needed)
      final appDir = await getApplicationDocumentsDirectory();
      soundsDirectory = Directory('${appDir.path}/Sounds');
      if (!await soundsDirectory!.exists()) {
        await soundsDirectory!.create(recursive: true);
      }
      myPrint('Sounds directory: ${soundsDirectory!.path}');

      myPrint('Storage paths initialized: ${documentsDirectory!.path}');
    } else {
      myPrint('Failed to get documents directory');
    }
  } catch (e) {
    myPrint('Error initializing storage paths: $e');
  }
}

// Получение директории документов
Future<Directory?> getDocumentsDirectory() async {
  try {
    if (Platform.isAndroid) {
      // Try external storage first
      final directory = await getExternalStorageDirectory();
      if (directory != null) {
        final androidPath = directory.path.split('/Android')[0];
        final documentsDir = Directory('$androidPath/Documents');

        try {
          // Try to create/access external Documents directory
          if (!await documentsDir.exists()) {
            await documentsDir.create(recursive: true);
          }
          // Test write access
          final testFile = File('${documentsDir.path}/.memorizer_test');
          await testFile.writeAsString('test');
          await testFile.delete();
          return documentsDir;
        } catch (e) {
          myPrint('Cannot access external Documents, using app-specific storage: $e');
          // Fallback to app-specific directory
          return await getApplicationDocumentsDirectory();
        }
      }
      return await getApplicationDocumentsDirectory();
    } else if (Platform.isLinux) {
      // На Linux обычно используем ~/Documents
      final home = Platform.environment['HOME'];
      if (home != null) {
        final documentsDir = Directory('$home/Documents');
        if (await documentsDir.exists()) {
          return documentsDir;
        }
        // Если директория не существует, создаем ее
        try {
          await documentsDir.create(recursive: true);
          return documentsDir;
        } catch (e) {
          myPrint('Error creating Documents directory: $e');
        }
      }
      return await getApplicationDocumentsDirectory();
    } else {
      // Другие платформы - используем директорию приложения
      return await getApplicationDocumentsDirectory();
    }
  } catch (e) {
    myPrint('Error getting documents directory: $e');
    return null;
  }
}

// Создание каталога для резервной копии с указанием даты
Future<Directory?> createBackupDirWithDate() async {
  try {
    if (memorizerDirectory == null) {
      await initStoragePaths();
    }

    if (memorizerDirectory == null) {
      myPrint('Memorizer directory is not initialized');
      return null;
    }

    // Генерация имени подкаталога с датой
    final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
    final backupDirPath = '${memorizerDirectory!.path}/mem-$dateStr';

    // Создание подкаталога с датой
    backupDirectory = Directory(backupDirPath);
    if (!await backupDirectory!.exists()) {
      await backupDirectory!.create(recursive: true);
    }

    return backupDirectory;
  } catch (e) {
    myPrint('Error creating backup directory with date: $e');
    return null;
  }
}

bool isValidPhotoPath(dynamic photoValue) {
  if (photoValue == null) return false;
  String path = photoValue.toString().trim();
  if (path.isEmpty || path == "\"\"" || path == "\"") return false;
  return true;
}

// Multi-photo utility functions

/// Parse photo paths from database value (JSON array or single path)
List<String> parsePhotoPaths(dynamic photoValue) {
  if (photoValue == null) return [];

  String value = photoValue.toString().trim();
  if (value.isEmpty) return [];

  // Try to parse as JSON array
  if (value.startsWith('[')) {
    try {
      final List<dynamic> parsed = json.decode(value);
      return parsed
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (e) {
      myPrint('Error parsing photo JSON: $e');
      // If JSON parsing fails, treat as single path
      return [value];
    }
  }

  // Single path (legacy format)
  return [value];
}

/// Encode photo paths to JSON string for database storage
String? encodePhotoPaths(List<String> paths) {
  if (paths.isEmpty) return null;
  if (paths.length == 1) {
    // For single photo, still use JSON array for consistency
    return json.encode(paths);
  }
  return json.encode(paths);
}

/// Get count of photos from database value
int getPhotoCount(dynamic photoValue) {
  return parsePhotoPaths(photoValue).length;
}

/// Check if there are any photos
bool hasPhotos(dynamic photoValue) {
  return parsePhotoPaths(photoValue).isNotEmpty;
}

/// Delete a single photo file without confirmation dialog
Future<bool> deletePhotoFileWithoutConfirmation(String photoPath) async {
  if (!isValidPhotoPath(photoPath)) return false;

  try {
    final file = File(photoPath);
    if (await file.exists()) {
      await file.delete();
      myPrint('Deleted photo file: $photoPath');
      return true;
    }
    return true; // File doesn't exist, consider it deleted
  } catch (e) {
    myPrint('Error deleting photo file: $e');
    return false;
  }
}

/// Delete all photos with a single confirmation dialog
Future<bool> deleteAllPhotosWithConfirmation(List<String> paths) async {
  if (paths.isEmpty) return true;

  // Filter to only existing files
  List<String> existingPaths = [];
  for (var path in paths) {
    if (isValidPhotoPath(path)) {
      final file = File(path);
      if (await file.exists()) {
        existingPaths.add(path);
      }
    }
  }

  if (existingPaths.isEmpty) return true;

  // Show confirmation dialog
  final confirmed = await showCustomDialog(
    title: lw('Delete Photos'),
    content: existingPaths.length == 1
        ? lw('Are you sure you want to delete this photo?')
        : '${lw('Are you sure you want to delete')} ${existingPaths.length} ${lw('photos')}?',
    actions: [
      {'label': lw('Cancel'), 'value': false, 'isDestructive': false},
      {'label': lw('Delete'), 'value': true, 'isDestructive': true},
    ],
  );

  if (confirmed == true) {
    int deletedCount = 0;
    for (var path in existingPaths) {
      if (await deletePhotoFileWithoutConfirmation(path)) {
        deletedCount++;
      }
    }
    myPrint('Deleted $deletedCount of ${existingPaths.length} photos');
    return true;
  }

  return false;
}

// ============ Item Photo Folder Utilities ============

/// Get the photo directory path for a specific item
String getItemPhotoDirPath(int itemId) {
  if (photoDirectory == null) return '';
  return '${photoDirectory!.path}/item_$itemId';
}

/// Get or create the photo directory for a specific item
Future<Directory?> getItemPhotoDir(int itemId) async {
  if (photoDirectory == null) {
    await initStoragePaths();
  }
  if (photoDirectory == null) return null;

  final dir = Directory(getItemPhotoDirPath(itemId));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// Create a temporary photo directory for new items
Future<String?> createTempPhotoDir() async {
  if (photoDirectory == null) {
    await initStoragePaths();
  }
  if (photoDirectory == null) return null;

  // Generate unique temp folder name with timestamp
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final tempDirPath = '${photoDirectory!.path}/$tempPhotoFolderPrefix$timestamp';
  final tempDir = Directory(tempDirPath);

  if (!await tempDir.exists()) {
    await tempDir.create(recursive: true);
  }

  myPrint('Created temp photo dir: $tempDirPath');
  return tempDirPath;
}

/// Move photos from temp directory to item directory after save
Future<List<String>> movePhotosFromTempToItem(String tempDirPath, int itemId) async {
  final tempDir = Directory(tempDirPath);
  if (!await tempDir.exists()) {
    myPrint('Temp dir does not exist: $tempDirPath');
    return [];
  }

  final itemDir = await getItemPhotoDir(itemId);
  if (itemDir == null) {
    myPrint('Failed to create item photo dir for item $itemId');
    return [];
  }

  List<String> newPaths = [];
  final files = await tempDir.list().toList();

  for (var entity in files) {
    if (entity is File) {
      final fileName = entity.path.split('/').last;
      final newPath = '${itemDir.path}/$fileName';
      try {
        await entity.copy(newPath);
        await entity.delete();
        newPaths.add(newPath);
        myPrint('Moved photo: ${entity.path} -> $newPath');
      } catch (e) {
        myPrint('Error moving photo: $e');
      }
    }
  }

  // Delete empty temp directory
  try {
    await tempDir.delete();
    myPrint('Deleted temp dir: $tempDirPath');
  } catch (e) {
    myPrint('Error deleting temp dir: $e');
  }

  return newPaths;
}

/// Delete a temporary photo directory (when user cancels)
Future<void> deleteTempPhotoDir(String? tempDirPath) async {
  if (tempDirPath == null || tempDirPath.isEmpty) return;

  final tempDir = Directory(tempDirPath);
  if (await tempDir.exists()) {
    try {
      await tempDir.delete(recursive: true);
      myPrint('Deleted temp photo dir: $tempDirPath');
    } catch (e) {
      myPrint('Error deleting temp photo dir: $e');
    }
  }
}

/// Delete the photo directory for a specific item
Future<void> deleteItemPhotoDir(int itemId) async {
  final dirPath = getItemPhotoDirPath(itemId);
  if (dirPath.isEmpty) return;

  final dir = Directory(dirPath);
  if (await dir.exists()) {
    try {
      await dir.delete(recursive: true);
      myPrint('Deleted item photo dir: $dirPath');
    } catch (e) {
      myPrint('Error deleting item photo dir: $e');
    }
  }
}

/// Clean up orphaned temp directories (older than 1 day)
Future<void> cleanupOrphanedTempDirs() async {
  if (photoDirectory == null) return;

  try {
    final entities = await photoDirectory!.list().toList();
    final oneDayAgo = DateTime.now().subtract(Duration(days: 1));

    for (var entity in entities) {
      if (entity is Directory) {
        final dirName = entity.path.split('/').last;
        if (dirName.startsWith(tempPhotoFolderPrefix)) {
          // Check if directory is old
          final stat = await entity.stat();
          if (stat.modified.isBefore(oneDayAgo)) {
            await entity.delete(recursive: true);
            myPrint('Cleaned up orphaned temp dir: ${entity.path}');
          }
        }
      }
    }
  } catch (e) {
    myPrint('Error cleaning up orphaned temp dirs: $e');
  }
}

/// Get list of photo files in an item's directory
Future<List<String>> getItemPhotoPaths(int itemId) async {
  final dirPath = getItemPhotoDirPath(itemId);
  if (dirPath.isEmpty) return [];

  final dir = Directory(dirPath);
  if (!await dir.exists()) return [];

  List<String> paths = [];
  final files = await dir.list().toList();
  for (var entity in files) {
    if (entity is File && _isImageFile(entity.path)) {
      paths.add(entity.path);
    }
  }

  // Sort by filename for consistent ordering
  paths.sort();
  return paths;
}

/// Check if file is an image based on extension
bool _isImageFile(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.webp');
}

/// Check if file is an audio file based on extension
bool isAudioFile(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.mp3') ||
      lower.endsWith('.wav') ||
      lower.endsWith('.ogg') ||
      lower.endsWith('.m4a') ||
      lower.endsWith('.aac');
}

/// Copy sound file to Sounds directory and return new path
Future<String?> copySoundFile(String sourcePath) async {
  if (soundsDirectory == null) {
    await initStoragePaths();
  }
  if (soundsDirectory == null) return null;

  try {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      myPrint('Source sound file does not exist: $sourcePath');
      return null;
    }

    // Get filename from source path
    final fileName = sourcePath.split('/').last;
    final destPath = '${soundsDirectory!.path}/$fileName';

    // Check if file already exists with same name
    final destFile = File(destPath);
    if (await destFile.exists()) {
      // File already exists, use it
      myPrint('Sound file already exists: $destPath');
      return destPath;
    }

    // Copy file
    await sourceFile.copy(destPath);
    myPrint('Sound file copied to: $destPath');
    return destPath;
  } catch (e) {
    myPrint('Error copying sound file: $e');
    return null;
  }
}

/// Get list of sound files in Sounds directory
Future<List<Map<String, String>>> getCustomSounds() async {
  if (soundsDirectory == null) {
    await initStoragePaths();
  }
  if (soundsDirectory == null) return [];

  try {
    final files = await soundsDirectory!.list().toList();
    List<Map<String, String>> sounds = [];

    for (var entity in files) {
      if (entity is File && isAudioFile(entity.path)) {
        final fileName = entity.path.split('/').last;
        // Remove extension for display name
        final displayName = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
        sounds.add({
          'name': displayName,
          'path': entity.path,
        });
      }
    }

    // Sort by name
    sounds.sort((a, b) => a['name']!.compareTo(b['name']!));
    return sounds;
  } catch (e) {
    myPrint('Error getting custom sounds: $e');
    return [];
  }
}

Future<bool> deletePhotoFile(String photoPath) async {
  // Quick exit if path is empty/invalid
  if (!isValidPhotoPath(photoPath)) return false;

  // Check if file exists
  final file = File(photoPath);
  if (!await file.exists()) return true; // Exit silently if file doesn't exist

  // Show confirmation dialog using existing methods
  final confirmed = await showCustomDialog(
    title: lw('Delete Photo'),
    content: lw('Are you sure you want to delete this photo?'),
    actions: [
      {'label': lw('Cancel'), 'value': false, 'isDestructive': false},
      {'label': lw('Delete'), 'value': true, 'isDestructive': true},
    ],
  );

  // Delete file if confirmed
  if (confirmed == true) {
    try {
      await file.delete();
      return true;
    } catch (e) {
      myPrint('Error deleting photo: $e');
      okInfoBarRed(lw('Error deleting photo'));
      return false;
    }
  }

  return false;
}

// Функция для преобразования int HHMM в строку "HH:MM"
String? timeIntToString(int? timeInt) {
  if (timeInt == null) return null;

  // Проверка корректности формата
  if (timeInt < 0 || timeInt > 2359) return null;

  // Разделяем на часы и минуты
  final hours = timeInt ~/ 100;
  final minutes = timeInt % 100;

  // Проверка правильности времени
  if (hours > 23 || minutes > 59) return null;

  // Форматируем с ведущими нулями
  return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
}

// Функция для преобразования строки "HH:MM" в int HHMM
int? timeStringToInt(String? timeString) {
  if (timeString == null || timeString.isEmpty) return null;

  // Разбиваем строку на части
  final parts = timeString.split(':');
  if (parts.length != 2) return null;

  // Пытаемся преобразовать части в числа
  final hours = int.tryParse(parts[0]);
  final minutes = int.tryParse(parts[1]);

  // Проверяем корректность значений
  if (hours == null || minutes == null) return null;
  if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) return null;

  // Возвращаем в формате HHMM
  return hours * 100 + minutes;
}

// Функция для проверки времени на корректность
bool isValidTimeFormat(String? timeString) {
  if (timeString == null || timeString.isEmpty) return true; // Пустое значение допустимо

  // Проверяем формат HH:MM
  final RegExp timeRegex = RegExp(r'^([01]?[0-9]|2[0-3]):([0-5][0-9])$');
  if (!timeRegex.hasMatch(timeString)) return false;

  return true;
}

// ============ Daily Reminder Utilities ============

// Days of week constants (bitmask: bit 0 = Monday, bit 6 = Sunday)
const int dayMonday = 1;      // 0b0000001
const int dayTuesday = 2;     // 0b0000010
const int dayWednesday = 4;   // 0b0000100
const int dayThursday = 8;    // 0b0001000
const int dayFriday = 16;     // 0b0010000
const int daySaturday = 32;   // 0b0100000
const int daySunday = 64;     // 0b1000000
const int dayAllDays = 127;   // 0b1111111 (all days)
const int dayWeekdays = 31;   // 0b0011111 (Mon-Fri)
const int dayWeekend = 96;    // 0b1100000 (Sat-Sun)

// Day names for UI (ordered: Mon-Sun)
const List<String> dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const List<String> dayNamesRu = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

/// Get localized day name for index (0=Monday, 6=Sunday)
String getDayName(int dayIndex) {
  if (dayIndex < 0 || dayIndex > 6) return '';
  final names = currentLocale == 'ru' ? dayNamesRu : dayNames;
  return names[dayIndex];
}

/// Check if a specific day is set in the bitmask
bool isDayEnabled(int dayMask, int dayIndex) {
  if (dayIndex < 0 || dayIndex > 6) return false;
  return (dayMask & (1 << dayIndex)) != 0;
}

/// Set or clear a specific day in the bitmask
int setDayEnabled(int dayMask, int dayIndex, bool enabled) {
  if (dayIndex < 0 || dayIndex > 6) return dayMask;
  if (enabled) {
    return dayMask | (1 << dayIndex);
  } else {
    return dayMask & ~(1 << dayIndex);
  }
}

/// Check if today is an active day in the bitmask
bool isTodayEnabled(int dayMask) {
  // DateTime.weekday: 1=Monday, 7=Sunday
  // Our bitmask: bit 0=Monday, bit 6=Sunday
  final todayIndex = DateTime.now().weekday - 1; // Convert to 0-6
  return isDayEnabled(dayMask, todayIndex);
}

/// Get list of enabled day indices from bitmask
List<int> getEnabledDays(int dayMask) {
  List<int> days = [];
  for (int i = 0; i < 7; i++) {
    if (isDayEnabled(dayMask, i)) {
      days.add(i);
    }
  }
  return days;
}

/// Get human-readable string of enabled days
String getDaysString(int dayMask) {
  if (dayMask == dayAllDays) return lw('Every day');
  if (dayMask == dayWeekdays) return lw('Weekdays');
  if (dayMask == dayWeekend) return lw('Weekend');
  if (dayMask == 0) return lw('No days');

  final enabledDays = getEnabledDays(dayMask);
  return enabledDays.map((i) => getDayName(i)).join(', ');
}

// ============ Daily Times JSON Utilities ============

/// Parse daily times from JSON string (["08:00", "14:00", "20:00"])
List<String> parseDailyTimes(dynamic timesValue) {
  if (timesValue == null) return [];

  String value = timesValue.toString().trim();
  if (value.isEmpty) return [];

  try {
    final List<dynamic> parsed = json.decode(value);
    return parsed
        .map((e) => e.toString().trim())
        .where((e) => isValidTimeFormat(e))
        .toList();
  } catch (e) {
    myPrint('Error parsing daily times JSON: $e');
    return [];
  }
}

/// Encode daily times to JSON string
String? encodeDailyTimes(List<String> times) {
  if (times.isEmpty) return null;
  // Filter only valid times and sort
  final validTimes = times.where((t) => isValidTimeFormat(t)).toList();
  validTimes.sort();
  if (validTimes.isEmpty) return null;
  return json.encode(validTimes);
}

/// Add a time to the list (sorted, no duplicates)
List<String> addDailyTime(List<String> times, String newTime) {
  if (!isValidTimeFormat(newTime)) return times;
  if (times.contains(newTime)) return times;

  final newList = List<String>.from(times);
  newList.add(newTime);
  newList.sort();
  return newList;
}

/// Remove a time from the list
List<String> removeDailyTime(List<String> times, String timeToRemove) {
  return times.where((t) => t != timeToRemove).toList();
}

/// Get formatted string of daily times for display
String getDailyTimesString(List<String> times) {
  if (times.isEmpty) return lw('No times set');
  return times.join(', ');
}

/// Default daily reminder sound name
const String defaultDailySound = 'default_daily';

Future<void> initLogging() async {
  final debugLogsEnabled = await getSetting("Debug logs") ?? "false";
  _logsEnabled = debugLogsEnabled == "true";

  if (_logsEnabled) {
    try {
      if (documentsDirectory == null) await initStoragePaths();
      if (documentsDirectory == null) return;

      // Создаем папку Logs
      final logsDir = Directory('${documentsDirectory!.path}/Memorizer/Logs');
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }

      // Имя файла с датой и временем
      final now = DateTime.now();
      final dateTime = DateFormat('yyyyMMdd-HHmmss').format(now);
      _currentLogFile = '${logsDir.path}/log-$dateTime.txt';

      // Записываем заголовок
      final startMessage = 'App started at ${DateFormat('yyyy-MM-dd HH:mm:ss').format(now)}\n';
      await File(_currentLogFile!).writeAsString(startMessage);
    } catch (e) {
      // Игнорируем ошибки в логировании
    }
  }
}