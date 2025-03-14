// tagscloud.dart (упрощенная версия)
import 'package:flutter/material.dart';
import 'globals.dart';

class TagsCloudScreen extends StatefulWidget {
  @override
  _TagsCloudScreenState createState() => _TagsCloudScreenState();
}

class _TagsCloudScreenState extends State<TagsCloudScreen> {
  bool _isLoading = true;
  List<TagData> _tags = [];
  List<String> _selectedTags = [];

  @override
  void initState() {
    super.initState();
    _loadAllTags();
  }

  // Загрузка тегов с использованием общей функции
  Future<void> _loadAllTags() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Используем общую функцию для получения тегов с частотами
      final tagsWithCounts = await getTagsWithCounts();

      // Преобразуем результат в объекты TagData
      final tags = tagsWithCounts.map((tag) =>
          TagData(
            name: tag['name'],
            count: tag['count'],
          )
      ).toList();

      // Инициализируем выбранные теги на основе текущего фильтра
      List<String> initialSelectedTags = [];
      if (xvTagFilter.isNotEmpty) {
        initialSelectedTags = xvTagFilter.split(',').map((tag) => tag.trim()).toList();
      }

      setState(() {
        _tags = tags;
        _selectedTags = initialSelectedTags;
        _isLoading = false;
      });
    } catch (e) {
      myPrint('Error loading tags: $e');
      setState(() {
        _tags = [];
        _isLoading = false;
      });
      okInfoBarRed(lw('Error loading tags'));
    }
  }

  // Apply the selected tags filter and return to main screen
  void _applyFilter() {
    // Join selected tags with comma
    xvTagFilter = _selectedTags.join(',');
    myPrint('Tag filter applied: $xvTagFilter');

    // Show confirmation message
    if (_selectedTags.isEmpty) {
      okInfoBarBlue(lw('All tags shown'));
    } else {
      okInfoBarGreen(lw('Filter applied: ') + xvTagFilter);
    }

    // Return to previous screen with refresh signal
    Navigator.pop(context, true);
  }

  // Clear all selected tags
  void _clearSelection() {
    setState(() {
      _selectedTags = [];
    });
  }

  // Toggle selection of a tag
  void _toggleTag(String tag) {
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
      } else {
        _selectedTags.add(tag);
      }
    });
  }

  // Get font size based on tag count and position
  double _getTagFontSize(int count, int maxCount, int index, int totalTags) {
    // Calculate relative size (0.0 to 1.0) based on count
    double relativeSize = count / maxCount;

    // Use font size based primarily on frequency
    if (relativeSize < 0.3) {
      return 15.0; // Smallest size
    } else if (relativeSize < 0.5) {
      return 17.0; // Small-medium size
    } else if (relativeSize < 0.7) {
      return 19.0; // Medium size
    } else if (relativeSize < 0.9) {
      return 22.0; // Large size
    } else {
      return 26.0; // Extra large size
    }
  }

  // Build the tag cloud layout
  Widget _buildTagCloud() {
    if (_tags.isEmpty) {
      return Center(
        child: Text(
          lw('No tags found'),
          style: TextStyle(color: clText, fontSize: fsMedium),
        ),
      );
    }

    // Calculate the maximum count for font size scaling
    int maxCount = _tags.isNotEmpty ? _tags.first.count : 1;

    // Top-aligned tag cloud with reduced vertical spacing
    return SingleChildScrollView(
      child: Wrap(
        alignment: WrapAlignment.start, // Start from the top-left
        spacing: 12.0, // Gap between tags horizontally
        runSpacing: 8.0, // Reduced gap between lines
        children: _tags.asMap().entries.map((entry) {
          final index = entry.key;
          final tag = entry.value;
          final fontSize = _getTagFontSize(tag.count, maxCount, index, _tags.length);
          final isSelected = _selectedTags.contains(tag.name);

          return GestureDetector(
            onTap: () => _toggleTag(tag.name),
            child: Chip(
              backgroundColor: isSelected ? clUpBar : clFill,
              label: Text(
                '${tag.name} (${tag.count})',
                style: TextStyle(
                  color: isSelected ? clText : clText,
                  fontSize: fontSize,
                  fontWeight: isSelected ? fwBold : fwNormal,
                ),
              ),
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4), // Reduced vertical padding
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: xvHiddenMode ? hidModeColor : clUpBar,
        foregroundColor: clText,
        title: GestureDetector(
          onLongPress: () => showHelp(50), // ID 50 for Tags Cloud screen title
          child: Row(
            children: [
              Text(lw('Tags'),
                  style: TextStyle(
                    fontSize: fsLarge,
                    color: clText,
                    fontWeight: fwBold,)
              ),
              if (xvHiddenMode)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Icon(Icons.visibility_off, size: 16),
                ),
            ],
          ),
        ),
        leading: GestureDetector(
          onLongPress: () => showHelp(10), // ID 10 for back button (same as in filters.dart)
          child: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, false),
          ),
        ),
        actions: [
          // Clear button
          GestureDetector(
            onLongPress: () => showHelp(41), // ID 41 for clear selection button
            child: IconButton(
              icon: Icon(Icons.clear_all),
              tooltip: lw('Clear selection'),
              onPressed: _clearSelection,
            ),
          ),
          // Apply button
          GestureDetector(
            onLongPress: () => showHelp(42), // ID 42 for apply filter button (same as in filters.dart)
            child: IconButton(
              icon: Icon(Icons.check),
              tooltip: lw('Apply filter'),
              onPressed: _applyFilter,
            ),
          ),
          // Cancel button
          GestureDetector(
            onLongPress: () => showHelp(43), // ID 43 for cancel button (same as in filters.dart)
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
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fixed height container for selected tags information (smaller height)
          GestureDetector(
            onLongPress: () => showHelp(52), // ID 52 for selected tags indicator
            child: Container(
              height: 24, // Reduced fixed height
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: _selectedTags.isEmpty
                  ? Container() // Empty container when no tags selected
                  : Text(
                lw('Selected tags') + ': ${_selectedTags.join(", ")}',
                style: TextStyle(
                  color: clText,
                  fontSize: fsMedium,
                  fontWeight: fwBold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // Tags cloud - using Expanded to take remaining space
          Expanded(
            child: GestureDetector(
              onLongPress: () => showHelp(53), // ID 53 for tag cloud
              child: Container(
                width: double.infinity,
                alignment: Alignment.topLeft,
                padding: EdgeInsets.all(16),
                child: _buildTagCloud(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Data class for tag information
class TagData {
  final String name;
  final int count;

  TagData({
    required this.name,
    required this.count,
  });
}
