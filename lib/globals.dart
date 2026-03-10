// globals.dart
import 'dart:async'; // For Timer
import 'dart:convert'; // For JSON (json.decode) and base64
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For rootBundle access
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:intl/intl.dart';

// Global keys for accessing main Flutter components
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

const String progVersion = '0.9.260310';
const int buildNumber = 131;
const String progAuthor = 'Eugen';

const String localesFile = 'assets/locales.json';
const String helpFile = 'assets/help.json';
const String mainDbFile = 'memorizer.db';
const String settDbFile = 'settings.db';
const int mainDbVersion = 16;
const int settDbVersion = 2;
// Set by initDatabases(), used by backup.dart for restore with migrations
OnDatabaseVersionChangeFn? mainDbOnUpgrade;

late Database mainDb;
late Database settDb;
late BuildContext globalContext;

// File storage paths
late Directory? documentsDirectory;
late Directory? memorizerDirectory;
late Directory? photoDirectory;
late Directory? soundsDirectory;
late Directory? backupDirectory;

bool xvDebug = true;
String xvTagFilter = '';
String xvFilter = '';
String xvSavedUserFilter = ''; // User filter preserved when inside virtual folders
bool xvHiddenMode = false;

String currentPin = '';
// Settings key constant
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
    Color(0xFF121E0A), // text - dark green
    Color(0xFFF3F7ED), // fon clBgrnd - light pistachio
    Color(0xFF97BA60), // upBar - deep olive
    Color(0xFFFFFFFF), // fill
    Color(0x4D4C6B3D), // selected - olive with transparency
    Color(0xFFD4E2C6),
  ], // menu - sage
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

// Map of supported languages with their names
Map<String, String> langNames = {
  'en': 'English',
  'ru': 'Русский',
  'ua': 'Українська',
};

// Translation cache for current language
Map<String, String> _uiLocale = {};
// Current locale
String currentLocale = 'en';

// Check if language is supported
bool isLanguageSupported(String locale) {
  return langNames.containsKey(locale.toLowerCase());
}

String lw(String text) {
  if (currentLocale == 'en') {
    return text;
  }
  return _uiLocale[text] ?? text;
}

