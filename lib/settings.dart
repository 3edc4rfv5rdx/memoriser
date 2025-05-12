// settings.dart
import 'package:flutter/material.dart';

import 'backup.dart';
import 'globals.dart';
import 'reminders.dart'; // Добавляем импорт

// Function to create settings screen
Widget buildSettingsScreen() {
  return _SettingsScreenImpl();
}

// Internal StatefulWidget to manage settings state
class _SettingsScreenImpl extends StatefulWidget {
  const _SettingsScreenImpl({Key? key}) : super(key: key);

  @override
  _SettingsScreenImplState createState() => _SettingsScreenImplState();
}

class _SettingsScreenImplState extends State<_SettingsScreenImpl> {
  String? _currentTheme;
  String? _currentLanguage;
  bool _newestFirst = true;
  int _lastItems = 0; // Last items setting
  String _remindTime = notifTime; // Default remind time
  bool _enableReminders = true; // Add this for reminders setting
  bool _isLoading = true;

  // Temporary values to track changes
  String? _newTheme;
  String? _newLanguage;
  bool? _newNewestFirst;
  int? _newLastItems; // Temporary value for Last items
  String? _newRemindTime; // Temporary remind time
  bool? _newEnableReminders; // Add this for temporary reminders value
  bool _hasChanges = false;

  // Controller for Last items input field
  late TextEditingController _lastItemsController;

  // Controller for remind time input field
  late TextEditingController _remindTimeController;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _lastItemsController.dispose();
    _remindTimeController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    // Load current theme
    final themeValue =
        await getSetting("Color theme") ?? defSettings["Color theme"];

    // Load current language
    final languageValue =
        await getSetting("Language") ?? defSettings["Language"];

    // Load sort order setting
    final newestFirstValue =
        await getSetting("Newest first") ?? defSettings["Newest first"];
    final isNewestFirst = newestFirstValue == "true";

    // Load Last items setting
    final lastItemsValue =
        await getSetting("Last items") ?? defSettings["Last items"];
    final lastItems = int.tryParse(lastItemsValue) ?? 0;

    // Load remind time setting
    final remindTimeValue = await getSetting("Notification time") ?? notifTime;

    // Load enable reminders setting
    final enableRemindersValue =
        await getSetting("Enable reminders") ?? defSettings["Enable reminders"];
    final enableReminders = enableRemindersValue == "true";

    _lastItemsController = TextEditingController(text: lastItems.toString());
    _remindTimeController = TextEditingController(text: remindTimeValue);

