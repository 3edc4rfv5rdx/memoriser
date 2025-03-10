// tagscloud.dart
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

  // Load all tags from the database
  Future<void> _loadAllTags() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Query all items to extract tags
      final allItems = await mainDb.query('items');
      Map<String, int> tagCounts = {};

      // Process each item's tags
      for (var item in allItems) {
        final tagsString = item['tags'] as String?;
        if (tagsString != null && tagsString.isNotEmpty) {
          // Split tags by comma and trim whitespace
          List<String> itemTags = tagsString.split(',')
              .map((tag) => tag.trim())
              .where((tag) => tag.isNotEmpty)
              .toList();

          // Count occurrences of each tag
          for (var tag in itemTags) {
            tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
          }
        }
      }

      // Convert to TagData objects
      List<TagData> tags = tagCounts.entries.map((entry) {
        return TagData(
          name: entry.key,
          count: entry.value,
        );
      }).toList();

      // Sort by count (descending) and then by name (alphabetically) for equal counts
      tags.sort((a, b) {
        // First compare by count (descending)
        int countComparison = b.count.compareTo(a.count);

        // If counts are equal, sort alphabetically by name
        if (countComparison == 0) {
          return a.name.compareTo(b.name);
        }

        return countComparison;
      });

      setState(() {
        _tags = tags;
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

  // Get font size based on tag count and position - with MUCH larger sizes
  double _getTagFontSize(int count, int maxCount, int index, int totalTags) {
    // Calculate relative size (0.0 to 1.0) based on count
    double relativeSize = count / maxCount;

    // Calculate position factor (0.0 to 1.0) - how far from center
    // 0.0 means center, 1.0 means at the edge
    double positionFactor;
    if (totalTags <= 1) {
      positionFactor = 0.0;
    } else {
      // Normalize index to be centered around the middle
      int middleIndex = totalTags ~/ 2;
      int distanceFromMiddle = (index - middleIndex).abs();
      positionFactor = distanceFromMiddle / (totalTags / 2);
    }

    // Combine count and position factors
    // Higher counts get bigger, further from center gets smaller
    double combinedFactor = relativeSize * (1.0 - 0.5 * positionFactor);

    // Use much more dramatic font size differences
    if (combinedFactor < 0.3) {
      return 14.0; // Smallest size
    } else if (combinedFactor < 0.5) {
      return 18.0; // Small-medium size
    } else if (combinedFactor < 0.7) {
      return 22.0; // Medium size
    } else if (combinedFactor < 0.9) {
      return 26.0; // Large size
    } else {
      return 32.0; // Extra large size
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

    // Create a centered cloud where most frequent tags are in the center
    // and less frequent ones spread outwards
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12.0, // Increased gap between tags horizontally
        runSpacing: 16.0, // Increased gap between lines
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
                  color: isSelected ? clText : clText.withOpacity(0.8),
                  fontSize: fontSize,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8), // Increased padding
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
        backgroundColor: clUpBar,
        foregroundColor: clText,
        title: Text(lw('Tags Cloud')),
        actions: [
          // Clear button
          IconButton(
            icon: Icon(Icons.clear_all),
            tooltip: lw('Clear selection'),
            onPressed: _clearSelection,
          ),
          // Apply button
          IconButton(
            icon: Icon(Icons.check),
            tooltip: lw('Apply filter'),
            onPressed: _applyFilter,
          ),
          // Cancel button
          IconButton(
            icon: Icon(Icons.cancel),
            tooltip: lw('Cancel'),
            onPressed: () {
              Navigator.pop(context, false);
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Selected tags information
            if (_selectedTags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  lw('Selected tags') + ': ${_selectedTags.join(", ")}',
                  style: TextStyle(
                    color: clText,
                    fontSize: fsMedium,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            // Tags cloud
            Expanded(
              child: _buildTagCloud(),
            ),
          ],
        ),
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