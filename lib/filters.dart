// filters.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'globals.dart';

// Класс для хранения данных фильтра
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

  // Проверка, есть ли активные фильтры
  bool get isActive =>
      dateFrom != null ||
          dateTo != null ||
          priority != null ||
          hasReminder != null ||
          (tags != null && tags!.isNotEmpty);

  // Преобразование в строку для отладки
  @override
  String toString() {
    return 'FilterData(dateFrom: $dateFrom, dateTo: $dateTo, priority: $priority, hasReminder: $hasReminder, tags: $tags)';
  }

  // Сброс всех фильтров
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
  // Данные фильтра
  FilterData _filterData = FilterData();

  // Контроллеры для текстовых полей
  late TextEditingController _dateFromController;
  late TextEditingController _dateToController;
  late TextEditingController _tagsController;

  // Временные переменные для UI
  int _selectedPriority = -1; // -1 означает "любой приоритет"
  bool? _selectedHasReminder; // null означает "любое значение"

  @override
  void initState() {
    super.initState();

    // Инициализация данных фильтра из глобальной переменной
    _parseFilterString();

    // Инициализация контроллеров
    _dateFromController = TextEditingController(
        text: _filterData.dateFrom != null
            ? DateFormat('yyyy-MM-dd').format(_filterData.dateFrom!)
            : ''
    );

    _dateToController = TextEditingController(
        text: _filterData.dateTo != null
            ? DateFormat('yyyy-MM-dd').format(_filterData.dateTo!)
            : ''
    );

    _tagsController = TextEditingController(
        text: _filterData.tags ?? ''
    );

    _selectedPriority = _filterData.priority ?? -1;
    _selectedHasReminder = _filterData.hasReminder;
  }

  @override
  void dispose() {
    _dateFromController.dispose();
    _dateToController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  // Преобразование строки фильтра в объект FilterData
  void _parseFilterString() {
    if (xvFilter.isEmpty) {
      _filterData = FilterData();
      return;
    }

    try {
      // Формат: "dateFrom:YYYY-MM-DD|dateTo:YYYY-MM-DD|priority:N|hasReminder:true/false|tags:tag1,tag2"
      final parts = xvFilter.split('|');

      for (final part in parts) {
        final keyValue = part.split(':');
        if (keyValue.length != 2) continue;

        final key = keyValue[0];
        final value = keyValue[1];

        switch (key) {
          case 'dateFrom':
            if (value.isNotEmpty) {
              _filterData.dateFrom = DateFormat('yyyy-MM-dd').parse(value);
            }
            break;
          case 'dateTo':
            if (value.isNotEmpty) {
              _filterData.dateTo = DateFormat('yyyy-MM-dd').parse(value);
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

  // Преобразование объекта FilterData в строку фильтра
  String _buildFilterString() {
    List<String> parts = [];

    if (_filterData.dateFrom != null) {
      parts.add('dateFrom:${DateFormat('yyyy-MM-dd').format(_filterData.dateFrom!)}');
    }

    if (_filterData.dateTo != null) {
      parts.add('dateTo:${DateFormat('yyyy-MM-dd').format(_filterData.dateTo!)}');
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

  // Применение фильтров
  void _applyFilters() {
    // Обновление данных фильтра из UI
    _filterData.priority = _selectedPriority >= 0 ? _selectedPriority : null;
    _filterData.hasReminder = _selectedHasReminder;
    _filterData.tags = _tagsController.text.trim().isEmpty ? null : _tagsController.text.trim();

    // Обновление глобальной строки фильтра
    xvFilter = _buildFilterString();

    myPrint('Filter applied: $xvFilter');

    // Показать сообщение о применении фильтра
    if (_filterData.isActive) {
      okInfoBarGreen(lw('Filter applied'));
    } else {
      okInfoBarBlue(lw('All filters cleared'));
    }

    // Вернуться на предыдущий экран с сигналом обновления
    Navigator.pop(context, true);
  }

  // Сброс всех фильтров
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

  // Выбор даты "с"
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
            dialogTheme: DialogTheme(
              backgroundColor: clFill,
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
        _filterData.dateFrom = picked;
        _dateFromController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  // Выбор даты "по"
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
            dialogTheme: DialogTheme(
              backgroundColor: clFill,
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
        _filterData.dateTo = picked;
        _dateToController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  // Построение виджета выбора приоритета
  Widget _buildPrioritySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          lw('Priority filter'),
          style: TextStyle(
            color: clText,
            fontSize: fsMedium,
          ),
        ),
        SizedBox(height: 8),
        Row(
          children: [
            // Кнопка "минус"
            ElevatedButton(
              onPressed: _selectedPriority > -1
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

            // Отображение текущего значения
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
                _selectedPriority == -1 ? lw('Any') : _selectedPriority.toString(),
                style: TextStyle(
                  color: clText,
                  fontSize: fsMedium,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            // Кнопка "плюс"
            ElevatedButton(
              onPressed: _selectedPriority < 3
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

            // Звездочки для визуализации
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (index) {
                  return Icon(
                    Icons.star,
                    color: (_selectedPriority >= 0 && index < _selectedPriority) ? clUpBar : clFill,
                    size: 34,
                  );
                }),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Построение селектора напоминаний
  Widget _buildReminderSelector() {
    return Row(
      children: [
        Text(
          lw('Reminder filter'),
          style: TextStyle(
            color: clText,
            fontSize: fsMedium,
          ),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: clUpBar,
        foregroundColor: clText,
        title: Text(lw('Filters')),
        actions: [
          // Кнопка сброса
          IconButton(
            icon: Icon(Icons.clear_all),
            tooltip: lw('Reset all filters'),
            onPressed: _resetFilters,
          ),
          // Кнопка применения
          IconButton(
            icon: Icon(Icons.check),
            tooltip: lw('Apply filters'),
            onPressed: _applyFilters,
          ),
          // Кнопка отмены
          IconButton(
            icon: Icon(Icons.cancel),
            tooltip: lw('Cancel'),
            onPressed: () {
              Navigator.pop(context, false);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Фильтр по дате "с"
            Text(
              lw('Date from'),
              style: TextStyle(
                color: clText,
                fontSize: fsMedium,
              ),
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dateFromController,
                    style: TextStyle(color: clText),
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: lw('Date from'),
                      labelStyle: TextStyle(color: clText),
                      fillColor: clFill,
                      filled: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.calendar_today, color: clText),
                  onPressed: () => _selectDateFrom(context),
                ),
                IconButton(
                  icon: Icon(Icons.clear, color: clText),
                  onPressed: () {
                    setState(() {
                      _dateFromController.clear();
                      _filterData.dateFrom = null;
                    });
                  },
                ),
              ],
            ),
            SizedBox(height: 16),

            // Фильтр по дате "по"
            Text(
              lw('Date to'),
              style: TextStyle(
                color: clText,
                fontSize: fsMedium,
              ),
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dateToController,
                    style: TextStyle(color: clText),
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: lw('Date to'),
                      labelStyle: TextStyle(color: clText),
                      fillColor: clFill,
                      filled: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.calendar_today, color: clText),
                  onPressed: () => _selectDateTo(context),
                ),
                IconButton(
                  icon: Icon(Icons.clear, color: clText),
                  onPressed: () {
                    setState(() {
                      _dateToController.clear();
                      _filterData.dateTo = null;
                    });
                  },
                ),
              ],
            ),
            SizedBox(height: 16),

            // Фильтр по приоритету
            _buildPrioritySelector(),
            SizedBox(height: 16),

            // Фильтр по напоминаниям
            _buildReminderSelector(),
            SizedBox(height: 16),

            // Фильтр по тегам
            Text(
              lw('Tags (comma separated)'),
              style: TextStyle(
                color: clText,
                fontSize: fsMedium,
              ),
            ),
            SizedBox(height: 8),
            TextField(
              controller: _tagsController,
              style: TextStyle(color: clText),
              decoration: InputDecoration(
                labelText: lw('Tags'),
                labelStyle: TextStyle(color: clText),
                fillColor: clFill,
                filled: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Функция для получения текста состояния фильтра
Future<String> getFilterStatusText() async {
  bool hasTagFilter = xvTagFilter.isNotEmpty;
  bool hasMainFilter = xvFilter.isNotEmpty;

  // Получаем значение настройки Last items
  final lastItemsStr = await getSetting("Last items") ?? defSettings["Last items"];
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