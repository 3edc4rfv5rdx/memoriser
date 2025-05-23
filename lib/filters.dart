// filters.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'globals.dart';

// Class for storing filter data
class FilterData {
  DateTime? dateFrom;
  DateTime? dateTo;
  int? priority;
  bool? hasReminder;
  String? tags;

  FilterData({
    this.dateFrom,
    this.dateTo,
    this.priority,
    this.hasReminder,
    this.tags,
  });

  // Check if any filters are active
  bool get isActive =>
      dateFrom != null ||
      dateTo != null ||
      priority != null ||
      hasReminder != null ||
      (tags != null && tags!.isNotEmpty);

  // Convert to string for debugging
  @override
  String toString() {
    return 'FilterData(dateFrom: $dateFrom, dateTo: $dateTo, priority: $priority, hasReminder: $hasReminder, tags: $tags)';
  }

  // Reset all filters
  void reset() {
    dateFrom = null;
    dateTo = null;
    priority = null;
    hasReminder = null;
    tags = null;
  }
}

class FiltersScreen extends StatefulWidget {
  @override
  _FiltersScreenState createState() => _FiltersScreenState();
}

class _FiltersScreenState extends State<FiltersScreen> {
  // Filter data
  FilterData _filterData = FilterData();

  // Controllers for text fields
  late TextEditingController _dateFromController;
  late TextEditingController _dateToController;
  late TextEditingController _tagsController;

  // Temporary variables for UI
  int _selectedPriority = -1; // -1 means "any priority"
  bool? _selectedHasReminder; // null means "any value"

  // Список тегов для выпадающего списка
  List<Map<String, dynamic>> _tagsWithCounts = [];

