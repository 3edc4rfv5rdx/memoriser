// additem.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'package:sqflite/sqflite.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import 'globals.dart';
import 'reminders.dart';

class EditItemPage extends StatefulWidget {
  final int? itemId; // Используем ID вместо целой записи

  const EditItemPage({super.key, this.itemId});

  @override
  _EditItemPageState createState() => _EditItemPageState();
}

class _EditItemPageState extends State<EditItemPage> {
  late TextEditingController titleController;
  late TextEditingController contentController;
  late TextEditingController tagsController;
  late TextEditingController dateController;

  // Multi-photo support
  List<String> _photoPaths = [];
  String? _currentPhotoDir; // Current photo directory (temp for new, item_X for edit)
  bool _isNewItem = true; // Track if this is a new item
  bool _isSaved = false; // Track if item was saved
  final ImagePicker _picker = ImagePicker();

  late TextEditingController timeController;
  int? _time; // Time value in HHMM format
  int? _selectedTimeOption; // 0 - morning, 1 - day, 2 - evening, null - none selected

  // Time option constants
  static const int TIME_MORNING = 930;  // 09:30
  static const int TIME_DAY = 1230;     // 12:30
  static const int TIME_EVENING = 1830; // 18:30

  DateTime? _date;
  int _priority = 0; // Default priority value
  bool _remind = false; // Default remind value
  bool _hidden = false; // Default hidden value for privacy feature
  bool _isLoading = false; // Loading indicator
  bool _removeAfterReminder = false; // Default value for auto-remove
  bool _yearly = false; // NEW: Default value for yearly repeat

  // Daily reminder fields
  bool _daily = false;
  List<String> _dailyTimes = [];
  int _dailyDays = dayAllDays; // 127 = all days by default

  // Sound fields
  String? _sound; // For one-time reminders
  String? _dailySound; // For daily reminders
  List<Map<String, String>> _systemSounds = [];

  // List of tags for dropdown
  List<Map<String, dynamic>> _tagsWithCounts = [];

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController();
    contentController = TextEditingController();
    tagsController = TextEditingController();
    dateController = TextEditingController();
    timeController = TextEditingController();
    _photoPaths = [];
    _isSaved = false;

    // If ID is passed, this is edit mode
    if (widget.itemId != null) {
      _isNewItem = false;
      _loadItem(widget.itemId!);
    } else {
      // If no ID passed, this is a new record
      _isNewItem = true;
      _hidden = xvHiddenMode; // Hide by default in hidden mode
      _yearly = false; // Default off for new records
      // Create temp directory for new item photos
      _initTempPhotoDir();
    }

    // Load all tags on initialization
    _loadTagsData();

    // Load system sounds
    _loadSystemSounds();
  }

  // Load available system sounds
  Future<void> _loadSystemSounds() async {
    final sounds = await SimpleNotifications.getSystemSounds();
    setState(() {
      _systemSounds = sounds;
    });
  }

  // Initialize temp photo directory for new items
  Future<void> _initTempPhotoDir() async {
    _currentPhotoDir = await createTempPhotoDir();
    myPrint('Initialized temp photo dir: $_currentPhotoDir');
  }

  // Функция для загрузки данных тегов
  Future<void> _loadTagsData() async {
    try {
      // Получаем отсортированные теги с их частотами
      List<Map<String, dynamic>> tags = await getTagsWithCounts();
      setState(() {
        _tagsWithCounts = tags;
      });
    } catch (e) {
      myPrint('Error loading tags data: $e');
    }
  }

  @override
  void dispose() {
    // Clean up temp photo directory if not saved (only for new items)
    if (!_isSaved && _isNewItem && _currentPhotoDir != null) {
      myPrint('Cleaning up temp photo dir: $_currentPhotoDir');
      deleteTempPhotoDir(_currentPhotoDir);
    }

    timeController.dispose();
    titleController.dispose();
    contentController.dispose();
    tagsController.dispose();
    dateController.dispose();
    super.dispose();
  }

