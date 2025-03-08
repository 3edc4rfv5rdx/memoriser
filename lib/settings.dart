// settings.dart
import 'package:flutter/material.dart';
import 'globals.dart';

// Функция для создания экрана настроек
Widget buildSettingsScreen() {
  return _SettingsScreenImpl();
}

// Внутренний StatefulWidget для управления состоянием настроек
class _SettingsScreenImpl extends StatefulWidget {
  const _SettingsScreenImpl({Key? key}) : super(key: key);

  @override
  _SettingsScreenImplState createState() => _SettingsScreenImplState();
}

class _SettingsScreenImplState extends State<_SettingsScreenImpl> {
  String? _currentTheme;
  String? _currentLanguage;
  bool _newestFirst = true;
  bool _isLoading = true;

  // Временные значения для отслеживания изменений
  String? _newTheme;
  String? _newLanguage;
  bool? _newNewestFirst;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    // Загрузка текущей темы
    final themeValue = await getSetting("Color theme") ?? defSettings["Color theme"];

    // Загрузка текущего языка
    final languageValue = await getSetting("Language") ?? defSettings["Language"];

    // Загрузка настройки сортировки
    final newestFirstValue = await getSetting("Newest first") ?? defSettings["Newest first"];
    final isNewestFirst = newestFirstValue == "true";

    if (mounted) {
      setState(() {
        _currentTheme = themeValue;
        _currentLanguage = languageValue.toLowerCase();
        _newestFirst = isNewestFirst;

        // Инициализация временных значений
        _newTheme = themeValue;
        _newLanguage = languageValue.toLowerCase();
        _newNewestFirst = isNewestFirst;

        _isLoading = false;
        _hasChanges = false;
      });
    }
  }

  // Функция для проверки наличия изменений
  void _checkForChanges() {
    setState(() {
      _hasChanges = _newTheme != _currentTheme ||
          _newLanguage != _currentLanguage ||
          _newNewestFirst != _newestFirst;
    });
  }

  // Функция сохранения и возврата
  Future<void> _saveChanges() async {
    if (!_hasChanges) {
      okInfoBarBlue(lw('No changes to save'));
      return;
    }

    // Сохраняем новые настройки языка, если изменились
    if (_newLanguage != _currentLanguage && _newLanguage != null) {
      await saveSetting("Language", _newLanguage!.toUpperCase());
      okInfoBarGreen(lw('Language settings saved'));
    }

    // Сохраняем новые настройки темы, если изменились
    if (_newTheme != _currentTheme && _newTheme != null) {
      await saveSetting("Color theme", _newTheme!);
      okInfoBarGreen(lw('Theme settings saved'));
    }

    // Сохраняем новые настройки сортировки, если изменились
    if (_newNewestFirst != _newestFirst && _newNewestFirst != null) {
      await saveSetting("Newest first", _newNewestFirst.toString());
      okInfoBarGreen(lw('Sort order settings saved'));
    }

    // Обновляем текущие значения
    setState(() {
      _currentTheme = _newTheme;
      _currentLanguage = _newLanguage;
      _newestFirst = _newNewestFirst ?? _newestFirst;
      _hasChanges = false;
    });

    // Показываем уведомление о перезапуске
    okInfoBarOrange(lw('Please restart app'));

    // Возвращаемся на главный экран
    Future.delayed(Duration(seconds: 1), () {
      Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // Предупреждаем о несохраненных изменениях при попытке выхода
      onWillPop: () async {
        if (_hasChanges) {
          final shouldSave = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(lw('Unsaved Changes')),
              content: Text(lw('Do you want to save changes before exiting?')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(lw('No')),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(lw('Yes')),
                ),
              ],
            ),
          );

          if (shouldSave == true) {
            await _saveChanges();
          }
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: clUpBar,
          foregroundColor: clText,
          title: Text(lw('Settings')),
          actions: [
            // Кнопка Save в AppBar (дискета)
            IconButton(
              icon: Icon(Icons.save),
              tooltip: lw('Save'),
              onPressed: _saveChanges,
            ),
          ],
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
        value: _newLanguage,
        isExpanded: true,
        underline: Container(),
        dropdownColor: clMenu,
        icon: Icon(Icons.arrow_drop_down, color: clText),
        style: TextStyle(color: clText),
        onChanged: (String? newValue) {
          if (newValue != null && newValue != _newLanguage) {
            // Только обновляем временное значение без сохранения
            setState(() {
              _newLanguage = newValue;
            });
            _checkForChanges();
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
        value: _newTheme,
        isExpanded: true,
        underline: Container(),
        dropdownColor: clMenu,
        icon: Icon(Icons.arrow_drop_down, color: clText),
        style: TextStyle(color: clText),
        onChanged: (String? newValue) {
          if (newValue != null && newValue != _newTheme) {
            // Только обновляем временное значение без сохранения
            setState(() {
              _newTheme = newValue;
            });
            _checkForChanges();
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
        value: _newNewestFirst,
        activeColor: clUpBar,
        checkColor: clText,
        onChanged: (bool? value) {
          if (value != null && value != _newNewestFirst) {
            // Только обновляем временное значение без сохранения
            setState(() {
              _newNewestFirst = value;
            });
            _checkForChanges();
          }
        },
      ),
    );
  }
}