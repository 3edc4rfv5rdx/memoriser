// settings.dart
import 'package:flutter/material.dart';

import 'backup.dart';
import 'globals.dart';
import 'reminders.dart';

// Function to create settings screen
Widget buildSettingsScreen() {
  return _SettingsScreenImpl();
}

// Internal StatefulWidget to manage settings state
class _SettingsScreenImpl extends StatefulWidget {
  const _SettingsScreenImpl();

  @override
  _SettingsScreenImplState createState() => _SettingsScreenImplState();
}

class _SettingsScreenImplState extends State<_SettingsScreenImpl> {
  String? _currentTheme;
  String? _currentLanguage;
  bool _newestFirst = true;
  int _lastItems = 0;
  bool _enableReminders = true;
  bool _enableDailyReminders = true;
  bool _debugLogs = false;
  bool _isLoading = true;

  // Sound settings
  String? _defaultSound;
  String? _defaultDailySound;
  List<Map<String, String>> _systemSounds = [];

  // Temporary values to track changes
  String? _newTheme;
  String? _newLanguage;
  bool? _newNewestFirst;
  int? _newLastItems;
  bool? _newEnableReminders;
  bool? _newEnableDailyReminders;
  bool? _newDebugLogs;
  String? _newDefaultSound;
  String? _newDefaultDailySound;
  bool _hasChanges = false;

  // Controller for Last items input field
  late TextEditingController _lastItemsController;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _lastItemsController.dispose();
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

    // Load enable reminders setting
    final enableRemindersValue =
        await getSetting("Enable reminders") ?? defSettings["Enable reminders"];
    final enableReminders = enableRemindersValue == "true";

    // Load enable daily reminders setting
    final enableDailyRemindersValue =
        await getSetting("Enable daily reminders") ?? defSettings["Enable daily reminders"];
    final enableDailyReminders = enableDailyRemindersValue == "true";

    // Load debug logs setting
    final debugLogsValue =
        await getSetting("Debug logs") ?? defSettings["Debug logs"];
    final debugLogs = debugLogsValue == "true";

    // Load default sound settings
    final defaultSoundValue = await getSetting("Default sound");
    final defaultDailySoundValue = await getSetting("Default daily sound");

    // Load system sounds
    final systemSounds = await SimpleNotifications.getSystemSounds();

    _lastItemsController = TextEditingController(text: lastItems.toString());

    if (mounted) {
      setState(() {
        _currentTheme = themeValue;
        _currentLanguage = languageValue.toLowerCase();
        _newestFirst = isNewestFirst;
        _lastItems = lastItems;
        _enableReminders = enableReminders;
        _enableDailyReminders = enableDailyReminders;
        _debugLogs = debugLogs;
        _defaultSound = defaultSoundValue;
        _defaultDailySound = defaultDailySoundValue;
        _systemSounds = systemSounds;

        // Initialize temporary values
        _newTheme = themeValue;
        _newLanguage = languageValue.toLowerCase();
        _newNewestFirst = isNewestFirst;
        _newLastItems = lastItems;
        _newEnableReminders = enableReminders;
        _newEnableDailyReminders = enableDailyReminders;
        _newDebugLogs = debugLogs;
        _newDefaultSound = defaultSoundValue;
        _newDefaultDailySound = defaultDailySoundValue;

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
              _newEnableReminders != _enableReminders ||
              _newEnableDailyReminders != _enableDailyReminders ||
              _newDebugLogs != _debugLogs ||
              _newDefaultSound != _defaultSound ||
              _newDefaultDailySound != _defaultDailySound;
    });
  }

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

    // Save enable reminders setting if changed
    if (_newEnableReminders != _enableReminders &&
        _newEnableReminders != null) {
      await saveSetting("Enable reminders", _newEnableReminders.toString());
      savedSettings.add('enable reminders');
      reminderSettingsChanged = true;
    }