// Read localizations from file
Future<void> readLocale(String locale) async {
  locale = locale.toLowerCase();
  // Check that the language is supported
  if (!isLanguageSupported(locale)) {
    myPrint('Language $locale not supported, using English instead');
    currentLocale = 'en';
  } else {
    currentLocale = locale;
  }
  // No cache needed for English
  if (currentLocale == 'en') {
    _uiLocale = {};
    return;
  }

  try {
    // Load JSON file with localizations
    final jsonString = await rootBundle.loadString(localesFile);
    final Map<String, dynamic> allTranslations = json.decode(jsonString);
    // Create empty cache
    _uiLocale = {};
    // Fill cache with translations for current locale
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
// Simplified version
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
    // Use DialogTheme instead of deprecated dialogBackgroundColor
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
  myPrint("Showing orange SnackBar: $message");
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

// Debug function to check key state
bool isScaffoldMessengerKeyInitialized() {
  bool isInitialized = scaffoldMessengerKey.currentState != null;
  myPrint("ScaffoldMessengerKey initialized: $isInitialized");
  return isInitialized;
}

// Show help by ID
void showHelp(int id) async {
  try {
    // Load JSON file with help texts
    final jsonString = await rootBundle.loadString(helpFile);
    final Map<String, dynamic> helpTexts = json.decode(jsonString);
    final String helpId = id.toString();
    String helpText = '';
    // Get help text for current language
    if (helpTexts.containsKey(helpId)) {
      final Map<String, dynamic> helpEntry = helpTexts[helpId];
      if (helpEntry.containsKey(currentLocale)) {
        helpText = helpEntry[currentLocale];
      } else if (helpEntry.containsKey('en')) {
        // If no translation for current language, use English
        helpText = helpEntry['en'];
      } else {
        helpText = 'Help text not available';
      }
    } else {
      helpText = 'Help ID:$helpId not found';
    }
    // Show dialog with help text
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

// Verify PIN code
Future<bool> verifyPin(String enteredPin) async {
  final storedPin = await getSetting(hiddPinKey);

  if (storedPin == null) {
    return false;
  }

  return storedPin == enteredPin;
}

// Save new PIN code
Future<void> saveNewPin(String pin) async {
  await saveSetting(hiddPinKey, pin);
}

// Check if PIN code is already set
Future<bool> isPinSet() async {
  final storedPin = await getSetting(hiddPinKey);
  return storedPin != null;
}

// Text obfuscation function - simple Base64
String obfuscateText(String text) {
  if (text.isEmpty) return text;

  // Use simple Base64 for obfuscation
  return base64Encode(utf8.encode(text));
}

String deobfuscateText(String encodedText) {
  if (encodedText.isEmpty) return encodedText;
  try {
    // Check if string is valid Base64
    if (RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(encodedText)) {
      return utf8.decode(base64Decode(encodedText));
    } else {
      // If not Base64, return as is
      myPrint('Text is not Base64 encoded, returning as is');
      return encodedText;
    }
  } catch (e) {
    myPrint('Error deobfuscating text: $e');
    // Return original text instead of error message
    return encodedText;
  }
}

// Encode/decode item depending on mode
Map<String, dynamic> processItemForView(Map<String, dynamic> item) {
  if (item['hidden'] == 1 && xvHiddenMode) {
    // Deobfuscate hidden items when viewing in hidden mode
    return {
      ...item,
      'title': deobfuscateText(item['title'] ?? ''),
      'content': deobfuscateText(item['content'] ?? ''),
      'tags': deobfuscateText(item['tags'] ?? ''),
    };
  }
  return item;
}

// Visual indication for hidden items mode
Color getAppBarColor() {
  return xvHiddenMode ? hidModeColor : clUpBar;
}

void exitHiddenMode(BuildContext context) {
  xvHiddenMode = false;
  currentPin = '';
  okInfoBarBlue(lw('Left private mode'));
  // Return to main screen
  Navigator.popUntil(navigatorKey.currentContext!, (route) => route.isFirst);
}

// Timer for automatic exit from hidden items mode
Timer? _hiddenModeTimer;

// Reset automatic exit timer
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

// In globals.dart:

// Main function to get all tags with their frequencies
Future<List<Map<String, dynamic>>> getTagsWithCounts() async {
  try {
    // Query all items to extract tags
    List<Map<String, dynamic>> allItems = [];

    // In hidden mode we need all items
    if (xvHiddenMode) {
      // Get only hidden items in hidden mode
      final items = await mainDb.query('items', where: 'hidden = 1');
      allItems = items.map((item) => processItemForView(item)).toList();
    } else {
      // Normal mode - get only non-hidden items
      allItems = await mainDb.query(
        'items',
        where: 'hidden = 0 OR hidden IS NULL',
      );
    }

    Map<String, int> tagCounts = {};

    // Count occurrences of each tag
    for (var item in allItems) {
      final tagsString = item['tags'] as String?;
      if (tagsString != null && tagsString.isNotEmpty) {
        // Split tags by comma and trim whitespace
        List<String> itemTags =
            tagsString
                .split(',')
                .map((tag) => tag.trim())
                .where((tag) => tag.isNotEmpty)
                .toList();

        // Count each tag occurrence
        for (var tag in itemTags) {
          tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
        }
      }
    }

    // Convert Map to list of Maps
    List<Map<String, dynamic>> result =
        tagCounts.entries.map((entry) {
          return {'name': entry.key, 'count': entry.value};
        }).toList();

    // Sort by count (descending), then by name (alphabetically)
    result.sort((a, b) {
      // First compare by count (descending)
      int countComparison = b['count'].compareTo(a['count']);

      // If count is equal, sort by name
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

// Helper function to get only tag names
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


// Convert int YYYYMMDD to DateTime
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
    // Initialize documents directory
    documentsDirectory = await getDocumentsDirectory();

    if (documentsDirectory != null) {
      // Create main app directory
      memorizerDirectory = Directory('${documentsDirectory!.path}/Memorizer');
      if (!await memorizerDirectory!.exists()) {
        await memorizerDirectory!.create(recursive: true);
      }

      // Create photos directory
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

// Get documents directory
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
      // On Linux we typically use ~/Documents
      final home = Platform.environment['HOME'];
      if (home != null) {
        final documentsDir = Directory('$home/Documents');
        if (await documentsDir.exists()) {
          return documentsDir;
        }
        // If directory doesn't exist, create it
        try {
          await documentsDir.create(recursive: true);
          return documentsDir;
        } catch (e) {
          myPrint('Error creating Documents directory: $e');
        }
      }
      return await getApplicationDocumentsDirectory();
    } else {
      // Other platforms - use app directory
      return await getApplicationDocumentsDirectory();
    }
  } catch (e) {
    myPrint('Error getting documents directory: $e');
    return null;
  }
}

// Create backup directory with date
Future<Directory?> createBackupDirWithDate() async {
  try {
    if (memorizerDirectory == null) {
      await initStoragePaths();
    }

    if (memorizerDirectory == null) {
      myPrint('Memorizer directory is not initialized');
      return null;
    }

    // Generate subdirectory name with date
    final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
    final backupDirPath = '${memorizerDirectory!.path}/mem-$dateStr';

    // Create subdirectory with date
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

// Convert int HHMM to string "HH:MM"
String? timeIntToString(int? timeInt) {
  if (timeInt == null) return null;

  // Validate format
  if (timeInt < 0 || timeInt > 2359) return null;

  // Split into hours and minutes
  final hours = timeInt ~/ 100;
  final minutes = timeInt % 100;

  // Validate time values
  if (hours > 23 || minutes > 59) return null;

  // Format with leading zeros
  return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
}

// Convert YYYYMMDD int to "yyyy-MM-dd" string
String dateIntToStr(int dateInt) {
  final y = dateInt ~/ 10000;
  final m = (dateInt % 10000) ~/ 100;
  final d = dateInt % 100;
  return '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
}

// Convert "yyyy-MM-dd" string to YYYYMMDD int
int? dateStrToInt(String? dateStr) {
  if (dateStr == null || dateStr.isEmpty) return null;
  try {
    final dt = DateFormat(ymdDateFormat).parse(dateStr);
    return dt.year * 10000 + dt.month * 100 + dt.day;
  } catch (e) {
    return null;
  }
}

// Convert string "HH:MM" to int HHMM
int? timeStringToInt(String? timeString) {
  if (timeString == null || timeString.isEmpty) return null;

  // Split string into parts
  final parts = timeString.split(':');
  if (parts.length != 2) return null;

  // Try to parse parts as numbers
  final hours = int.tryParse(parts[0]);
  final minutes = int.tryParse(parts[1]);

  // Validate values
  if (hours == null || minutes == null) return null;
  if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) return null;

  // Return in HHMM format
  return hours * 100 + minutes;
}

// Validate time format
bool isValidTimeFormat(String? timeString) {
  if (timeString == null || timeString.isEmpty) return true; // Empty value is allowed

  // Check HH:MM format
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

// Virtual folder filter identifiers
const Set<String> virtualFolderFilters = {
  'notes:true', 'yearly:true', 'daily:true', 'monthly:true', 'period:true'
};

// Date picker bounds
final DateTime datePickerFirst = DateTime(2000);
final DateTime datePickerLast = DateTime(2101);

// Priority
const int maxPriority = 3;

// Day name keys for localization (ordered: Mon-Sun)
const List<String> dayKeys = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

/// Get localized day name for index (0=Monday, 6=Sunday)
String getDayName(int dayIndex) {
  if (dayIndex < 0 || dayIndex > 6) return '';
  return lw(dayKeys[dayIndex]);
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

/// Get compact days string (e.g., "MTWTF--")
String getDaysCompact(int dayMask) {
  final sb = StringBuffer();
  for (int i = 0; i < 7; i++) {
    if (isDayEnabled(dayMask, i)) {
      sb.write(lw(dayKeys[i])[0].toLowerCase());
    } else {
      sb.write('-');
    }
  }
  return sb.toString();
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

      // Create Logs folder
      final logsDir = Directory('${documentsDirectory!.path}/Memorizer/Logs');
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }

      // File name with date and time
      final now = DateTime.now();
      final dateTime = DateFormat('yyyyMMdd-HHmmss').format(now);
      _currentLogFile = '${logsDir.path}/log-$dateTime.txt';

      // Write header
      final startMessage = 'App started at ${DateFormat('yyyy-MM-dd HH:mm:ss').format(now)}\n';
      await File(_currentLogFile!).writeAsString(startMessage);
    } catch (e) {
      // Ignore logging errors
    }
  }
}

// Returns filter status indicator for the app bar title
Future<String> getFilterStatusText() async {
  bool hasTagFilter = xvTagFilter.isNotEmpty;

  // Virtual folder filters are not user-set filters, don't show (F)
  bool hasUserFilter = xvFilter.isNotEmpty &&
      !virtualFolderFilters.contains(xvFilter);

  // Get Last items setting
  final lastItemsStr =
      await getSetting("Last items") ?? defSettings["Last items"];
  final lastItems = int.tryParse(lastItemsStr) ?? 0;
  bool hasLastItems = lastItems > 0;

  if (hasUserFilter && hasTagFilter) {
    return '(FT) ';
  } else if (hasTagFilter) {
    return '(T) ';
  } else if (hasUserFilter) {
    return '(F) ';
  } else if (hasLastItems) {
    return '($lastItems) ';
  } else {
    return '(All) ';
  }
}