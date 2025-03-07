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
  bool _settingsChanged = false;

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
        _settingsChanged = false;
      });
    }
  }

  Future<void> _applyChanges() async {
    if (_settingsChanged) {
      // Перечитываем локализацию, если выбран новый язык
      if (_currentLanguage != null) {
        await readLocale(_currentLanguage!);
      }

      // Перестраиваем всё приложение, применяя новые настройки
      widget.rebuildApp();
      okInfoBarGreen(lw('Settings applied'));
    } else {
      okInfoBarBlue(lw('No changes to apply'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: clUpBar,
        foregroundColor: clText,
        title: Text(lw('Settings')),
        actions: [
          // Добавляем кнопку применения в AppBar - делаем её более заметной
          Container(
            margin: EdgeInsets.only(right: 10),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              icon: Icon(Icons.check),
              label: Text(lw('Apply')),
              onPressed: _applyChanges,
            ),
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
            // Сохраняем выбранный язык
            await saveSetting("Language", newValue.toUpperCase());

            // Обновляем состояние локально
            setState(() {
              _currentLanguage = newValue;
              _settingsChanged = true;
            });

            // Показываем сообщение, что настройки изменены
            okInfoBarBlue(lw('Language changed. Apply to see changes.'));
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
            // Сохраняем выбранную тему
            await saveSetting("Color theme", newValue);

            // Обновляем состояние локально
            setState(() {
              _currentTheme = newValue;
              _settingsChanged = true;
            });

            // Показываем сообщение, что настройки изменены
            okInfoBarBlue(lw('Theme changed. Apply to see changes.'));
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
            await saveSetting("Newest first", value.toString());
            setState(() {
              _newestFirst = value;
              _settingsChanged = true;
            });

            // Показываем сообщение, что настройки изменены
            okInfoBarBlue(lw('Sort order changed. Apply to see changes.'));
          }
        },
      ),
    );
  }
}