    // Save enable daily reminders setting if changed
    if (_newEnableDailyReminders != _enableDailyReminders &&
        _newEnableDailyReminders != null) {
      await saveSetting("Enable daily reminders", _newEnableDailyReminders.toString());
      savedSettings.add('enable daily reminders');
      // TODO: Handle daily reminders rescheduling when Kotlin part is implemented
    }

    // Save debug logs setting if changed
    if (_newDebugLogs != _debugLogs && _newDebugLogs != null) {
      await saveSetting("Debug logs", _newDebugLogs.toString());
      savedSettings.add('debug logs');
    }

    // Save default sound settings if changed
    if (_newDefaultSound != _defaultSound) {
      if (_newDefaultSound != null) {
        await saveSetting("Default sound", _newDefaultSound!);
      } else {
        await saveSetting("Default sound", "");
      }
      savedSettings.add('default sound');
    }

    if (_newDefaultDailySound != _defaultDailySound) {
      if (_newDefaultDailySound != null) {
        await saveSetting("Default daily sound", _newDefaultDailySound!);
      } else {
        await saveSetting("Default daily sound", "");
      }
      savedSettings.add('default daily sound');
    }

    // Update current values
    setState(() {
      _currentTheme = _newTheme;
      _currentLanguage = _newLanguage;
      _newestFirst = _newNewestFirst ?? _newestFirst;
      _lastItems = _newLastItems ?? _lastItems;
      _enableReminders = _newEnableReminders ?? _enableReminders;
      _enableDailyReminders = _newEnableDailyReminders ?? _enableDailyReminders;
      _debugLogs = _newDebugLogs ?? _debugLogs;
      _defaultSound = _newDefaultSound;
      _defaultDailySound = _newDefaultDailySound;
      _hasChanges = false;
    });

    // Handle reminder changes
    if (reminderSettingsChanged) {
      if (_newEnableReminders == false) {
        // If reminders are disabled, cancel all scheduled notifications
        try {
          await SimpleNotifications.cancelAllNotifications();
          myPrint('All reminders cancelled - reminders disabled');
          okInfoBarBlue(lw('Reminders disabled'));
        } catch (e) {
          myPrint('Error cancelling reminders: $e');
          okInfoBarRed(lw('Error disabling reminders'));
        }
      } else if (_newEnableReminders == true) {
        // НОВОЕ: If reminders are enabled, reschedule all reminders
        try {
          myPrint('Rescheduling all reminders - reminders enabled...');
          await SimpleNotifications.rescheduleAllReminders();
          myPrint('All reminders rescheduled successfully');
          okInfoBarGreen(lw('Reminders enabled and scheduled'));
        } catch (e) {
          myPrint('Error rescheduling reminders: $e');
          okInfoBarRed(lw('Error enabling reminders'));
        }
      }
    }

    // Show one common notification for all saved settings (only if no reminder messages shown)
    if (savedSettings.isNotEmpty && !reminderSettingsChanged) {
      okInfoBarGreen(lw('Settings saved: ') + savedSettings.join(', '));
    } else if (savedSettings.isNotEmpty && reminderSettingsChanged) {
      // Give time for reminder message to be seen, then show general save message
      await Future.delayed(Duration(milliseconds: 2000));
      okInfoBarGreen(lw('Settings saved: ') + savedSettings.join(', '));
    }

    // Give time to see first notification
    await Future.delayed(Duration(milliseconds: 1500));

    // Show restart notification only if language or theme changed
    if (languageOrThemeChanged) {
      okInfoBarOrange(lw('PLEASE RESTART APP'));
    }

    // Return to main screen after notifications
    Future.delayed(Duration(seconds: 2), () {
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (_hasChanges) {
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
              },
            ],
          );

