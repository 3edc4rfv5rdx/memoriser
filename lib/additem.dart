// additem.dart
import 'package:flutter/material.dart';
import 'globals.dart';

class EditItemPage extends StatefulWidget {
  final Map<String, dynamic>? item;
  final Function onSave;
  
  const EditItemPage({
    Key? key, 
    this.item,
    required this.onSave
  }) : super(key: key);
  
  @override
  _EditItemPageState createState() => _EditItemPageState();
}

class _EditItemPageState extends State<EditItemPage> {
  late TextEditingController titleController;
  late TextEditingController contentController;
  late TextEditingController tagsController;
  
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
  }
  
  @override
  void dispose() {
    titleController.dispose();
    contentController.dispose();
    tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.item != null;
    
    return Scaffold(
      appBar: AppBar(
        backgroundColor: clUpBar,
        foregroundColor: clText,
        title: Text(
          isEditing ? lw('Edit Item') : lw('New Item'),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.save),
            onPressed: () async {
              if (titleController.text.trim().isEmpty) {
                okInfo(lw('Title cannot be empty'));
                return;
              }

              if (isEditing) {
                widget.onSave(
                  widget.item!['id'],
                  titleController.text.trim(),
                  contentController.text.trim(),
                  tagsController.text.trim(),
                );
              } else {
                widget.onSave(
                  null,
                  titleController.text.trim(),
                  contentController.text.trim(),
                  tagsController.text.trim(),
                );
              }

              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
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
            SizedBox(height: 16),
            TextField(
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
            SizedBox(height: 16),
            TextField(
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
          ],
        ),
      ),
    );
  }
}
