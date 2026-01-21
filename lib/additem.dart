// additem.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'package:sqflite/sqflite.dart';
import 'package:image_picker/image_picker.dart';

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
  late TextEditingController photoController;

  final ImagePicker _picker = ImagePicker();

  late TextEditingController timeController;
  int? _time; // Time value in HHMM format
  int? _selectedTimeOption; // 0 - morning, 1 - day, 2 - evening, null - none selected

  // Time option constants
  static const int TIME_MORNING = 800;  // 08:00
  static const int TIME_DAY = 1230;     // 12:30
  static const int TIME_EVENING = 1700; // 17:00

  DateTime? _date;
  int _priority = 0; // Default priority value
  bool _remind = false; // Default remind value
  bool _hidden = false; // Default hidden value for privacy feature
  bool _isLoading = false; // Loading indicator
  bool _removeAfterReminder = false; // Default value for auto-remove
  bool _yearly = false; // NEW: Default value for yearly repeat

  // List of tags for dropdown
  List<Map<String, dynamic>> _tagsWithCounts = [];

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController();
    contentController = TextEditingController();
    tagsController = TextEditingController();
    dateController = TextEditingController();
    photoController = TextEditingController();
    timeController = TextEditingController();

    // If ID is passed, this is edit mode
    if (widget.itemId != null) {
      _loadItem(widget.itemId!);
    } else {
      // If no ID passed, this is a new record
      _hidden = xvHiddenMode; // Hide by default in hidden mode
      _yearly = false; // Default off for new records
    }

    // Load all tags on initialization
    _loadTagsData();
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
    timeController.dispose();
    titleController.dispose();
    contentController.dispose();
    tagsController.dispose();
    dateController.dispose();
    photoController.dispose();
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
        photoController.text = item['photo'] ?? '';

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

    // Convert date to YYYYMMDD format for storage
    final dateValue = _date != null ? dateTimeToYYYYMMDD(_date) : null;
    final remindValue = _remind ? 1 : 0;
    final hiddenValue = _hidden ? 1 : 0;
    final removeValue = _removeAfterReminder ? 1 : 0;
    final yearlyValue = _yearly ? 1 : 0; // NEW: Yearly field

    // Get time value (may be null)
    final timeValue = _time;

    // Prepare data for saving
    String titleText = titleController.text.trim();
    String contentText = contentController.text.trim();
    String tagsText = tagsController.text.trim();
    String? photoPath = photoController.text.trim();
    photoPath = photoPath.isEmpty ? null : photoPath;

    // Obfuscate data if the record is hidden and we're in hidden mode
    if (hiddenValue == 1 && xvHiddenMode) {
      titleText = obfuscateText(titleText);
      contentText = obfuscateText(contentText);
      tagsText = obfuscateText(tagsText);
    }

    try {
      if (widget.itemId != null) {
        // Update existing item
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
            'yearly': yearlyValue, // NEW: Add yearly field
            'photo': photoPath,
          },
          where: 'id = ?',
          whereArgs: [widget.itemId],
        );
        myPrint("Item updated: ${widget.itemId} - $titleText - Time: $timeValue - Yearly: $yearlyValue");

        // Update/cancel specific reminder for this item
        await SimpleNotifications.updateSpecificReminder(
          widget.itemId!,
          _remind,
          _date,
          _time,
        );

      } else {
        // Insert new item
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
          'yearly': yearlyValue, // NEW: Add yearly field
          'photo': photoPath,
          'created': dateTimeToYYYYMMDD(DateTime.now()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        myPrint("Item inserted: $titleText - Time: $timeValue - Yearly: $yearlyValue, ID: $insertedId");

        // Schedule specific reminder for new item if needed
        if (_remind && _date != null) {
          await SimpleNotifications.scheduleSpecificReminder(
            insertedId,
            _date!,
            _time,
          );
        }
      }

      Navigator.pop(context, true);
    } catch (e) {
      // Show error message if database operation fails
      okInfoBarPurple('${lw('Error saving item')}: $e');
      myPrint("Error saving item: $e");
    }
  }

  Future<void> _takePicture() async {
    try {
      // Get the image from the camera
      final XFile? image = await _picker.pickImage(source: ImageSource.camera);

      if (image != null) {
        // Проверяем инициализацию путей
        if (photoDirectory == null) {
          await initStoragePaths();
        }

        if (photoDirectory == null) {
          throw Exception('Photo directory is not available');
        }

        // Generate a unique filename with timestamp
        final now = DateTime.now();
        final formattedDate = DateFormat('yyyyMMdd-HHmmss').format(now);
        final fileName = 'mem-$formattedDate.jpg';

        // Copy the image to our app's directory
        final File newImage = File('${photoDirectory!.path}/$fileName');
        await File(image.path).copy(newImage.path);

        // Update the photo controller with the new path
        setState(() {
          photoController.text = newImage.path;
        });

        okInfoBarGreen(lw('Photo saved'));
      }
    } catch (e) {
      myPrint('Error taking picture: $e');
      okInfoBarRed(lw('Failed to take picture'));
    }
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
        // Автоматическая валидация напоминания
        if (_remind) _validateReminderDate();
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

// UPDATED: Reminder selector with automatic morning selection
  Widget _buildReminderSelector() {
    return GestureDetector(
      onLongPress: () => showHelp(35), // ID 35 for reminder checkbox
      child: Row(
        children: [
          Checkbox(
            value: _remind,
            activeColor: clUpBar,
            checkColor: clText,
            onChanged: (value) {
              setState(() {
                _remind = value ?? false;

                // If enabling reminder, validate date and set morning time
                if (_remind) {
                  _validateReminderDate();

                  // If reminder is still enabled after validation, set morning time
                  if (_remind) {
                    // Automatically select morning time
                    _selectedTimeOption = 0;
                    _time = TIME_MORNING; // 08:00
                    timeController.text = '08:00';
                  }
                } else {
                  // If disabling reminder, reset time field, radio buttons, yearly and remove
                  timeController.clear();
                  _time = null;
                  _selectedTimeOption = null;
                  _yearly = false; // Reset yearly when reminder is disabled
                  _removeAfterReminder = false;
                }
              });
            },
          ),
          Text(
            lw('Set reminder'),
            style: TextStyle(color: clText, fontSize: fsMedium),
          ),
        ],
      ),
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
                    _time = TIME_MORNING; // 08:00
                    timeController.text = '08:00';
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
                    _time = TIME_EVENING; // 17:00
                    timeController.text = '17:00';
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


  // Build photo field and camera button
  // Build photo field and camera button
  Widget _buildPhotoField() {
    return GestureDetector(
      onLongPress: () => showHelp(38), // New help ID for photo field
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: photoController,
              style: TextStyle(color: clText),
              readOnly: true,
              decoration: InputDecoration(
                labelText: lw('Photo'),
                labelStyle: TextStyle(color: clText),
                fillColor: clFill,
                filled: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.camera_alt, color: clText),
            tooltip: lw('Take photo'),
            onPressed: _takePicture,
          ),
          IconButton(
            icon: Icon(Icons.clear, color: clText),
            tooltip: lw('Clear photo'),
            onPressed: () async {
              if (photoController.text.isNotEmpty) {
                final wasDeleted = await deletePhotoFile(photoController.text);
                if (wasDeleted) {
                  setState(() {
                    photoController.clear();
                  });
                }
              } else {
                setState(() {
                  photoController.clear();
                });
              }
            },
          ),
        ],
      ),
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

            // Photo field
            _buildPhotoField(),
            SizedBox(height: 10),

            // Priority section
            _buildPrioritySelector(),
            SizedBox(height: 10),

            // Date field
            _buildDateField(),
            SizedBox(height: 10),

            // Reminder checkbox
            _buildReminderSelector(),
            SizedBox(height: 10),

            // Time field
            _buildTimeField(),
            SizedBox(height: 10),

            // Time options (radio buttons)
            _buildTimeOptions(),
            SizedBox(height: 10),

            // NEW: Yearly repeat checkbox
            _buildYearlySelector(),
            SizedBox(height: 10),

            // Remove checkbox (updated)
            _buildRemoveAfterReminderSelector(),
            SizedBox(height: 10),

            // Hidden checkbox (only in hidden mode)
            _buildHiddenSelector(),
          ],
        ),
      ),
    );
  }

}