// Method to load item by ID in _EditItemPageState
  Future<void> _loadItem(int itemId) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get record from database
      final List<Map<String, dynamic>> result = await mainDb.query(
        'items',
        where: 'id = ?',
        whereArgs: [itemId],
      );

      if (result.isNotEmpty) {
        final item = result.first;

        // If record is hidden and we're in hidden mode, decode data
        if (item['hidden'] == 1 && xvHiddenMode) {
          final decodedTitle = deobfuscateText(item['title'] ?? '');
          final decodedContent = deobfuscateText(item['content'] ?? '');
          final decodedTags = deobfuscateText(item['tags'] ?? '');

          titleController.text = decodedTitle;
          contentController.text = decodedContent;
          tagsController.text = decodedTags;
        } else {
          // Regular records are used as is
          titleController.text = item['title'] ?? '';
          contentController.text = item['content'] ?? '';
          tagsController.text = item['tags'] ?? '';
        }

        // Initialize other fields
        _priority = item['priority'] ?? 0;
        _remind = item['remind'] == 1;
        _hidden = item['hidden'] == 1;
        _removeAfterReminder = item['remove'] == 1;
        _yearly = item['yearly'] == 1; // NEW: Load yearly field

        // Load daily reminder fields
        _daily = item['daily'] == 1;
        _dailyTimes = parseDailyTimes(item['daily_times']);
        _dailyDays = item['daily_days'] ?? dayAllDays;

        // Load sound fields
        _sound = item['sound'];
        _dailySound = item['daily_sound'];

        // If daily sound is empty and daily is enabled, get default from settings
        if (_dailySound == null && _daily) {
          _dailySound = await SimpleNotifications.getDefaultDailySound();
        }

        // Set up photo directory for existing item
        _currentPhotoDir = getItemPhotoDirPath(itemId);
        // Load photos from item directory (filesystem is the source of truth)
        _photoPaths = await getItemPhotoPaths(itemId);

        // Load time if set
        _time = item['time'] as int?;
        if (_time != null) {
          // Convert numeric value to HH:MM string format
          String? timeStr = timeIntToString(_time);
          if (timeStr != null) {
            timeController.text = timeStr;

            // Check if time matches one of the preset options
            if (_time == TIME_MORNING) {
              _selectedTimeOption = 0;
            } else if (_time == TIME_DAY) {
              _selectedTimeOption = 1;
            } else if (_time == TIME_EVENING) {
              _selectedTimeOption = 2;
            } else {
              _selectedTimeOption = null;
            }
          }
        }

        // Initialize date if it exists
        if (item['date'] != null) {
          _date = yyyymmddToDateTime(item['date']);
          // Set date controller text only if _date is not null
          if (_date != null) {
            // Use forced unwrapping (!) since we checked that _date is not null
            dateController.text = DateFormat(ymdDateFormat).format(_date!);
          } else {
            dateController.text = ""; // Clear date controller if date is incorrect
            myPrint('Warning: Could not parse date value: ${item['date']}');
          }
        }
      }
    } catch (e) {
      myPrint('Error loading item: $e');
      okInfoBarRed(lw('Error loading item'));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

// Save function that directly interacts with the database
  Future<void> _saveItem() async {
    if (titleController.text.trim().isEmpty) {
      okInfoBarRed(lw('Title cannot be empty'), duration: Duration(seconds: 4));
      return;
    }

    // Validation for one-time reminder
    if (_remind) {
      // Check if date is set
      if (_date == null) {
        okInfoBarRed(
          lw('Set a date for the reminder'),
          duration: Duration(seconds: 4),
        );
        return;
      }

      // Validate the reminder date is not in the past
      final today = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );

      if (_date!.isBefore(today)) {
        okInfoBarRed(
          lw('Reminder date cannot be in the past'),
          duration: Duration(seconds: 4),
        );
        return;
      }
    }

    // Validation for daily reminder
    if (_daily) {
      if (_dailyTimes.isEmpty) {
        okInfoBarRed(
          lw('Add at least one time'),
          duration: Duration(seconds: 4),
        );
        return;
      }
      if (_dailyDays == 0) {
        okInfoBarRed(
          lw('Select at least one day'),
          duration: Duration(seconds: 4),
        );
        return;
      }
    }

    // Convert date to YYYYMMDD format for storage
    final dateValue = _date != null ? dateTimeToYYYYMMDD(_date) : null;
    final remindValue = _remind ? 1 : 0;
    final hiddenValue = _hidden ? 1 : 0;
    final removeValue = _removeAfterReminder ? 1 : 0;
    final yearlyValue = _yearly ? 1 : 0; // NEW: Yearly field

    // Daily reminder fields
    final dailyValue = _daily ? 1 : 0;
    final dailyTimesValue = encodeDailyTimes(_dailyTimes);
    final dailyDaysValue = _dailyDays;

    // Get time value (may be null)
    final timeValue = _time;

    // Prepare data for saving
    String titleText = titleController.text.trim();
    String contentText = contentController.text.trim();
    String tagsText = tagsController.text.trim();

    // Obfuscate data if the record is hidden and we're in hidden mode
    if (hiddenValue == 1 && xvHiddenMode) {
      titleText = obfuscateText(titleText);
      contentText = obfuscateText(contentText);
      tagsText = obfuscateText(tagsText);
    }

    try {
      if (widget.itemId != null) {
        // Update existing item - photos are already in item_X directory
        final photoData = encodePhotoPaths(_photoPaths);

        await mainDb.update(
          'items',
          {
            'title': titleText,
            'content': contentText.isEmpty ? null : contentText,
            'tags': tagsText.isEmpty ? null : tagsText,
            'priority': _priority,
            'date': dateValue,
            'time': timeValue,
            'remind': remindValue,
            'hidden': hiddenValue,
            'remove': removeValue,
            'yearly': yearlyValue,
            'daily': dailyValue,
            'daily_times': dailyTimesValue,
            'daily_days': dailyDaysValue,
            'sound': _sound,
            'daily_sound': _dailySound,
            'photo': photoData,
          },
          where: 'id = ?',
          whereArgs: [widget.itemId],
        );
        myPrint("Item updated: ${widget.itemId} - $titleText - Photos: ${_photoPaths.length}");

        // Update/cancel specific reminder for this item
        await SimpleNotifications.updateSpecificReminder(
          widget.itemId!,
          _remind,
          _date,
          _time,
        );

        // Update daily reminders for this item
        await SimpleNotifications.updateDailyReminders(
          widget.itemId!,
          _daily,
          _dailyTimes,
          _dailyDays,
          titleText,
        );

      } else {
        // Insert new item first to get the ID
        final insertedId = await mainDb.insert('items', {
          'title': titleText,
          'content': contentText.isEmpty ? null : contentText,
          'tags': tagsText.isEmpty ? null : tagsText,
          'priority': _priority,
          'date': dateValue,
          'time': timeValue,
          'remind': remindValue,
          'hidden': hiddenValue,
          'remove': removeValue,
          'yearly': yearlyValue,
          'daily': dailyValue,
          'daily_times': dailyTimesValue,
          'daily_days': dailyDaysValue,
          'sound': _sound,
          'daily_sound': _dailySound,
          'photo': null, // Will update after moving photos
          'created': dateTimeToYYYYMMDD(DateTime.now()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        myPrint("Item inserted with ID: $insertedId");

        // Move photos from temp directory to item directory
        if (_currentPhotoDir != null && _photoPaths.isNotEmpty) {
          final newPaths = await movePhotosFromTempToItem(_currentPhotoDir!, insertedId);
          _photoPaths = newPaths;

          // Update the photo field with new paths
          final photoData = encodePhotoPaths(_photoPaths);
          await mainDb.update(
            'items',
            {'photo': photoData},
            where: 'id = ?',
            whereArgs: [insertedId],
          );
          myPrint("Updated photo paths for item $insertedId: ${_photoPaths.length} photos");
        }

        // Schedule specific reminder for new item if needed
        if (_remind && _date != null) {
          await SimpleNotifications.scheduleSpecificReminder(
            insertedId,
            _date!,
            _time,
          );
        }

        // Schedule daily reminders for new item if needed
        if (_daily && _dailyTimes.isNotEmpty) {
          await SimpleNotifications.scheduleAllDailyReminders(
            insertedId,
            _dailyTimes,
            _dailyDays,
            titleText,
          );
        }
      }

      _isSaved = true; // Mark as saved so dispose won't delete photos
      Navigator.pop(context, true);
    } catch (e) {
      // Show error message if database operation fails
      okInfoBarPurple('${lw('Error saving item')}: $e');
      myPrint("Error saving item: $e");
    }
  }

  Future<void> _takePicture() async {
    // Check limit
    if (_photoPaths.length >= maxPhotosPerItem) {
      okInfoBarOrange(lw('Maximum photos reached'));
      return;
    }

    try {
      // Get the image from the camera
      final XFile? image = await _picker.pickImage(source: ImageSource.camera);

      if (image != null) {
        // Ensure we have a photo directory
        if (_currentPhotoDir == null) {
          if (_isNewItem) {
            await _initTempPhotoDir();
          } else {
            _currentPhotoDir = getItemPhotoDirPath(widget.itemId!);
            await getItemPhotoDir(widget.itemId!); // Create if needed
          }
        }

        if (_currentPhotoDir == null) {
          throw Exception('Photo directory is not available');
        }

        // Ensure directory exists
        final dir = Directory(_currentPhotoDir!);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }

        // Generate a unique filename with timestamp
        final now = DateTime.now();
        final formattedDate = DateFormat('yyyyMMdd-HHmmss').format(now);
        final fileName = 'photo-$formattedDate.jpg';

        // Copy the image to the photo directory
        final File newImage = File('$_currentPhotoDir/$fileName');
        await File(image.path).copy(newImage.path);

        // Add to photo list
        setState(() {
          _photoPaths.add(newImage.path);
        });

        okInfoBarGreen(lw('Photo saved'));
      }
    } catch (e) {
      myPrint('Error taking picture: $e');
      okInfoBarRed(lw('Failed to take picture'));
    }
  }

  // Pick multiple photos from gallery
  Future<void> _pickFromGallery() async {
    // Calculate how many more photos can be added
    final remaining = maxPhotosPerItem - _photoPaths.length;
    if (remaining <= 0) {
      okInfoBarOrange(lw('Maximum photos reached'));
      return;
    }

    try {
      // Pick multiple images from gallery
      final List<XFile> images = await _picker.pickMultiImage();

      if (images.isEmpty) return;

      // Limit to remaining slots
      final imagesToProcess = images.take(remaining).toList();

      // Ensure we have a photo directory
      if (_currentPhotoDir == null) {
        if (_isNewItem) {
          await _initTempPhotoDir();
        } else {
          _currentPhotoDir = getItemPhotoDirPath(widget.itemId!);
          await getItemPhotoDir(widget.itemId!); // Create if needed
        }
      }

      if (_currentPhotoDir == null) {
        throw Exception('Photo directory is not available');
      }

      // Ensure directory exists
      final dir = Directory(_currentPhotoDir!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      int addedCount = 0;
      for (var image in imagesToProcess) {
        if (_photoPaths.length >= maxPhotosPerItem) break;

        // Generate a unique filename with timestamp
        final now = DateTime.now();
        final formattedDate = DateFormat('yyyyMMdd-HHmmss').format(now);
        final fileName = 'photo-$formattedDate-$addedCount.jpg';

        // Copy the image to the photo directory
        final File newImage = File('$_currentPhotoDir/$fileName');
        await File(image.path).copy(newImage.path);

        _photoPaths.add(newImage.path);
        addedCount++;
      }

      if (addedCount > 0) {
        setState(() {});
        okInfoBarGreen('$addedCount ${lw('photos added')}');
      }
    } catch (e) {
      myPrint('Error picking images: $e');
      okInfoBarRed(lw('Failed to pick images'));
    }
  }

  // Remove a single photo from the list
  Future<void> _removePhoto(int index) async {
    if (index < 0 || index >= _photoPaths.length) return;

    final path = _photoPaths[index];
    final confirmed = await showCustomDialog(
      title: lw('Delete Photo'),
      content: lw('Are you sure you want to delete this photo?'),
      actions: [
        {'label': lw('Cancel'), 'value': false, 'isDestructive': false},
        {'label': lw('Delete'), 'value': true, 'isDestructive': true},
      ],
    );

    if (confirmed == true) {
      // Delete file
      await deletePhotoFileWithoutConfirmation(path);

      // Remove from list
      setState(() {
        _photoPaths.removeAt(index);
      });
    }
  }

  // Show photo in fullscreen
  void _showPhotoFullscreen(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      okInfoBarRed(lw('Photo Not Found'));
      return;
    }

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (BuildContext dialogContext) {
        final screenSize = MediaQuery.of(dialogContext).size;

        return Dialog(
          backgroundColor: clFill,
          insetPadding: EdgeInsets.symmetric(
            horizontal: screenSize.width * 0.05,
            vertical: screenSize.height * 0.05,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                backgroundColor: clUpBar,
                foregroundColor: clText,
                title: Text(lw('Photo')),
                leading: IconButton(
                  icon: Icon(Icons.close),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ),
              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: screenSize.height * 0.8,
                    maxWidth: screenSize.width * 0.9,
                  ),
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 5.0,
                    child: Image.file(
                      file,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Method to show date picker
  Future<void> _selectDate(BuildContext context) async {
    final DateTime initialDate = _date ?? DateTime.now();

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      locale: Locale(getLocaleCode(currentLocale)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: clUpBar,
              onPrimary: clText,
              onSurface: clText,
            ),
            dialogTheme: DialogThemeData(backgroundColor: clFill),
            // Add custom button styling
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                backgroundColor: clUpBar,
                foregroundColor: clText,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _date = picked;
        dateController.text = DateFormat(ymdDateFormat).format(picked);
      });
    }
  }

  // Build priority selector with + and - buttons
  Widget _buildPrioritySelector() {
    return GestureDetector(
      onLongPress: () => showHelp(34), // ID 34 для всех элементов приоритета
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label for priority
          Text(
            lw('Priority (0-3)'),
            style: TextStyle(color: clText, fontSize: fsMedium),
          ),
          SizedBox(height: 8),
          // Single row containing all elements
          Row(
            children: [
              // LEFT SIDE: Minus button with upbar color
              ElevatedButton(
                onPressed:
                    _priority > 0 ? () => setState(() => _priority--) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: clUpBar,
                  foregroundColor: clText,
                  shape: CircleBorder(),
                  padding: EdgeInsets.all(8),
                  minimumSize: Size(36, 36),
                ),
                child: Icon(Icons.remove, size: 20),
              ),
              Container(
                width: 40,
                height: 40,
                margin: EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: clFill,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: clUpBar),
                ),
                alignment: Alignment.center,
                child: Text(
                  _priority.toString(),
                  style: TextStyle(
                    color: clText,
                    fontSize: fsMedium,
                    fontWeight: fwBold,
                  ),
                ),
              ),
              // Plus button with upbar color
              ElevatedButton(
                onPressed:
                    _priority < 3 ? () => setState(() => _priority++) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: clUpBar,
                  foregroundColor: clText,
                  shape: CircleBorder(),
                  padding: EdgeInsets.all(8),
                  minimumSize: Size(36, 36),
                ),
                child: Icon(Icons.add, size: 20),
              ),

              // MIDDLE: Stars moved to center with expanded space on both sides
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (index) {
                    return Icon(
                      Icons.star,
                      color: index < _priority ? clUpBar : clFill,
                      size: 34, // Larger stars
                    );
                  }),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

// Complete reminder section with header, checkbox, and type selector
  Widget _buildReminderSection() {
    // Check if any reminder is enabled
    final bool reminderEnabled = _remind || _daily;

    return GestureDetector(
      onLongPress: () => showHelp(35),
      child: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: clFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: reminderEnabled ? clUpBar : clText.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with checkbox
            Row(
              children: [
                Checkbox(
                  value: reminderEnabled,
                  activeColor: clUpBar,
                  checkColor: clText,
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        // Enable one-time reminder by default
                        _remind = true;
                        _daily = false;
                        // Set default time
                        _selectedTimeOption = 0;
                        _time = TIME_MORNING;
                        timeController.text = '09:30';
                      } else {
                        // Disable all reminders
                        _remind = false;
                        _daily = false;
                        timeController.clear();
                        _time = null;
                        _selectedTimeOption = null;
                        _yearly = false;
                        _removeAfterReminder = false;
                      }
                    });
                  },
                ),
                Text(
                  lw('Reminder'),
                  style: TextStyle(
                    color: clText,
                    fontSize: fsMedium,
                    fontWeight: fwBold,
                  ),
                ),
              ],
            ),

            // Show options only when reminder is enabled
            if (reminderEnabled) ...[
              SizedBox(height: 12),

              // One-time / Daily toggle
              _buildReminderTypeToggle(),

              SizedBox(height: 12),

              // One-time reminder options
              if (_remind) ...[
                _buildTimeField(),
                SizedBox(height: 10),
                _buildTimeOptions(),
                SizedBox(height: 10),
                _buildYearlySelector(),
                SizedBox(height: 10),
                _buildRemoveAfterReminderSelector(),
                // Sound for one-time reminders is taken from app Settings
              ],

              // Daily reminder options
              if (_daily) ...[
                _buildDailyTimesSection(),
                SizedBox(height: 12),
                _buildDailyDaysSection(),
                SizedBox(height: 12),
                _buildSoundSelector(isDaily: true),
              ],
            ],
          ],
        ),
      ),
    );
  }

  // One-time / Daily toggle buttons
  Widget _buildReminderTypeToggle() {
    return Row(
      children: [
        // One-time toggle
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _remind = true;
                _daily = false;
                _selectedTimeOption = 0;
                _time = TIME_MORNING;
                timeController.text = '09:30';
              });
            },
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: _remind ? clUpBar : Colors.transparent,
                borderRadius: BorderRadius.horizontal(left: Radius.circular(6)),
                border: Border.all(color: _remind ? clUpBar : clText.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event, color: clText, size: 18),
                  SizedBox(width: 6),
                  Text(
                    lw('One-time'),
                    style: TextStyle(
                      color: clText,
                      fontSize: fsNormal,
                      fontWeight: _remind ? fwBold : fwNormal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Daily toggle
        Expanded(
          child: GestureDetector(
            onTap: () async {
              // Load default daily sound if not set
              String? defaultSound = _dailySound;
              if (defaultSound == null) {
                defaultSound = await SimpleNotifications.getDefaultDailySound();
              }
              setState(() {
                _daily = true;
                _remind = false;
                timeController.clear();
                _time = null;
                _selectedTimeOption = null;
                _yearly = false;
                _removeAfterReminder = false;
                _dailySound = defaultSound;
                if (_dailyTimes.isEmpty) {
                  _dailyTimes = ['09:00'];
                }
              });
            },
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: _daily ? clUpBar : Colors.transparent,
                borderRadius: BorderRadius.horizontal(right: Radius.circular(6)),
                border: Border.all(color: _daily ? clUpBar : clText.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.repeat, color: clText, size: 18),
                  SizedBox(width: 6),
                  Text(
                    lw('Daily'),
                    style: TextStyle(
                      color: clText,
                      fontSize: fsNormal,
                      fontWeight: _daily ? fwBold : fwNormal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

// UPDATED: Widget for remove after reminder selector
  Widget _buildRemoveAfterReminderSelector() {
    return GestureDetector(
      onLongPress: () => showHelp(42), // ID 42 for remove checkbox
      child: Row(
        children: [
          Checkbox(
            value: _removeAfterReminder,
            activeColor: clRed,
            checkColor: clText,
            // Disable if yearly is enabled OR reminder is disabled
            onChanged: (_yearly || !_remind) ? null : (value) {
              setState(() {
                _removeAfterReminder = value ?? false;
              });
            },
          ),
          Text(
            lw('Remove after reminder'),
            style: TextStyle(
              color: (_yearly || !_remind) ? clText.withValues(alpha: 0.5) : clText,
              fontSize: fsMedium,
            ),
          ),
        ],
      ),
    );
  }

  // NEW: Widget for yearly repeat selector
  Widget _buildYearlySelector() {
    return GestureDetector(
      onLongPress: () => showHelp(43), // ID 43 for yearly checkbox
      child: Row(
        children: [
          Checkbox(
            value: _yearly,
            activeColor: Colors.green,
            checkColor: clText,
            // Enable only if reminder is set
            onChanged: _remind ? (value) {
              setState(() {
                _yearly = value ?? false;

                // If yearly is enabled, automatically disable "remove after reminder"
                if (_yearly) {
                  _removeAfterReminder = false;
                }
              });
            } : null,
          ),
          Text(
            lw('Yearly repeat'),
            style: TextStyle(
              color: _remind ? clText : clText.withValues(alpha: 0.5),
              fontSize: fsMedium,
            ),
          ),
          SizedBox(width: 4),
          Icon(
            Icons.autorenew,
            color: _remind ? Colors.green : Colors.green.withValues(alpha: 0.5),
            size: 16,
          ),
        ],
      ),
    );
  }

  // Build the times list section
  Widget _buildDailyTimesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.access_time, color: clText, size: 16),
            SizedBox(width: 8),
            Text(
              lw('Times'),
              style: TextStyle(color: clText, fontSize: fsNormal, fontWeight: fwBold),
            ),
            Spacer(),
            // Add time button
            IconButton(
              icon: Icon(Icons.add_circle, color: clUpBar, size: 24),
              onPressed: () => _showAddTimeDialog(),
              tooltip: lw('Add time'),
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(),
            ),
          ],
        ),
        SizedBox(height: 8),

        // List of times
        if (_dailyTimes.isEmpty)
          Text(
            lw('No times set'),
            style: TextStyle(color: clText.withValues(alpha: 0.5), fontSize: fsSmall),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _dailyTimes.map((time) {
              return Chip(
                label: Text(time, style: TextStyle(color: clText)),
                backgroundColor: clUpBar,
                deleteIcon: Icon(Icons.close, size: 16, color: clRed),
                onDeleted: () {
                  setState(() {
                    _dailyTimes = removeDailyTime(_dailyTimes, time);
                  });
                },
              );
            }).toList(),
          ),
      ],
    );
  }

  // Show dialog to add a new time
  Future<void> _showAddTimeDialog() async {
    TimeOfDay? selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: 9, minute: 0),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: clUpBar,
              onPrimary: clText,
              surface: clBgrnd,
              onSurface: clText,
            ),
          ),
          child: child!,
        );
      },
    );

    if (selectedTime != null) {
      final timeStr = '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';
      setState(() {
        _dailyTimes = addDailyTime(_dailyTimes, timeStr);
      });
    }
  }

  // Build the days of week section
  Widget _buildDailyDaysSection() {
    // Check if all days or weekdays are currently selected
    final bool allDaysOn = _dailyDays == dayAllDays;
    final bool weekdaysOn = (_dailyDays & dayWeekdays) == dayWeekdays;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with toggle buttons
        Row(
          children: [
            Icon(Icons.calendar_today, color: clText, size: 16),
            SizedBox(width: 8),
            Text(
              lw('Days'),
              style: TextStyle(color: clText, fontSize: fsNormal, fontWeight: fwBold),
            ),
            Spacer(),
            // Independent toggle buttons
            // "All" toggle - on/off
            GestureDetector(
              onTap: () {
                setState(() {
                  if (allDaysOn) {
                    _dailyDays = 0; // Turn off all
                  } else {
                    _dailyDays = dayAllDays; // Turn on all
                  }
                });
              },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                margin: EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: allDaysOn ? clUpBar : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: allDaysOn ? clUpBar : clText.withValues(alpha: 0.3)),
                ),
                child: Text(
                  lw('All'),
                  style: TextStyle(
                    fontSize: fsSmall,
                    color: clText,
                    fontWeight: allDaysOn ? fwBold : fwNormal,
                  ),
                ),
              ),
            ),
            // "Weekdays" toggle - on/off
            GestureDetector(
              onTap: () {
                setState(() {
                  if (weekdaysOn) {
                    // Turn off weekdays (Mon-Fri), keep weekend as is
                    _dailyDays = _dailyDays & dayWeekend;
                  } else {
                    // Turn on weekdays, keep weekend as is
                    _dailyDays = _dailyDays | dayWeekdays;
                  }
                });
              },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: weekdaysOn ? clUpBar : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: weekdaysOn ? clUpBar : clText.withValues(alpha: 0.3)),
                ),
                child: Text(
                  lw('Weekdays'),
                  style: TextStyle(
                    fontSize: fsSmall,
                    color: clText,
                    fontWeight: weekdaysOn ? fwBold : fwNormal,
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 12),

        // Day checkboxes
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(7, (index) {
            final isEnabled = isDayEnabled(_dailyDays, index);
            return GestureDetector(
              onTap: () {
                setState(() {
                  _dailyDays = setDayEnabled(_dailyDays, index, !isEnabled);
                });
              },
              child: Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isEnabled ? clUpBar : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isEnabled ? clUpBar : clText.withValues(alpha: 0.3),
                      ),
                    ),
                    child: isEnabled
                        ? Icon(Icons.check, color: clText, size: 18)
                        : null,
                  ),
                  SizedBox(height: 4),
                  Text(
                    getDayName(index),
                    style: TextStyle(
                      color: clText,
                      fontSize: fsSmall,
                      fontWeight: isEnabled ? fwBold : fwNormal,
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  // Build sound selector widget
  Widget _buildSoundSelector({required bool isDaily}) {
    final currentSound = isDaily ? _dailySound : _sound;
    final soundName = _getSoundName(currentSound);

    return Row(
      children: [
        Icon(Icons.volume_up, color: clText, size: 20),
        SizedBox(width: 8),
        Text(
          lw('Sound:'),
          style: TextStyle(color: clText, fontSize: fsNormal),
        ),
        SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () => _showSoundPicker(isDaily: isDaily),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: clText.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      soundName,
                      style: TextStyle(color: clText, fontSize: fsNormal),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.arrow_drop_down, color: clText),
                ],
              ),
            ),
          ),
        ),
        // Play button
        if (currentSound != null) ...[
          SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.play_arrow, color: clText),
            onPressed: () => SimpleNotifications.playSound(soundUri: currentSound),
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(),
          ),
        ],
      ],
    );
  }

  // Get sound name from URI or path
  String _getSoundName(String? soundValue) {
    if (soundValue == null) return lw('Default');

    // Check system sounds
    for (var sound in _systemSounds) {
      if (sound['uri'] == soundValue) {
        return sound['name'] ?? lw('Unknown');
      }
    }

    // If it's a file path, show filename without extension
    if (soundValue.startsWith('/')) {
      final fileName = soundValue.split('/').last;
      // Remove extension
      return fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    }

    return lw('Default');
  }

  // Show sound picker dialog
  void _showSoundPicker({required bool isDaily}) async {
    // Load custom sounds from Sounds folder
    final customSounds = await getCustomSounds();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: clBgrnd,
          title: Text(
            lw('Select Sound'),
            style: TextStyle(color: clText),
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView(
              children: [
                // Default option
                ListTile(
                  leading: Icon(Icons.notifications, color: clText),
                  title: Text(lw('Default'), style: TextStyle(color: clText)),
                  trailing: (isDaily ? _dailySound : _sound) == null
                      ? Icon(Icons.check, color: Colors.green)
                      : null,
                  onTap: () {
                    setState(() {
                      if (isDaily) {
                        _dailySound = null;
                      } else {
                        _sound = null;
                      }
                    });
                    Navigator.pop(dialogContext);
                  },
                ),

                // Custom sounds section (if any)
                if (customSounds.isNotEmpty) ...[
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      lw('Custom sounds'),
                      style: TextStyle(color: clText.withValues(alpha: 0.7), fontSize: fsSmall),
                    ),
                  ),
                  ...customSounds.map((sound) {
                    final currentSound = isDaily ? _dailySound : _sound;
                    final isSelected = currentSound == sound['path'];
                    return ListTile(
                      leading: Icon(Icons.audiotrack, color: Colors.orange),
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
                              SimpleNotifications.playSound(soundPath: sound['path']);
                            },
                          ),
                          if (isSelected) Icon(Icons.check, color: Colors.green),
                        ],
                      ),
                      onTap: () {
                        SimpleNotifications.stopSound();
                        setState(() {
                          if (isDaily) {
                            _dailySound = sound['path'];
                          } else {
                            _sound = sound['path'];
                          }
                        });
                        Navigator.pop(dialogContext);
                      },
                    );
                  }),
                ],

                // Choose file option
                ListTile(
                  leading: Icon(Icons.folder_open, color: Colors.blue),
                  title: Text(lw('Choose file'), style: TextStyle(color: Colors.blue)),
                  onTap: () async {
                    Navigator.pop(dialogContext);
                    await _pickSoundFile(isDaily: isDaily);
                  },
                ),

                // System sounds section
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    lw('System sounds'),
                    style: TextStyle(color: clText.withValues(alpha: 0.7), fontSize: fsSmall),
                  ),
                ),
                ..._systemSounds.map((sound) {
                  final currentSound = isDaily ? _dailySound : _sound;
                  final isSelected = currentSound == sound['uri'];
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
                          _dailySound = sound['uri'];
                        } else {
                          _sound = sound['uri'];
                        }
                      });
                      Navigator.pop(dialogContext);
                    },
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                SimpleNotifications.stopSound();
                Navigator.pop(dialogContext);
              },
              child: Text(lw('Cancel'), style: TextStyle(color: clText)),
            ),
          ],
        );
      },
    ).then((_) {
      // Stop sound when dialog is closed
      SimpleNotifications.stopSound();
    });
  }

  // Pick sound file from device
  Future<void> _pickSoundFile({required bool isDaily}) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'ogg', 'm4a', 'aac'],
      );

      if (result != null && result.files.single.path != null) {
        final sourcePath = result.files.single.path!;

        // Copy file to Sounds directory
        final newPath = await copySoundFile(sourcePath);

        if (newPath != null) {
          setState(() {
            if (isDaily) {
              _dailySound = newPath;
            } else {
              _sound = newPath;
            }
          });
          okInfoBarGreen(lw('Sound added'));
        } else {
          okInfoBarRed(lw('Error adding sound'));
        }
      }
    } catch (e) {
      myPrint('Error picking sound file: $e');
      okInfoBarRed(lw('Error picking file'));
    }
  }

  // Validate reminder date is in the future
  void _validateReminderDate() {
    // Check if date is set
    if (_date == null) {
      okInfoBarOrange(lw('Please set a date for the reminder'));
      setState(() {
        _remind = false;
      });
      return;
    }

    try {
      // Get today's date (start of day)
      final today = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );

      // Check if date is at least today (not in the past)
      if (_date!.isBefore(today)) {
        okInfoBarOrange(lw('Reminder date cannot be in the past'));
        // Automatically uncheck the reminder if date is invalid
        setState(() {
          _remind = false;
        });
      }
    } catch (e) {
      // Handle any exceptions that might occur
      myPrint('Error validating reminder date: $e');
      setState(() {
        _remind = false;
      });
      okInfoBarRed(lw('Error validating date'));
    }
  }

  // Build hidden checkbox (only shown in hidden mode)
  Widget _buildHiddenSelector() {
    // Показываем чекбокс только если мы в режиме скрытых записей
    if (!xvHiddenMode) return SizedBox.shrink();

    return GestureDetector(
      onLongPress: () => showHelp(37), // ID 37 для чекбокса скрытых записей
      child: Row(
        children: [
          Checkbox(
            value: _hidden,
            activeColor: Color(0xFFf29238),
            checkColor: clText,
            onChanged: (value) {
              setState(() {
                _hidden = value ?? false;
              });
            },
          ),
          Text(
            lw('Private item'),
            style: TextStyle(color: clText, fontSize: fsMedium),
          ),
          SizedBox(width: 4),
          Icon(Icons.lock, color: Color(0xFFf29238), size: 16),
        ],
      ),
    );
  }