          if (shouldSave == true) {
            await _saveChanges();
          } else {
            if (mounted) Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: clUpBar,
          foregroundColor: clText,
          leading: GestureDetector(
            onLongPress: () => showHelp(10),
            child: IconButton(
              icon: Icon(Icons.arrow_back),
              onPressed: () {
                if (_hasChanges) {
                  Navigator.maybePop(context);
                } else {
                  Navigator.pop(context);
                }
              },
            ),
          ),
          title: GestureDetector(
            onLongPress: () => showHelp(60),
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
            GestureDetector(
              onLongPress: () => showHelp(44),
              child: PopupMenuButton<String>(
                icon: Icon(Icons.save_alt),
                tooltip: lw('Backup & Restore'),
                color: clMenu,
                itemBuilder: (BuildContext context) {
                  return [
                    PopupMenuItem<String>(
                      value: 'create_backup',
                      child: GestureDetector(
                        onLongPress: () => showHelp(45),
                        child: Text(
                          lw('Create DB backup'),
                          style: TextStyle(color: clText),
                        ),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'restore_backup',
                      child: GestureDetector(
                        onLongPress: () => showHelp(46),
                        child: Text(
                          lw('Restore from DB backup'),
                          style: TextStyle(color: clText),
                        ),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'export_csv',
                      child: GestureDetector(
                        onLongPress: () => showHelp(47),
                        child: Text(
                          lw('Export to CSV'),
                          style: TextStyle(color: clText),
                        ),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'restore_csv',
                      child: GestureDetector(
                        onLongPress: () => showHelp(48),
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
            GestureDetector(
              onLongPress: () => showHelp(12),
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
                helpId: 100,
              ),

              SizedBox(height: 10),

              // Color theme selector row
              _buildSettingsRow(
                label: lw('Color theme'),
                child: _buildThemeDropdown(),
                helpId: 101,
              ),

              SizedBox(height: 10),

              // Newest first checkbox row
              _buildSettingsRow(
                label: lw('Newest first'),
                child: _buildSortOrderCheckbox(),
                helpId: 102,
              ),

              SizedBox(height: 10),

              // Last items row
              _buildSettingsRow(
                label: lw('Last items'),
                child: _buildLastItemsField(),
                helpId: 103,
              ),

              SizedBox(height: 10),

              // Enable reminders checkbox row
              _buildSettingsRow(
                label: lw('Enable reminders'),
                child: _buildEnableRemindersCheckbox(),
                helpId: 105,
              ),

              SizedBox(height: 10),

              // Enable daily reminders checkbox row
              _buildSettingsRow(
                label: lw('Enable daily reminders'),
                child: _buildEnableDailyRemindersCheckbox(),
                helpId: 107,
              ),

              SizedBox(height: 10),

              // Default sound for one-time reminders
              _buildSettingsRow(
                label: lw('Default sound'),
                child: _buildSoundSelector(isDaily: false),
                helpId: 108,
              ),

              SizedBox(height: 10),

              // Default sound for daily reminders
              _buildSettingsRow(
                label: lw('Default daily sound'),
                child: _buildSoundSelector(isDaily: true),
                helpId: 109,
              ),

              SizedBox(height: 10),

              // Debug logs checkbox row
              _buildSettingsRow(
                label: lw('Debug logs'),
                child: _buildDebugLogsCheckbox(),
                helpId: 106,
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
          Expanded(
            flex: 60,
            child: Text(
              label,
              style: TextStyle(color: clText, fontSize: fsMedium),
            ),
          ),
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

  // Function for enable daily reminders checkbox
  Widget _buildEnableDailyRemindersCheckbox() {
    return Container(
      alignment: Alignment.centerLeft,
      child: Checkbox(
        value: _newEnableDailyReminders,
        activeColor: clUpBar,
        checkColor: clText,
        onChanged: (bool? value) {
          if (value != null && value != _newEnableDailyReminders) {
            setState(() {
              _newEnableDailyReminders = value;
            });
            _checkForChanges();
          }
        },
      ),
    );
  }

  // Function to build debug logs checkbox
  Widget _buildDebugLogsCheckbox() {
    return Container(
      alignment: Alignment.centerLeft,
      child: Checkbox(
        value: _newDebugLogs,
        activeColor: clUpBar,
        checkColor: clText,
        onChanged: (bool? value) {
          if (value != null && value != _newDebugLogs) {
            setState(() {
              _newDebugLogs = value;
            });
            _checkForChanges();
          }
        },
      ),
    );
  }

  // Function to build sound selector
  Widget _buildSoundSelector({required bool isDaily}) {
    final currentSound = isDaily ? _newDefaultDailySound : _newDefaultSound;
    final soundName = _getSoundName(currentSound);

    return GestureDetector(
      onTap: () => _showSoundPicker(isDaily: isDaily),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: clFill,
          border: Border.all(color: clUpBar),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                soundName,
                style: TextStyle(color: clText, fontSize: fsMedium),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (currentSound != null)
                  GestureDetector(
                    onTap: () => SimpleNotifications.playSound(soundUri: currentSound),
                    child: Icon(Icons.play_arrow, color: clText, size: 20),
                  ),
                SizedBox(width: 4),
                Icon(Icons.arrow_drop_down, color: clText),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Get sound name from URI
  String _getSoundName(String? soundUri) {
    if (soundUri == null || soundUri.isEmpty) return lw('Default');
    for (var sound in _systemSounds) {
      if (sound['uri'] == soundUri) {
        return sound['name'] ?? lw('Unknown');
      }
    }
    // If it's a file path, show just the filename
    if (soundUri.startsWith('/')) {
      return soundUri.split('/').last;
    }
    return lw('Default');
  }

  // Show sound picker dialog
  void _showSoundPicker({required bool isDaily}) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: clBgrnd,
          title: Text(
            lw('Select Sound'),
            style: TextStyle(color: clText),
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView.builder(
              itemCount: _systemSounds.length + 1, // +1 for "Default" option
              itemBuilder: (context, index) {
                if (index == 0) {
                  // Default option
                  final isSelected = isDaily
                      ? (_newDefaultDailySound == null || _newDefaultDailySound!.isEmpty)
                      : (_newDefaultSound == null || _newDefaultSound!.isEmpty);
                  return ListTile(
                    leading: Icon(Icons.notifications, color: clText),
                    title: Text(lw('Default'), style: TextStyle(color: clText)),
                    trailing: isSelected
                        ? Icon(Icons.check, color: Colors.green)
                        : null,
                    onTap: () {
                      setState(() {
                        if (isDaily) {
                          _newDefaultDailySound = null;
                        } else {
                          _newDefaultSound = null;
                        }
                      });
                      _checkForChanges();
                      Navigator.pop(context);
                    },
                  );
                }

                final sound = _systemSounds[index - 1];
                final isSelected = isDaily
                    ? _newDefaultDailySound == sound['uri']
                    : _newDefaultSound == sound['uri'];

                return ListTile(
                  leading: Icon(Icons.music_note, color: clText),
                  title: Text(
                    sound['name'] ?? '',
                    style: TextStyle(color: clText),
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.play_arrow, color: clText),
                        onPressed: () {
                          SimpleNotifications.playSound(soundUri: sound['uri']);
                        },
                      ),
                      if (isSelected) Icon(Icons.check, color: Colors.green),
                    ],
                  ),
                  onTap: () {
                    SimpleNotifications.stopSound();
                    setState(() {
                      if (isDaily) {
                        _newDefaultDailySound = sound['uri'];
                      } else {
                        _newDefaultSound = sound['uri'];
                      }
                    });
                    _checkForChanges();
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                SimpleNotifications.stopSound();
                Navigator.pop(context);
              },
              child: Text(lw('Cancel'), style: TextStyle(color: clText)),
            ),
          ],
        );
      },
    );
  }
}