  @override
  void initState() {
    super.initState();

    // Initialize filter data from global variable
    _parseFilterString();

    // Initialize controllers
    _dateFromController = TextEditingController(
      text:
          _filterData.dateFrom != null
              ? DateFormat(ymdDateFormat).format(_filterData.dateFrom!)
              : '',
    );

    _dateToController = TextEditingController(
      text:
          _filterData.dateTo != null
              ? DateFormat(ymdDateFormat).format(_filterData.dateTo!)
              : '',
    );

    _tagsController = TextEditingController(text: _filterData.tags ?? '');

    _selectedPriority = _filterData.priority ?? -1;
    _selectedHasReminder = _filterData.hasReminder;

    // Загружаем теги при инициализации
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
    _dateFromController.dispose();
    _dateToController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  // Convert filter string to FilterData object
  void _parseFilterString() {
    if (xvFilter.isEmpty) {
      _filterData = FilterData();
      return;
    }

    try {
      // Format: "dateFrom:YYYY-MM-DD|dateTo:YYYY-MM-DD|priority:N|hasReminder:true/false|tags:tag1,tag2"
      final parts = xvFilter.split('|');

      for (final part in parts) {
        final keyValue = part.split(':');
        if (keyValue.length != 2) continue;

        final key = keyValue[0];
        final value = keyValue[1];

        switch (key) {
          case 'dateFrom':
            if (value.isNotEmpty) {
              _filterData.dateFrom = DateFormat(ymdDateFormat).parse(value);
            }
            break;
          case 'dateTo':
            if (value.isNotEmpty) {
              _filterData.dateTo = DateFormat(ymdDateFormat).parse(value);
            }
            break;
          case 'priority':
            if (value.isNotEmpty) {
              _filterData.priority = int.tryParse(value);
            }
            break;
          case 'hasReminder':
            if (value.isNotEmpty) {
              _filterData.hasReminder = value == 'true';
            }
            break;
          case 'tags':
            if (value.isNotEmpty) {
              _filterData.tags = value;
            }
            break;
        }
      }
    } catch (e) {
      myPrint('Error parsing filter string: $e');
      _filterData = FilterData();
    }
  }

  // Convert FilterData object to filter string
  String _buildFilterString() {
    List<String> parts = [];

    if (_filterData.dateFrom != null) {
      parts.add(
        'dateFrom:${DateFormat(ymdDateFormat).format(_filterData.dateFrom!)}',
      );
    }

    if (_filterData.dateTo != null) {
      parts.add(
        'dateTo:${DateFormat(ymdDateFormat).format(_filterData.dateTo!)}',
      );
    }

    if (_filterData.priority != null) {
      parts.add('priority:${_filterData.priority}');
    }

    if (_filterData.hasReminder != null) {
      parts.add('hasReminder:${_filterData.hasReminder}');
    }

    if (_filterData.tags != null && _filterData.tags!.isNotEmpty) {
      parts.add('tags:${_filterData.tags}');
    }

    return parts.join('|');
  }

  // Функция для показа диалога обмена дат
  Future<void> _showSwapDatesDialog() async {
    bool swapDates =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              backgroundColor: clFill,
              title: Text(
                lw('Invalid Date Range'),
                style: TextStyle(color: clText),
              ),
              content: Text(
                lw(
                  'Date from is after Date to. Would you like to swap the dates?',
                ),
                style: TextStyle(color: clText),
              ),
              actions: [
                TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: clUpBar,
                    foregroundColor: clText,
                  ),
                  child: Text(lw('Cancel')),
                  onPressed: () {
                    Navigator.pop(context, false);
                  },
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: clUpBar,
                    foregroundColor: clText,
                  ),
                  child: Text(lw('Swap Dates')),
                  onPressed: () {
                    Navigator.pop(context, true);
                  },
                ),
              ],
            );
          },
        ) ??
        false;

    if (swapDates) {
      setState(() {
        // Меняем даты местами
        final tempDate = _filterData.dateFrom;
        _filterData.dateFrom = _filterData.dateTo;
        _filterData.dateTo = tempDate;

        // Также обновляем текст в полях
        final tempText = _dateFromController.text;
        _dateFromController.text = _dateToController.text;
        _dateToController.text = tempText;
      });
    }
  }

  // В методе _applyFilters добавляем полную проверку
  void _applyFilters() async {
    if (_dateFromController.text.isNotEmpty) {
      if (!validateDateInput(_dateFromController.text)) {
        okInfoBarOrange(
          lw('Invalid date format in From field. Use YYYY-MM-DD'),
        );
        return;
      }
    }
    if (_dateToController.text.isNotEmpty) {
      if (!validateDateInput(_dateToController.text)) {
        okInfoBarOrange(lw('Invalid date format in To field. Use YYYY-MM-DD'));
        return;
      }
    }
    // Проверка, что начальная дата не позже конечной & swap
    if (_filterData.dateFrom != null && _filterData.dateTo != null) {
      if (_filterData.dateFrom!.isAfter(_filterData.dateTo!)) {
        await _showSwapDatesDialog();
        return; // Выходим без применения фильтра
      }
    }
    // Код применения фильтра выполнится только если даты корректны
    _filterData.priority = _selectedPriority >= 0 ? _selectedPriority : null;
    _filterData.hasReminder = _selectedHasReminder;
    _filterData.tags =
        _tagsController.text.trim().isEmpty
            ? null
            : _tagsController.text.trim();
    xvFilter = _buildFilterString();
    if (_filterData.isActive) {
      okInfoBarGreen(lw('Filter applied'));
    } else {
      okInfoBarBlue(lw('All filters cleared'));
    }
    Navigator.pop(context, true);
  }

  // Reset all filters
  void _resetFilters() {
    setState(() {
      _filterData.reset();
      _selectedPriority = -1;
      _selectedHasReminder = null;
      _dateFromController.clear();
      _dateToController.clear();
      _tagsController.clear();
    });
  }

  // Select "date from"
  Future<void> _selectDateFrom(BuildContext context) async {
    final DateTime initialDate = _filterData.dateFrom ?? DateTime.now();

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
        _filterData.dateFrom = picked;
        _dateFromController.text = DateFormat(ymdDateFormat).format(picked);
      });
    }
  }

  // Select "date to"
  Future<void> _selectDateTo(BuildContext context) async {
    final DateTime initialDate = _filterData.dateTo ?? DateTime.now();

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
        _filterData.dateTo = picked;
        _dateToController.text = DateFormat(ymdDateFormat).format(picked);
      });
    }
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
          content: Container(
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
    String currentTags = _tagsController.text.trim();

    // Если поле пустое, просто добавляем тег
    if (currentTags.isEmpty) {
      _tagsController.text = tag;
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
        _tagsController.text = currentTags + ', ' + tag;
      } else {
        // Тег уже есть, показываем сообщение
        okInfoBarBlue(lw('Tag already added'));
      }
    }
  }

  // Build priority selector widget
  Widget _buildPrioritySelector() {
    return GestureDetector(
      onLongPress: () => showHelp(34), // ID 34 for priority controls
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lw('Priority filter'),
            style: TextStyle(color: clText, fontSize: fsMedium),
          ),
          SizedBox(height: 8),
          Row(
            children: [
              // Minus button
              ElevatedButton(
                onPressed:
                    _selectedPriority > -1
                        ? () => setState(() => _selectedPriority--)
                        : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: clUpBar,
                  foregroundColor: clText,
                  shape: CircleBorder(),
                  padding: EdgeInsets.all(8),
                  minimumSize: Size(36, 36),
                ),
                child: Icon(Icons.remove, size: 20),
              ),

              // Display current value
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
                  _selectedPriority == -1
                      ? lw('Any')
                      : _selectedPriority.toString(),
                  style: TextStyle(
                    color: clText,
                    fontSize: fsMedium,
                    fontWeight: fwBold,
                  ),
                ),
              ),

              // Plus button
              ElevatedButton(
                onPressed:
                    _selectedPriority < 3
                        ? () => setState(() => _selectedPriority++)
                        : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: clUpBar,
                  foregroundColor: clText,
                  shape: CircleBorder(),
                  padding: EdgeInsets.all(8),
                  minimumSize: Size(36, 36),
                ),
                child: Icon(Icons.add, size: 20),
              ),

              // Stars for visualization
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (index) {
                    return Icon(
                      Icons.star,
                      color:
                          (_selectedPriority >= 0 && index < _selectedPriority)
                              ? clUpBar
                              : clFill,
                      size: 34,
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

  // Build reminder selector
  Widget _buildReminderSelector() {
    return GestureDetector(
      onLongPress: () => showHelp(35), // ID 35 for reminder selector
      child: Row(
        children: [
          Text(
            lw('Reminder filter'),
            style: TextStyle(color: clText, fontSize: fsMedium),
          ),
          SizedBox(width: 16),
          DropdownButton<bool?>(
            value: _selectedHasReminder,
            dropdownColor: clMenu,
            hint: Text(lw('Any'), style: TextStyle(color: clText)),
            items: [
              DropdownMenuItem<bool?>(
                value: null,
                child: Text(lw('Any'), style: TextStyle(color: clText)),
              ),
              DropdownMenuItem<bool?>(
                value: true,
                child: Text(lw('Yes'), style: TextStyle(color: clText)),
              ),
              DropdownMenuItem<bool?>(
                value: false,
                child: Text(lw('No'), style: TextStyle(color: clText)),
              ),
            ],
            onChanged: (value) {
              setState(() {
                _selectedHasReminder = value;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDateField(
    String label,
    TextEditingController controller,
    Future<void> Function() onSelectDate,
  ) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            style: TextStyle(color: clText),
            readOnly: false,
            // Разрешаем ручной ввод
            onChanged: (value) {
              if (value.isEmpty) {
                // Если поле пустое, сбрасываем соответствующую дату
                if (label == lw('Date from')) {
                  _filterData.dateFrom = null;
                } else {
                  _filterData.dateTo = null;
                }
              } else {
                // Проверяем формат и корректность даты
                if (isValidDateFormat(value) && isValidDate(value)) {
                  try {
                    final date = DateFormat(ymdDateFormat).parse(value);
                    if (label == lw('Date from')) {
                      _filterData.dateFrom = date;
                    } else {
                      _filterData.dateTo = date;
                    }
                  } catch (e) {
                    myPrint('Error parsing date: $e');
                  }
                }
              }
            },
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(color: clText),
              hintText: 'YYYY-MM-DD',
              hintStyle: TextStyle(color: clText),
              fillColor: clFill,
              filled: true,
              border: OutlineInputBorder(),
              floatingLabelBehavior: FloatingLabelBehavior.auto,
            ),
          ),
        ),
        IconButton(
          icon: Icon(Icons.calendar_today, color: clText),
          onPressed: onSelectDate,
        ),
        IconButton(
          icon: Icon(Icons.clear, color: clText),
          onPressed: () {
            setState(() {
              controller.clear();
              if (label == lw('Date from')) {
                _filterData.dateFrom = null;
              } else {
                _filterData.dateTo = null;
              }
            });
          },
        ),
      ],
    );
  }

  // Build tags field with tag picker button
  Widget _buildTagsField() {
    return GestureDetector(
      onLongPress: () => showHelp(33), // ID 33 for tags field
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _tagsController,
              style: TextStyle(color: clText),
              decoration: InputDecoration(
                labelText: lw('Tags (comma separated)'),
                labelStyle: TextStyle(color: clText),
                fillColor: clFill,
                filled: true,
                border: OutlineInputBorder(),
                floatingLabelBehavior: FloatingLabelBehavior.auto,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.tag, color: clText),
            tooltip: lw('Select from existing tags'),
            onPressed: _showTagsDialog,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: clUpBar,
        foregroundColor: clText,
        title: GestureDetector(
          onLongPress: () => showHelp(40), // ID 40 for screen title
          child: Text(
            lw('Filters'),
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
            onPressed: () => Navigator.pop(context, false),
          ),
        ),
        actions: [
          // Reset button
          GestureDetector(
            onLongPress: () => showHelp(41), // ID 41 for reset button
            child: IconButton(
              icon: Icon(Icons.clear_all),
              tooltip: lw('Reset all filters'),
              onPressed: _resetFilters,
            ),
          ), // Apply button
          GestureDetector(
            onLongPress: () => showHelp(42), // ID 42 for apply button
            child: IconButton(
              icon: Icon(Icons.check),
              tooltip: lw('Apply filters'),
              onPressed: _applyFilters,
            ),
          ), // Cancel button
          GestureDetector(
            onLongPress: () => showHelp(43), // ID 43 for cancel button
            child: IconButton(
              icon: Icon(Icons.cancel),
              tooltip: lw('Cancel'),
              onPressed: () {
                Navigator.pop(context, false);
              },
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // "Date from" field
            _buildDateField(
              lw('Date from'),
              _dateFromController,
              () => _selectDateFrom(context),
            ),
            SizedBox(height: 16),

            // "Date to" field
            _buildDateField(
              lw('Date to'),
              _dateToController,
              () => _selectDateTo(context),
            ),
            SizedBox(height: 16),

            // Tags field - now using the new method with tag button
            _buildTagsField(),
            SizedBox(height: 16),

            // Priority filter
            _buildPrioritySelector(),
            SizedBox(height: 16),

            // Reminder filter
            _buildReminderSelector(),
          ],
        ),
      ),
    );
  }

  // Function to get filter status text
  Future<String> getFilterStatusText() async {
    bool hasTagFilter = xvTagFilter.isNotEmpty;
    bool hasMainFilter = xvFilter.isNotEmpty;

    // Get "Last items" setting value
    final lastItemsStr =
        await getSetting("Last items") ?? defSettings["Last items"];
    final lastItems = int.tryParse(lastItemsStr) ?? 0;
    bool hasLastItems = lastItems > 0;

    if (hasTagFilter && hasMainFilter) {
      return '(FT) ';
    } else if (hasTagFilter) {
      return '(T) ';
    } else if (hasMainFilter) {
      return '(F) ';
    } else if (hasLastItems) {
      return '($lastItems) ';
    } else {
      return '(All) ';
    }
  }
}
