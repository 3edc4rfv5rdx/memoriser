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

  @override
  void initState() {
    super.initState();

    // Initialize filter data from global variable
    _parseFilterString();

    // Initialize controllers
    _dateFromController = TextEditingController(
        text: _filterData.dateFrom != null
            ? DateFormat(ymdDateFormat).format(_filterData.dateFrom!)
            : ''
    );

    _dateToController = TextEditingController(
        text: _filterData.dateTo != null
            ? DateFormat(ymdDateFormat).format(_filterData.dateTo!)
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
      parts.add('dateFrom:${DateFormat(ymdDateFormat).format(_filterData.dateFrom!)}');
    }

    if (_filterData.dateTo != null) {
      parts.add('dateTo:${DateFormat(ymdDateFormat).format(_filterData.dateTo!)}');
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

  // Apply filters
  void _applyFilters() {
    // Update filter data from UI
    _filterData.priority = _selectedPriority >= 0 ? _selectedPriority : null;
    _filterData.hasReminder = _selectedHasReminder;
    _filterData.tags = _tagsController.text.trim().isEmpty ? null : _tagsController.text.trim();

    // Update global filter string
    xvFilter = _buildFilterString();

    myPrint('Filter applied: $xvFilter');

    // Show confirmation message
    if (_filterData.isActive) {
      okInfoBarGreen(lw('Filter applied'));
    } else {
      okInfoBarBlue(lw('All filters cleared'));
    }

    // Return to previous screen with refresh signal
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
        _dateToController.text = DateFormat(ymdDateFormat).format(picked);
      });
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
            style: TextStyle(
              color: clText,
              fontSize: fsMedium,
            ),
          ),
          SizedBox(height: 8),
          Row(
            children: [
              // Minus button
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
                  _selectedPriority == -1 ? lw('Any') : _selectedPriority.toString(),
                  style: TextStyle(
                    color: clText,
                    fontSize: fsMedium,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              // Plus button
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

              // Stars for visualization
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
          child: Text(lw('Filters')),
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
          ),
          // Apply button
          GestureDetector(
            onLongPress: () => showHelp(42), // ID 42 for apply button
            child: IconButton(
              icon: Icon(Icons.check),
              tooltip: lw('Apply filters'),
              onPressed: _applyFilters,
            ),
          ),
          // Cancel button
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
            // "Date from" filter
            GestureDetector(
              onLongPress: () => showHelp(36), // ID 36 for date field
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                ],
              ),
            ),
            SizedBox(height: 16),

            // "Date to" filter
            GestureDetector(
              onLongPress: () => showHelp(36), // ID 36 for date field (same as date from)
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                ],
              ),
            ),
            SizedBox(height: 16),

            // Priority filter
            _buildPrioritySelector(),
            SizedBox(height: 16),

            // Reminder filter
            _buildReminderSelector(),
            SizedBox(height: 16),

            // Tags filter
            GestureDetector(
              onLongPress: () => showHelp(33), // ID 33 for tags field (same as in additem.dart)
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
          ],
        ),
      ),
    );
  }
}

// Function to get filter status text
Future<String> getFilterStatusText() async {
  bool hasTagFilter = xvTagFilter.isNotEmpty;
  bool hasMainFilter = xvFilter.isNotEmpty;

  // Get "Last items" setting value
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