// Build date field with date picker button
  Widget _buildDateField() {
    return GestureDetector(
      onLongPress: () => showHelp(36), // ID 36 для поля даты и кнопок
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: dateController,
              style: TextStyle(color: clText),
              readOnly: false,
              // Allow manual input
              onChanged: (value) {
                if (value.isEmpty) {
                  setState(() {
                    _date = null;
                  });
                } else if (validateDateInput(value)) {
                  // If valid date input, update _date
                  setState(() {
                    _date = DateFormat(ymdDateFormat).parse(value);
                  });
                }
              },
              decoration: InputDecoration(
                labelText: lw('Date (YYYY-MM-DD)'),
                labelStyle: TextStyle(color: clText),
                fillColor: clFill,
                filled: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.calendar_today, color: clText),
            onPressed: () => _selectDate(context),
          ),
          // Clear button
          IconButton(
            icon: Icon(Icons.clear, color: clText),
            onPressed: () {
              setState(() {
                dateController.clear();
                _date = null;
                // Also clear the reminder checkbox when date is cleared
                _remind = false;
                // Clear time field and radio buttons
                timeController.clear();
                _time = null;
                _selectedTimeOption = null;
                // Clear remove after reminder checkbox
                _removeAfterReminder = false;
              });
              // Optionally show a message that reminder was cleared
              okInfoBarBlue(lw('Date and reminder cleared'));
            },
          ),
        ],
      ),
    );
  }

  // Виджет для выбора времени с полем ввода и кнопками
  Widget _buildTimeField() {
    return GestureDetector(
      onLongPress: () => showHelp(39), // ID 39 для поля времени
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: timeController,
              style: TextStyle(color: clText),
              readOnly: false, // Разрешаем ручной ввод
              enabled: _remind, // Активно только если включено напоминание
              onChanged: (value) {
                if (value.isEmpty) {
                  setState(() {
                    _time = null;
                    _selectedTimeOption = null; // Сбрасываем выбор радио-кнопок
                  });
                } else if (isValidTimeFormat(value)) {
                  // Если ввод корректен, обновляем _time
                  setState(() {
                    _time = timeStringToInt(value);

                    // Проверяем, соответствует ли введенное время одному из предустановленных вариантов
                    if (_time == TIME_MORNING) {
                      _selectedTimeOption = 0;
                    } else if (_time == TIME_DAY) {
                      _selectedTimeOption = 1;
                    } else if (_time == TIME_EVENING) {
                      _selectedTimeOption = 2;
                    } else {
                      _selectedTimeOption = null;
                    }
                  });
                }
              },
              decoration: InputDecoration(
                labelText: lw('Time (HH:MM)'),
                labelStyle: TextStyle(color: _remind ? clText : clText.withValues(alpha: 0.5)),
                fillColor: clFill,
                filled: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.access_time, color: _remind ? clText : clText.withValues(alpha: 0.5)),
            onPressed: _remind ? () => _selectTime(context) : null,
          ),
          IconButton(
            icon: Icon(Icons.clear, color: _remind ? clText : clText.withValues(alpha: 0.5)),
            onPressed: _remind ? () {
              setState(() {
                timeController.clear();
                _time = null;
                _selectedTimeOption = null; // Сбрасываем выбор радио-кнопок
              });
            } : null,
          ),
        ],
      ),
    );
  }

