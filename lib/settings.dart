// settings.dart
import 'package:flutter/material.dart';
import 'globals.dart';

// Используем более уникальное имя для функции
Widget buildSettingsScreen({required Function rebuildApp}) {
  return _SettingsScreenImpl(rebuildApp: rebuildApp);
}

// Internal stateful widget to manage settings state
class _SettingsScreenImpl extends StatefulWidget {
  final Function rebuildApp;

  const _SettingsScreenImpl({Key? key, required this.rebuildApp}) : super(key: key);

  @override
  _SettingsScreenImplState createState() => _SettingsScreenImplState();
}

class _SettingsScreenImplState extends State<_SettingsScreenImpl> {
  String? _currentTheme;
  String? _currentLanguage;
  bool _newestFirst = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    // Load current theme
    final themeValue = await getSetting("Color theme") ?? defSettings["Color theme"];

    // Load current language
    final languageValue = await getSetting("Language") ?? defSettings["Language"];

    // Load sort order setting
    final newestFirstValue = await getSetting("Newest first") ?? defSettings["Newest first"];
    final isNewestFirst = newestFirstValue == "true";

    if (mounted) {
      setState(() {
        _currentTheme = themeValue;
        _currentLanguage = languageValue.toLowerCase();
        _newestFirst = isNewestFirst;
        _isLoading = false;
      });
    }
  }

  // Показать уведомление напрямую
  void _showNotification(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            fontSize: fsSmall,
            color: Colors.white,
          ),
        ),
        backgroundColor: color,
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Функция для применения изменений языка
  Future<void> _applyLanguageChange(String newLanguage) async {
    // Сохраняем новый язык
    await saveSetting("Language", newLanguage.toUpperCase());

    // Перечитываем языковой файл
    await readLocale(newLanguage);

    // Обновляем состояние
    setState(() {
      _currentLanguage = newLanguage;
    });

    // Показываем уведомление
    _showNotification(lw('Language changed'), Colors.green);

    // Небольшая задержка перед перестроением приложения
    await Future.delayed(Duration(milliseconds: 500));

    // Полное перестроение приложения для применения языка
    widget.rebuildApp();
  }

  // Функция для применения изменений темы
  Future<void> _applyThemeChange(String newTheme) async {
    // Сохраняем новую тему
    await saveSetting("Color theme", newTheme);

    // Применяем цвета темы
    setThemeColors(newTheme);

    // Обновляем состояние
    setState(() {
      _currentTheme = newTheme;
    });

    // Показываем уведомление
    _showNotification(lw('Theme changed'), Colors.green);

    // Небольшая задержка перед перестроением приложения
    await Future.delayed(Duration(milliseconds: 500));

    // Перестраиваем приложение для применения темы
    widget.rebuildApp();
  }

  // Функция для применения изменений сортировки
  Future<void> _applySortOrderChange(bool newValue) async {
    // Сохраняем новое значение
    await saveSetting("Newest first", newValue.toString());

    // Обновляем состояние
    setState(() {
      _newestFirst = newValue;
    });

    // Показываем уведомление
    _showNotification(lw('Sort order changed'), Colors.green);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: clUpBar,
        foregroundColor: clText,
        title: Text(lw('Settings')),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Language selector row
            _buildSettingsRow(
              label: lw('App language'),
              child: _buildLanguageDropdown(),
            ),

            SizedBox(height: 10),

            // Color theme selector row
            _buildSettingsRow(
              label: lw('Color theme'),
              child: _buildThemeDropdown(),
            ),

            SizedBox(height: 10),

            // Newest first checkbox row
            _buildSettingsRow(
              label: lw('Newest first'),
              child: _buildSortOrderCheckbox(),
            ),
          ],
        ),
      ),
    );
  }

  // Function to build a settings row with label and control
  Widget _buildSettingsRow({required String label, required Widget child}) {
    return Row(
      children: [
        // Left side - Label (60%)
        Expanded(
          flex: 60,
          child: Text(
            label,
            style: TextStyle(
              color: clText,
              fontSize: fsMedium,
            ),
          ),
        ),
        // Right side - Control (40%)
        Expanded(
          flex: 40,
          child: child,
        ),
      ],
    );
  }

  // Function to build language dropdown
  Widget _buildLanguageDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: clFill,
        borderRadius: BorderRadius.circular(4),
      ),
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: DropdownButton<String>(
        value: _currentLanguage,
        isExpanded: true,
        underline: Container(),
        dropdownColor: clMenu,
        icon: Icon(Icons.arrow_drop_down, color: clText),
        style: TextStyle(color: clText),
        onChanged: (String? newValue) async {
          if (newValue != null && newValue != _currentLanguage) {
            // Непосредственно применяем изменение языка
            await _applyLanguageChange(newValue);
          }
        },
        items: langNames.entries.map<DropdownMenuItem<String>>((entry) {
          return DropdownMenuItem<String>(
            value: entry.key,
            child: Text(entry.value),
          );
        }).toList(),
      ),
    );
  }

  // Function to build theme dropdown
  Widget _buildThemeDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: clFill,
        borderRadius: BorderRadius.circular(4),
      ),
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: DropdownButton<String>(
        value: _currentTheme,
        isExpanded: true,
        underline: Container(),
        dropdownColor: clMenu,
        icon: Icon(Icons.arrow_drop_down, color: clText),
        style: TextStyle(color: clText),
        onChanged: (String? newValue) async {
          if (newValue != null && newValue != _currentTheme) {
            // Непосредственно применяем изменение темы
            await _applyThemeChange(newValue);
          }
        },
        items: appTHEMES.map<DropdownMenuItem<String>>((String value) {
          return DropdownMenuItem<String>(
            value: value,
            child: Text(value),
          );
        }).toList(),
      ),
    );
  }

  // Function to build sort order checkbox
  Widget _buildSortOrderCheckbox() {
    return Container(
      alignment: Alignment.centerLeft,
      child: Checkbox(
        value: _newestFirst,
        activeColor: clUpBar,
        checkColor: clText,
        onChanged: (bool? value) async {
          if (value != null && value != _newestFirst) {
            // Непосредственно применяем изменение порядка сортировки
            await _applySortOrderChange(value);
          }
        },
      ),
    );
  }
}