    if (mounted) {
      setState(() {
        _currentTheme = themeValue;
        _currentLanguage = languageValue.toLowerCase();
        _newestFirst = isNewestFirst;
        _lastItems = lastItems;
        _remindTime = remindTimeValue;
        _enableReminders = enableReminders; // Initialize the checkbox state

        // Initialize temporary values
        _newTheme = themeValue;
        _newLanguage = languageValue.toLowerCase();
        _newNewestFirst = isNewestFirst;
        _newLastItems = lastItems;
        _newRemindTime = remindTimeValue;
        _newEnableReminders = enableReminders; // Initialize the temporary value

        _isLoading = false;
        _hasChanges = false;
      });
    }
  }

  // Function to check for changes
  void _checkForChanges() {
    setState(() {
      _hasChanges =
          _newTheme != _currentTheme ||
              _newLanguage != _currentLanguage ||
              _newNewestFirst != _newestFirst ||
              _newLastItems != _lastItems ||
              _newRemindTime != _remindTime ||
              _newEnableReminders != _enableReminders; // Add this to the check
    });
  }

  // Save function with improved notifications
  Future<void> _saveChanges() async {
    if (!_hasChanges) {
      okInfoBarBlue(lw('No changes to save'));
      return;
    }

    bool languageOrThemeChanged = false;
    bool reminderSettingsChanged = false;
    List<String> savedSettings = [];

    // Save new language settings if changed
    if (_newLanguage != _currentLanguage && _newLanguage != null) {
      await saveSetting("Language", _newLanguage!);
      savedSettings.add('language');
      languageOrThemeChanged = true;
    }

    // Save new theme settings if changed
    if (_newTheme != _currentTheme && _newTheme != null) {
      await saveSetting("Color theme", _newTheme!);
      savedSettings.add('theme');
      languageOrThemeChanged = true;
    }

    // Save new sort order settings if changed
    if (_newNewestFirst != _newestFirst && _newNewestFirst != null) {
      await saveSetting("Newest first", _newNewestFirst.toString());
      savedSettings.add('sort order');
    }

    // Save Last items setting if changed
    if (_newLastItems != _lastItems && _newLastItems != null) {
      await saveSetting("Last items", _newLastItems.toString());
      savedSettings.add('last items');
    }

    // Save remind time setting if changed
    if (_newRemindTime != _remindTime && _newRemindTime != null) {
      await saveSetting("Notification time", _newRemindTime.toString());
      savedSettings.add('remind time');
      reminderSettingsChanged = true;
    }

    // Save enable reminders setting if changed
    if (_newEnableReminders != _enableReminders &&
        _newEnableReminders != null) {
      await saveSetting("Enable reminders", _newEnableReminders.toString());
      savedSettings.add('enable reminders');
      reminderSettingsChanged = true;
    }

    // Update current values
    setState(() {
      _currentTheme = _newTheme;
      _currentLanguage = _newLanguage;
      _newestFirst = _newNewestFirst ?? _newestFirst;
      _lastItems = _newLastItems ?? _lastItems;
      _remindTime = _newRemindTime ?? _remindTime;
      _enableReminders = _newEnableReminders ?? _enableReminders;
      _hasChanges = false;
    });

    // Reschedule reminders if reminder settings changed
    if (reminderSettingsChanged) {
      if (_newEnableReminders == true) {
        await SimpleNotifications.scheduleReminderCheck();
        okInfoBarBlue(lw('Reminder schedule updated'));
      } else {
        // If reminders are disabled, cancel all scheduled notifications
        await SimpleNotifications.cancelAllNotifications();
        okInfoBarBlue(lw('Reminders disabled'));
      }
    }

    // Show one common notification for all saved settings
    if (savedSettings.isNotEmpty) {
      okInfoBarGreen(lw('Settings saved: ') + savedSettings.join(', '));

      // Give time to see first notification
      await Future.delayed(Duration(milliseconds: 1500));

      // Show restart notification only if language or theme changed
      if (languageOrThemeChanged) {
        okInfoBarOrange(lw('PLEASE RESTART APP'));
      }
    }

    // Return to main screen after notifications
    Future.delayed(Duration(seconds: 2), () {
      Navigator.of(context).pop(true);
    });
  }

  // Fixed version with correct types
  @override
  Widget build(BuildContext context) {
    return PopScope(
      // canPop: false means we want to control back button behavior
      canPop: !_hasChanges,
      // onPopInvokedWithResult returns void, not bool
      onPopInvokedWithResult: (didPop, result) async {
        // If already handled (no changes), do nothing
        if (didPop) return;

        if (_hasChanges) {
          // Use showCustomDialog function from globals.dart for consistent style
          final shouldSave = await showCustomDialog(
            title: lw('Unsaved Changes'),
            content: lw('Do you want to save changes before exiting?'),
            actions: [
              {'label': lw('No'), 'value': false, 'isDestructive': false},
              {
                'label': lw('Yes'),
                'value': true,
                'isDestructive': false,
                'onPressed': null,
                // No additional actions, just return value
              },
            ],
          );

          if (shouldSave == true) {
            await _saveChanges();
          } else {
            // If not saving, just close the screen
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: clUpBar,
          foregroundColor: clText,
          // Customize back button with long press handler
          leading: GestureDetector(
            onLongPress: () => showHelp(10), // ID 10 for back button
            child: IconButton(
              icon: Icon(Icons.arrow_back),
              onPressed: () {
                // Check for changes before exiting
                if (_hasChanges) {
                  // Trigger exit check logic via PopScope
                  Navigator.maybePop(context);
                } else {
                  // If no changes, just exit
                  Navigator.pop(context);
                }
              },
            ),
          ),
          title: GestureDetector(
            onLongPress: () => showHelp(60), // ID 60 for settings screen title
            child: Text(
              lw('Settings'),
              style: TextStyle(
                fontSize: fsLarge,
                color: clText,
                fontWeight: fwBold,
              ),
            ),
          ),
          actions: [

// Обновленная часть settings.dart для меню бэкапа
            GestureDetector(
              onLongPress: () => showHelp(44), // ID 44 для кнопки бэкапа
              child: PopupMenuButton<String>(
                icon: Icon(Icons.save_alt), // Иконка сохранения
                tooltip: lw('Backup & Restore'), // Обновленный текст подсказки
                color: clMenu,
                itemBuilder: (BuildContext context) {
                  return [
                    PopupMenuItem<String>(
                      value: 'create_backup',
                      child: GestureDetector(
                        onLongPress: () => showHelp(45), // ID 45 для пункта создания бэкапа
                        child: Text(
                          lw('Create DB backup'),
                          style: TextStyle(color: clText),
                        ),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'restore_backup',
                      child: GestureDetector(
                        onLongPress: () => showHelp(46), // ID 46 для восстановления
                        child: Text(
                          lw('Restore from DB backup'),
                          style: TextStyle(color: clText),
                        ),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'export_csv',
                      child: GestureDetector(
                        onLongPress: () => showHelp(47), // ID 47 для экспорта CSV
                        child: Text(
                          lw('Export to CSV'),
                          style: TextStyle(color: clText),
                        ),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'restore_csv',
                      child: GestureDetector(
                        onLongPress: () => showHelp(48), // ID 48 для восстановления из CSV
                        child: Text(
                          lw('Restore from CSV'),
                          style: TextStyle(color: clText),
                        ),
                      ),
                    ),
                  ];
                },
                onSelected: (String result) async {
                  if (result == 'create_backup') {
                    await createBackup();
                  } else if (result == 'export_csv') {
                    await exportToCSV();
                  } else if (result == 'restore_backup') {
                    await restoreBackup();
                  } else if (result == 'restore_csv') {
                    await restoreFromCSV();
                  }
                },
              ),
            ),

            // Save button in AppBar (disk icon) with long press handler
            GestureDetector(
              onLongPress: () => showHelp(12), // ID 12 for save button
              child: IconButton(
                icon: Icon(Icons.save),
                tooltip: lw('Save'),
                onPressed: _saveChanges,
              ),
            ),
          ],
        ),
        body:
        _isLoading
            ? Center(child: CircularProgressIndicator())
            : Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView(
            children: [
              // Language selector row
              _buildSettingsRow(
                label: lw('App language'),
                child: _buildLanguageDropdown(),
                helpId:
                100, // Keep existing ID 100 for language setting
              ),

              SizedBox(height: 10),

              // Color theme selector row
              _buildSettingsRow(
                label: lw('Color theme'),
                child: _buildThemeDropdown(),
                helpId: 101, // Keep existing ID 101 for theme setting
              ),

              SizedBox(height: 10),

              // Newest first checkbox row
              _buildSettingsRow(
                label: lw('Newest first'),
                child: _buildSortOrderCheckbox(),
                helpId:
                102, // Keep existing ID 102 for sort order setting
              ),

              SizedBox(height: 10),

              // Last items row
              _buildSettingsRow(
                label: lw('Last items'),
                child: _buildLastItemsField(),
                helpId:
                103, // Keep existing ID 103 for last items setting
              ),

              SizedBox(height: 10),

              // Enable reminders checkbox row
              _buildSettingsRow(
                label: lw('Enable reminders'),
                child: _buildEnableRemindersCheckbox(),
                helpId: 105, // New ID 105 for enable reminders setting
              ),

              SizedBox(height: 10),

              // Notification time row (only show if reminders enabled)
              if (_newEnableReminders == true)
                _buildSettingsRow(
                  label: lw('Notification time'),
                  child: _buildRemindTimeField(),
                  helpId:
                  104, // Keep existing ID 104 for remind time setting
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Function to build a settings row with label and control
  Widget _buildSettingsRow({
    required String label,
    required Widget child,
    int helpId = 11,
  }) {
    return GestureDetector(
      onLongPress: () => showHelp(helpId),
      child: Row(
        children: [
          // Left side - Label (60%)
          Expanded(
            flex: 60,
            child: Text(
              label,
              style: TextStyle(color: clText, fontSize: fsMedium),
            ),
          ),
          // Right side - Control (40%)
          Expanded(flex: 40, child: child),
        ],
      ),
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
            // Only update temporary value without saving
            setState(() {
              _newLanguage = newValue;
            });
            _checkForChanges();
          }
        },
        items:
        langNames.entries.map<DropdownMenuItem<String>>((entry) {
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
            // Only update temporary value without saving
            setState(() {
              _newTheme = newValue;
            });
            _checkForChanges();
          }
        },
        items:
        appTHEMES.map<DropdownMenuItem<String>>((String value) {
          return DropdownMenuItem<String>(value: value, child: Text(value));
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
            // Only update temporary value without saving
            setState(() {
              _newNewestFirst = value;
            });
            _checkForChanges();
          }
        },
      ),
    );
  }

  // Function for Last items input field
  Widget _buildLastItemsField() {
    return Container(
      decoration: BoxDecoration(
        color: clFill,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: clUpBar),
      ),
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: TextField(
        controller: _lastItemsController,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.left,
        style: TextStyle(color: clText),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: '0',
          hintStyle: TextStyle(color: clText),
        ),
        onChanged: (value) {
          final parsedValue = int.tryParse(value) ?? 0;
          if (parsedValue >= 0) {
            // Check that value is non-negative
            setState(() {
              _newLastItems = parsedValue;
            });
            _checkForChanges();
          }
        },
      ),
    );
  }

  // Function for enable reminders checkbox
  Widget _buildEnableRemindersCheckbox() {
    return Container(
      alignment: Alignment.centerLeft,
      child: Checkbox(
        value: _newEnableReminders,
        activeColor: clUpBar,
        checkColor: clText,
        onChanged: (bool? value) {
          if (value != null && value != _newEnableReminders) {
            setState(() {
              _newEnableReminders = value;
            });
            _checkForChanges();
          }
        },
      ),
    );
  }

  // Function for Notification time input field and clock button outside
  Widget _buildRemindTimeField() {
    return Row(
      children: [
        // Text input field (takes most of the space)
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: clFill,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: clUpBar),
            ),
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: TextField(
              controller: _remindTimeController,
              keyboardType: TextInputType.text,
              textAlign: TextAlign.left,
              style: TextStyle(color: clText),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: '07:30',
                hintStyle: TextStyle(color: clText),
              ),
              onChanged: (value) {
                setState(() {
                  _newRemindTime = value;
                });
                _checkForChanges();
              },
            ),
          ),
        ), // Clock icon button (outside the text field)
        Container(
          margin: EdgeInsets.only(left: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => _selectTime(context),
            child: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
              child: Icon(Icons.access_time, color: clText, size: 24),
            ),
          ),
        ),
      ],
    );
  }

  // Time picker function with styled buttons
  Future<void> _selectTime(BuildContext context) async {
    // Parse current time or use default
    final List<String> timeParts = (_newRemindTime ?? notifTime).split(":");
    final int hour = int.tryParse(timeParts[0]) ?? 10;
    final int minute = int.tryParse(timeParts[1]) ?? 0;

    final TimeOfDay initialTime = TimeOfDay(hour: hour, minute: minute);

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: Theme.of(context).copyWith(
            timePickerTheme: TimePickerThemeData(
              backgroundColor: clMenu,
              hourMinuteTextColor: clText,
              dayPeriodTextColor: clText,
              dialHandColor: clUpBar,
              dialBackgroundColor: clFill,
              dialTextColor: clText,
              entryModeIconColor: clText,
            ),
            colorScheme: ColorScheme.dark(
              primary: clUpBar,
              onPrimary: clText,
              surface: clMenu,
              onSurface: clText,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: clText,
                backgroundColor: clUpBar,
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      // Format to HH:MM
      final String hour = picked.hour.toString().padLeft(2, '0');
      final String minute = picked.minute.toString().padLeft(2, '0');
      final String formattedTime = "$hour:$minute";

      setState(() {
        _newRemindTime = formattedTime;
        _remindTimeController.text = formattedTime;
      });
      _checkForChanges();
    }
  }
}