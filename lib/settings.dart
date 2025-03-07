// settings.dart
import 'package:flutter/material.dart';
import 'globals.dart';

class SettingsPage extends StatefulWidget {
  final Function rebuildApp;

  const SettingsPage({Key? key, required this.rebuildApp}) : super(key: key);

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String? _currentTheme;
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

    // Load sort order setting
    final newestFirstValue = await getSetting("Newest first") ?? defSettings["Newest first"];
    final isNewestFirst = newestFirstValue == "true";

    if (mounted) {
      setState(() {
        _currentTheme = themeValue;
        _newestFirst = isNewestFirst;
        _isLoading = false;
      });
    }
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
            // Color theme selector row
            Row(
              children: [
                // Left side - Label (60%)
                Expanded(
                  flex: 60,
                  child: Text(
                    lw('Color theme'),
                    style: TextStyle(
                      color: clText,
                      fontSize: fsMedium,
                    ),
                  ),
                ),
                // Right side - Dropdown (40%)
                Expanded(
                  flex: 40,
                  child: Container(
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
                        if (newValue != null) {
                          await saveSetting("Color theme", newValue);
                          setState(() {
                            _currentTheme = newValue;
                          });
                          widget.rebuildApp();
                        }
                      },
                      items: appTHEMES.map<DropdownMenuItem<String>>((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),

            SizedBox(height: 10),

            // Newest first checkbox row
            Row(
              children: [
                // Left side - Label (60%)
                Expanded(
                  flex: 60,
                  child: Text(
                    lw('Newest first'),
                    style: TextStyle(
                      color: clText,
                      fontSize: fsMedium,
                    ),
                  ),
                ),
                // Right side - Checkbox (40%)
                Expanded(
                  flex: 40,
                  child: Container(
                    alignment: Alignment.centerLeft,
                    child: Checkbox(
                      value: _newestFirst,
                      activeColor: clUpBar,
                      checkColor: clText,
                      onChanged: (bool? value) async {
                        if (value != null) {
                          await saveSetting("Newest first", value.toString());
                          setState(() {
                            _newestFirst = value;
                          });
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