// Виджет для выбора предустановленных вариантов времени (радио-кнопки)
  Widget _buildTimeOptions() {
    return GestureDetector(
      onLongPress: () => showHelp(41), // ID 41 для радио-кнопок времени
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Утро
          Row(
            children: [
              Radio<int>(
                value: 0,
                groupValue: _selectedTimeOption,
                onChanged: _remind ? (int? value) {
                  setState(() {
                    _selectedTimeOption = value;
                    _time = TIME_MORNING; // 09:30
                    timeController.text = '09:30';
                  });
                } : null,
              ),
              Text(
                lw('Morning'),
                style: TextStyle(
                  color: _remind ? clText : clText.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          // День
          Row(
            children: [
              Radio<int>(
                value: 1,
                groupValue: _selectedTimeOption,
                onChanged: _remind ? (int? value) {
                  setState(() {
                    _selectedTimeOption = value;
                    _time = TIME_DAY; // 12:30
                    timeController.text = '12:30';
                  });
                } : null,
              ),
              Text(
                lw('Day'),
                style: TextStyle(
                  color: _remind ? clText : clText.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          // Вечер
          Row(
            children: [
              Radio<int>(
                value: 2,
                groupValue: _selectedTimeOption,
                onChanged: _remind ? (int? value) {
                  setState(() {
                    _selectedTimeOption = value;
                    _time = TIME_EVENING; // 18:30
                    timeController.text = '18:30';
                  });
                } : null,
              ),
              Text(
                lw('Evening'),
                style: TextStyle(
                  color: _remind ? clText : clText.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

// Метод для отображения выбора времени
  Future<void> _selectTime(BuildContext context) async {
    // Парсим текущее время или используем время по умолчанию
    TimeOfDay initialTime;
    if (_time != null) {
      final hours = _time! ~/ 100;
      final minutes = _time! % 100;
      initialTime = TimeOfDay(hour: hours, minute: minutes);
    } else {
      initialTime = TimeOfDay.now(); // Используем текущее время
    }

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: clUpBar,
              onPrimary: clText,
              onSurface: clText,
            ),
            dialogTheme: DialogThemeData(backgroundColor: clFill),
            timePickerTheme: TimePickerThemeData(
              backgroundColor: clFill,
              hourMinuteTextColor: clText,
              dayPeriodTextColor: clText,
              dialHandColor: clUpBar,
              dialBackgroundColor: clFill.withValues(alpha: 0.8),
              dialTextColor: clText,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                backgroundColor: clUpBar,
                foregroundColor: clText,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        // Преобразуем выбранное время в числовой формат HHMM
        _time = picked.hour * 100 + picked.minute;

        // Обновляем текст в поле ввода
        timeController.text = timeIntToString(_time) ?? '';

        // Проверяем, соответствует ли выбранное время одному из предустановленных вариантов
        if (_time == TIME_MORNING) {
          _selectedTimeOption = 0;
        } else if (_time == TIME_DAY) {
          _selectedTimeOption = 1;
        } else if (_time == TIME_EVENING) {
          _selectedTimeOption = 2;
        } else {
          _selectedTimeOption = null; // Не соответствует предустановленным вариантам
        }
      });
    }
  }


  // Build multi-photo section with horizontal thumbnail list
  Widget _buildPhotoSection() {
    return GestureDetector(
      onLongPress: () => showHelp(38),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with count
          Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              '${lw('Photo')} (${_photoPaths.length}/$maxPhotosPerItem)',
              style: TextStyle(color: clText, fontSize: fsMedium),
            ),
          ),
          // Horizontal list of thumbnails with space for delete button
          Padding(
            padding: EdgeInsets.only(top: 10), // Space for X button above
            child: SizedBox(
              height: photoThumbnailSize + 4,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none, // Allow X button to overflow
                itemCount: _photoPaths.length + 1, // +1 for add button
                itemBuilder: (context, index) {
                  if (index == _photoPaths.length) {
                    // Add button at the end
                    return _buildAddPhotoButton();
                  }
                  return _buildPhotoThumbnail(index);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Build a single photo thumbnail with delete button
  Widget _buildPhotoThumbnail(int index) {
    final path = _photoPaths[index];
    final file = File(path);
    final exists = file.existsSync();

    return Padding(
      padding: EdgeInsets.only(right: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Thumbnail image
          GestureDetector(
            onTap: () => _showPhotoFullscreen(path),
            child: Container(
              width: photoThumbnailSize,
              height: photoThumbnailSize,
              decoration: BoxDecoration(
                border: Border.all(color: clUpBar, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: exists
                    ? Image.file(
                        file,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: clFill,
                            child: Icon(Icons.broken_image, color: clText),
                          );
                        },
                      )
                    : Container(
                        color: clFill,
                        child: Icon(Icons.broken_image, color: clRed),
                      ),
              ),
            ),
          ),
          // Delete button
          Positioned(
            top: -8,
            right: -8,
            child: GestureDetector(
              onTap: () => _removePhoto(index),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: clRed,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.close, color: clWhite, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Build add photo button with popup menu
  Widget _buildAddPhotoButton() {
    final canAdd = _photoPaths.length < maxPhotosPerItem;

    return PopupMenuButton<String>(
      enabled: canAdd,
      onSelected: (value) {
        if (value == 'camera') {
          _takePicture();
        } else if (value == 'gallery') {
          _pickFromGallery();
        }
      },
      offset: Offset(0, 40),
      color: clMenu,
      child: Container(
        width: photoThumbnailSize,
        height: photoThumbnailSize,
        decoration: BoxDecoration(
          border: Border.all(
            color: canAdd ? clUpBar : clText.withValues(alpha: 0.3),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(8),
          color: clFill,
        ),
        child: Icon(
          Icons.add_a_photo,
          color: canAdd ? clUpBar : clText.withValues(alpha: 0.3),
          size: 32,
        ),
      ),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'camera',
          child: Row(
            children: [
              Icon(Icons.camera_alt, color: clText),
              SizedBox(width: 8),
              Text(lw('Take photo'), style: TextStyle(color: clText)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'gallery',
          child: Row(
            children: [
              Icon(Icons.photo_library, color: clText),
              SizedBox(width: 8),
              Text(lw('Choose from gallery'), style: TextStyle(color: clText)),
            ],
          ),
        ),
      ],
    );
  }

  // Функция для показа диалога выбора тегов
  void _showTagsDialog() {
    if (_tagsWithCounts.isEmpty) {
      okInfoBarBlue(lw('No tags found'));
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: clFill,
          title: Text(lw('Select tag'), style: TextStyle(color: clText)),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: _tagsWithCounts.length,
              itemBuilder: (context, index) {
                final tag = _tagsWithCounts[index];
                return ListTile(
                  title: Text(
                    '${tag['name']} (${tag['count']})',
                    style: TextStyle(color: clText),
                  ),
                  tileColor: index % 2 == 0 ? clFill : clSel,
                  onTap: () {
                    _addTagToField(tag['name']);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: clUpBar,
                foregroundColor: clText,
              ),
              child: Text(lw('Cancel')),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        );
      },
    );
  }

  // Функция для добавления тега в поле ввода
  void _addTagToField(String tag) {
    // Получаем текущее значение поля
    String currentTags = tagsController.text.trim();

    // Если поле пустое, просто добавляем тег
    if (currentTags.isEmpty) {
      tagsController.text = tag;
    } else {
      // Проверяем, содержит ли уже тег
      List<String> existingTags =
          currentTags
              .split(',')
              .map((t) => t.trim())
              .where((t) => t.isNotEmpty)
              .toList();

      if (!existingTags.contains(tag)) {
        // Добавляем тег с запятой
        tagsController.text = '$currentTags, $tag';
      } else {
        // Тег уже есть, показываем сообщение
        okInfoBarBlue(lw('Tag already added'));
      }
    }
  }

// Модифицируем существующий виджет для поля тегов
  Widget _buildTagsField() {
    return GestureDetector(
      onLongPress: () => showHelp(33), // ID 33 для поля тегов
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: tagsController,
              style: TextStyle(color: clText),
              decoration: InputDecoration(
                labelText: lw('Tags (comma separated)'),
                labelStyle: TextStyle(color: clText),
                fillColor: clFill,
                filled: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.tag, color: clText),
            tooltip: lw('Select from existing tags'),
            onPressed: _showTagsDialog,
          ),
          IconButton(
            icon: Icon(Icons.clear, color: clText),
            tooltip: lw('Clear tags'),
            onPressed: () {
              setState(() {
                tagsController.clear();
              });
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.itemId != null; // Check if ID exists

    return Scaffold(
      appBar: AppBar(
        backgroundColor: xvHiddenMode ? Color(0xFFf29238) : clUpBar,
        foregroundColor: clText,
        title: GestureDetector(
          onLongPress: () => showHelp(30), // ID 30 for title
          child: Text(
            isEditing ? lw('Edit Item') : lw('New Item'),
            style: TextStyle(
              fontSize: fsLarge,
              color: clText,
              fontWeight: fwBold,
            ),
          ),
        ),
        leading: GestureDetector(
          onLongPress: () => showHelp(10), // ID 10 for back button
          child: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        actions: [
          GestureDetector(
            onLongPress: () => showHelp(12), // ID 12 for save button
            child: IconButton(icon: Icon(Icons.save), onPressed: _saveItem),
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title field
            GestureDetector(
              onLongPress: () => showHelp(31), // ID 31 for title field
              child: TextField(
                controller: titleController,
                style: TextStyle(color: clText),
                decoration: InputDecoration(
                  labelText: lw('Title'),
                  labelStyle: TextStyle(color: clText),
                  fillColor: clFill,
                  filled: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            SizedBox(height: 10),

            // Content field with reduced height
            GestureDetector(
              onLongPress: () => showHelp(32), // ID 32 for content field
              child: TextField(
                controller: contentController,
                style: TextStyle(color: clText),
                decoration: InputDecoration(
                  labelText: lw('Content'),
                  labelStyle: TextStyle(color: clText),
                  fillColor: clFill,
                  filled: true,
                  border: OutlineInputBorder(),
                ),
                maxLines: 3, // Reduced from 5 to 3
              ),
            ),
            SizedBox(height: 10),

            // Tags field
            _buildTagsField(),
            SizedBox(height: 10),

            // Multi-photo section
            _buildPhotoSection(),
            SizedBox(height: 10),

            // Priority section
            _buildPrioritySelector(),
            SizedBox(height: 10),

            // Date field (always visible)
            _buildDateField(),
            SizedBox(height: 10),

            // Reminder section with header and checkbox
            _buildReminderSection(),

            // Hidden checkbox (only in hidden mode)
            _buildHiddenSelector(),
          ],
        ),
      ),
    );
  }

}
