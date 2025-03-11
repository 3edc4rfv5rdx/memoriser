// additem.dart
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'globals.dart';

class EditItemPage extends StatefulWidget {
  final Map<String, dynamic>? item;

  const EditItemPage({
    Key? key,
    this.item,
  }) : super(key: key);

  @override
  _EditItemPageState createState() => _EditItemPageState();
}

class _EditItemPageState extends State<EditItemPage> {
  late TextEditingController titleController;
  late TextEditingController contentController;
  late TextEditingController tagsController;
  late TextEditingController dateController;

  DateTime? _date;
  int _priority = 1; // Default priority value
  bool _remind = false; // Default remind value

  @override
  void initState() {
    super.initState();
    final isEditing = widget.item != null;

    titleController = TextEditingController(
      text: isEditing ? widget.item!['title'] : '',
    );
    contentController = TextEditingController(
      text: isEditing ? widget.item!['content'] : '',
    );
    tagsController = TextEditingController(
      text: isEditing ? widget.item!['tags'] : '',
    );

    // Initialize date
    _date = isEditing && widget.item!['date'] != null
        ? DateTime.fromMillisecondsSinceEpoch(widget.item!['date'])
        : null;
    dateController = TextEditingController(
      text: _date != null
          ? DateFormat(ymdDateFormat).format(_date!)
          : '',
    );

    // Initialize priority (0-3 range)
    if (isEditing && widget.item!['priority'] != null) {
      _priority = widget.item!['priority'];
      // Ensure priority is within 0-3 range
      if (_priority < 0 || _priority > 3) {
        _priority = _priority > 3 ? 3 : 0; // Convert old values to new range
      }
    } else {
      _priority = 0; // Default priority
    }

    // Initialize remind checkbox
    if (isEditing && widget.item!['remind'] != null) {
      _remind = widget.item!['remind'] == 1;
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    contentController.dispose();
    tagsController.dispose();
    dateController.dispose();
    super.dispose();
  }

  // Save function that directly interacts with the database
  Future<void> _saveItem() async {
    if (titleController.text.trim().isEmpty) {
      okInfoBarRed(lw('Title cannot be empty'), duration: Duration(seconds: 4));
      return;
    }

    if (_remind && _date == null) {
      okInfoBarRed(lw('Set a date for the reminder'), duration: Duration(seconds: 4));
      return;
    }

    // Convert date to milliseconds for storage
    final dateMillis = _date?.millisecondsSinceEpoch;
    final remindValue = _remind ? 1 : 0;

    try {
      if (widget.item != null) {
        // Update existing item
        await mainDb.update(
          'items',
          {
            'title': titleController.text.trim(),
            'content': contentController.text.trim(),
            'tags': tagsController.text.trim(),
            'priority': _priority,
            'date': dateMillis,
            'remind': remindValue,
          },
          where: 'id = ?',
          whereArgs: [widget.item!['id']],
        );
        myPrint("Item updated: ${widget.item!['id']} - ${titleController.text}");
      } else {
        // Insert new item
        await mainDb.insert(
          'items',
          {
            'title': titleController.text.trim(),
            'content': contentController.text.trim(),
            'tags': tagsController.text.trim(),
            'priority': _priority,
            'date': dateMillis,
            'remind': remindValue,
            'created': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        myPrint("Item inserted: ${titleController.text}");
      }

      // Return to previous screen
      Navigator.pop(context, true);
    } catch (e) {
      // Show error message if database operation fails
      okInfoBarPurple(lw('Error saving item') + ': $e');
      myPrint("Error saving item: $e");
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
            dialogTheme: DialogTheme(
              backgroundColor: clFill,
            ),
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
            style: TextStyle(
              color: clText,
              fontSize: fsMedium,
            ),
          ),
          SizedBox(height: 8),
          // Single row containing all elements
          Row(
            children: [
              // LEFT SIDE: Minus button with upbar color
              ElevatedButton(
                onPressed: _priority > 0
                    ? () => setState(() => _priority--)
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
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // Plus button with upbar color
              ElevatedButton(
                onPressed: _priority < 3
                    ? () => setState(() => _priority++)
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

              // RIGHT SIDE: Checkbox and reminder text
              GestureDetector(
                onLongPress: () => showHelp(35), // ID 35 для чекбокса и текста напоминания
                child: Row(
                  children: [
                    Checkbox(
                      value: _remind,
                      activeColor: clUpBar,
                      checkColor: clText,
                      onChanged: (value) {
                        setState(() {
                          _remind = value ?? false;
                        });
                      },
                    ),
                    Text(
                      lw('Set reminder'),
                      style: TextStyle(
                        color: clText,
                        fontSize: fsMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
              readOnly: true, // Make the field read-only
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
              });
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.item != null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: clUpBar,
        foregroundColor: clText,
        title: GestureDetector(
          onLongPress: () => showHelp(30), // ID 30 для заголовка
          child: Text(
            isEditing ? lw('Edit Item') : lw('New Item'),
          ),
        ),
        leading: GestureDetector(
          onLongPress: () => showHelp(10), // ID 10 для кнопки назад
          child: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        actions: [
          GestureDetector(
            onLongPress: () => showHelp(12), // ID 12 для кнопки сохранения
            child: IconButton(
              icon: Icon(Icons.save),
              onPressed: _saveItem,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title field
            GestureDetector(
              onLongPress: () => showHelp(31), // ID 31 для поля заголовка
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
            SizedBox(height: 16),

            // Content field
            GestureDetector(
              onLongPress: () => showHelp(32), // ID 32 для поля содержимого
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
                maxLines: 5,
              ),
            ),
            SizedBox(height: 16),

            // Tags field
            GestureDetector(
              onLongPress: () => showHelp(33), // ID 33 для поля тегов
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
            SizedBox(height: 16),

            // Priority section
            _buildPrioritySelector(),
            SizedBox(height: 16),

            // Date field
            _buildDateField(),
          ],
        ),
      ),
    );
  }
}