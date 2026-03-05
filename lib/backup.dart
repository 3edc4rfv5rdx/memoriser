// backup.dart
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import 'globals.dart';
import 'reminders.dart';

// Create database backup
Future<String> createBackup() async {
  try {
    myPrint('Starting backup process...');

    final backupDir = await createBackupDirWithDate();
    final backupDirPath = backupDir?.path;

    myPrint('Backup directory path: $backupDirPath');

    if (backupDirPath == null) {
      myPrint('Failed to create backup directory');
      okInfoBarRed(lw('Error creating backup'));
      return lw('Error creating backup');
    }

    // Get main database path
    final databasesPath = await getDatabasesPath();
    myPrint('Database path: $databasesPath');

    final mainDbPath = path.join(databasesPath, mainDbFile);
    myPrint('Main DB file path: $mainDbPath');

    // Check file exists
    bool dbExists = await File(mainDbPath).exists();
    myPrint('Database file exists: $dbExists');

    if (!dbExists) {
      myPrint('Database file not found');
      okInfoBarRed(lw('Error creating backup: database file not found'));
      return lw('Error creating backup: database file not found');
    }

    // Generate filename with date
    final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
    final mainBackupPath = '$backupDirPath/memorizer-$dateStr.db';
    myPrint('Target backup file path: $mainBackupPath');

    // Flush WAL to main file before copying
    try {
      await mainDb.execute("PRAGMA wal_checkpoint(TRUNCATE)");
      myPrint('WAL checkpoint completed for mainDb');
    } catch (e) {
      myPrint('WAL checkpoint warning: $e');
    }

    // Copy database file with size verification
    final dbFile = File(mainDbPath);
    final dbSize = await dbFile.length();
    myPrint('Database file size: $dbSize bytes');

    try {
      final backupFile = await dbFile.copy(mainBackupPath);
      final backupSize = await backupFile.length();
      myPrint('Backup file created with size: $backupSize bytes');

      if (backupSize != dbSize) {
        myPrint('Warning: backup file size differs from original!');
      }
    } catch (copyError) {
      myPrint('Error copying file: $copyError');
      okInfoBarRed(lw('Error copying database file'));
      return lw('Error copying database file');
    }

    // Verify backup file was created
    bool backupExists = await File(mainBackupPath).exists();
    myPrint('Backup file created: $backupExists');

    if (!backupExists) {
      myPrint('Backup file was not created for some reason');
      okInfoBarRed(lw('Error: backup file was not created'));
      return lw('Error: backup file was not created');
    }

    // Backup settings database
    await _backupSettingsDb(databasesPath, backupDirPath, dateStr);

    // Backup Photo folder
    await _backupPhotoFolder(backupDirPath);

    // Backup Sounds folder
    await _backupSoundsFolder(backupDirPath);

    // List all files in backup directory
    await listBackupFiles();

    myPrint('Backup created successfully at $mainBackupPath');
    okInfoBarGreen('${lw('Backup created successfully')} ${lw('in Documents folder')}');
    return lw('Backup created successfully');
  } catch (e) {
    myPrint('Error creating backup: $e');
    okInfoBarRed(lw('Error creating backup'));
    return lw('Error creating backup');
  }
}

// Recursively copy directory preserving structure
Future<int> _copyDirectoryRecursive(Directory source, Directory target, {bool skipTemp = false}) async {
  myPrint('_copyDirectoryRecursive: ${source.path} -> ${target.path}');
  if (!await source.exists()) {
    myPrint('_copyDirectoryRecursive: source does not exist!');
    return 0;
  }
  if (!await target.exists()) {
    await target.create(recursive: true);
  }
  int copiedFiles = 0;
  final entities = await source.list().toList();
  myPrint('_copyDirectoryRecursive: found ${entities.length} entities in source');
  for (var entity in entities) {
    final name = path.basename(entity.path);
    if (skipTemp && name.startsWith('temp_')) continue;
    final isDir = await FileSystemEntity.isDirectory(entity.path);
    if (isDir) {
      final subTarget = Directory('${target.path}/$name');
      copiedFiles += await _copyDirectoryRecursive(Directory(entity.path), subTarget);
    } else if (await FileSystemEntity.isFile(entity.path)) {
      await File(entity.path).copy('${target.path}/$name');
      copiedFiles++;
    }
  }
  return copiedFiles;
}

// Backup settings database
Future<void> _backupSettingsDb(String databasesPath, String backupDirPath, String dateStr) async {
  try {
    // Flush WAL before copying
    try {
      await settDb.execute("PRAGMA wal_checkpoint(TRUNCATE)");
    } catch (e) {
      myPrint('WAL checkpoint warning for settDb: $e');
    }

    final settDbPath = path.join(databasesPath, settDbFile);
    final settFile = File(settDbPath);

    if (!await settFile.exists()) {
      myPrint('Settings DB not found, skipping');
      return;
    }

    final backupPath = '$backupDirPath/settings-$dateStr.db';
    final backupFile = await settFile.copy(backupPath);
    myPrint('Settings DB backed up: ${await backupFile.length()} bytes');
  } catch (e) {
    myPrint('Error backing up settings DB: $e');
  }
}

// Restore settings database from backup directory
Future<void> _restoreSettingsDb(String backupDirPath) async {
  try {
    // Find settings DB file in backup dir
    final backupDir = Directory(backupDirPath);
    if (!await backupDir.exists()) return;

    final entities = await backupDir.list().toList();
    final settingsFile = entities.whereType<File>().where(
      (f) => path.basename(f.path).startsWith('settings-') && f.path.endsWith('.db')
    ).toList();

    if (settingsFile.isEmpty) {
      myPrint('No settings DB in backup');
      return;
    }

    final databasesPath = await getDatabasesPath();
    final settDbPath = path.join(databasesPath, settDbFile);

    // Close settings DB before overwriting
    await settDb.close();

    try {
      await settingsFile.first.copy(settDbPath);
      myPrint('Settings DB restored from backup');
    } catch (copyError) {
      myPrint('Error copying settings DB: $copyError');
    }

    // Always reopen settings DB (even if copy failed, the old file still exists)
    settDb = await openDatabase(
      settDbPath,
      version: settDbVersion,
      onCreate: (db, version) {
        return db.execute(
          'CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT)',
        );
      },
    );
    myPrint('Settings DB reopened');
  } catch (e) {
    myPrint('Error restoring settings DB: $e');
    // Ensure settDb is reopened even on unexpected errors
    try {
      final databasesPath = await getDatabasesPath();
      final settDbPath = path.join(databasesPath, settDbFile);
      settDb = await openDatabase(settDbPath);
    } catch (e) {
      myPrint('Error reopening settDb in fallback: $e');
    }
  }
}

// Backup Photo folder to backup directory
Future<void> _backupPhotoFolder(String backupDirPath) async {
  try {
    if (photoDirectory == null) {
      await initStoragePaths();
    }
    if (photoDirectory == null || !await photoDirectory!.exists()) {
      myPrint('No Photo folder to backup');
      return;
    }

    myPrint('Photo backup: source=${photoDirectory!.path}');

    final backupPhotoDir = Directory('$backupDirPath/Photo');
    final copiedFiles = await _copyDirectoryRecursive(photoDirectory!, backupPhotoDir, skipTemp: true);

    myPrint('Photo backup: $copiedFiles files copied');
  } catch (e) {
    myPrint('Error backing up Photo folder: $e');
  }
}

// Restore Photo folder from backup directory
Future<void> _restorePhotoFolder(String backupDirPath) async {
  try {
    final backupPhotoDir = Directory('$backupDirPath/Photo');
    if (!await backupPhotoDir.exists()) {
      myPrint('No Photo folder in backup to restore');
      return;
    }

    if (photoDirectory == null) {
      await initStoragePaths();
    }
    if (photoDirectory == null) {
      myPrint('Cannot restore photos: photoDirectory is null');
      return;
    }

    // Ensure target Photo directory exists
    if (!await photoDirectory!.exists()) {
      await photoDirectory!.create(recursive: true);
    }

    // Remove existing item_* folders to avoid duplicates
    final existing = await photoDirectory!.list().toList();
    for (var entity in existing) {
      final name = path.basename(entity.path);
      if (name.startsWith('item_') && await FileSystemEntity.isDirectory(entity.path)) {
        await Directory(entity.path).delete(recursive: true);
      }
    }

    final restoredFiles = await _copyDirectoryRecursive(backupPhotoDir, photoDirectory!);

    myPrint('Restored $restoredFiles photo files');
  } catch (e) {
    myPrint('Error restoring Photo folder: $e');
  }
}

// Backup Sounds folder to backup directory
Future<void> _backupSoundsFolder(String backupDirPath) async {
  try {
    if (soundsDirectory == null) {
      await initStoragePaths();
    }
    if (soundsDirectory == null || !await soundsDirectory!.exists()) {
      myPrint('No Sounds folder to backup');
      return;
    }

    final backupSoundsDir = Directory('$backupDirPath/Sounds');
    if (!await backupSoundsDir.exists()) {
      await backupSoundsDir.create(recursive: true);
    }

    // Copy all sound files
    final entities = await soundsDirectory!.list().toList();
    int copiedFiles = 0;

    for (var entity in entities) {
      if (entity is File && isAudioFile(entity.path)) {
        final fileName = path.basename(entity.path);
        await entity.copy('${backupSoundsDir.path}/$fileName');
        copiedFiles++;
      }
    }

    myPrint('Backed up $copiedFiles sound files');
  } catch (e) {
    myPrint('Error backing up Sounds folder: $e');
  }
}

// Restore Sounds folder from backup directory
Future<void> _restoreSoundsFolder(String backupDirPath) async {
  try {
    final backupSoundsDir = Directory('$backupDirPath/Sounds');
    if (!await backupSoundsDir.exists()) {
      myPrint('No Sounds folder in backup to restore');
      return;
    }

    if (soundsDirectory == null) {
      await initStoragePaths();
    }
    if (soundsDirectory == null) {
      myPrint('Cannot restore sounds: soundsDirectory is null');
      return;
    }

    // Ensure target Sounds directory exists
    if (!await soundsDirectory!.exists()) {
      await soundsDirectory!.create(recursive: true);
    }

    // Copy all sound files from backup
    final entities = await backupSoundsDir.list().toList();
    int restoredFiles = 0;

    for (var entity in entities) {
      if (entity is File && isAudioFile(entity.path)) {
        final fileName = path.basename(entity.path);
        final targetPath = '${soundsDirectory!.path}/$fileName';

        await entity.copy(targetPath);
        restoredFiles++;
      }
    }

    myPrint('Restored $restoredFiles sound files');
  } catch (e) {
    myPrint('Error restoring Sounds folder: $e');
  }
}

// Export data to CSV
Future<String> exportToCSV() async {
  try {
    myPrint('Starting CSV export...');

    final backupDir = await createBackupDirWithDate();
    if (backupDir == null) {
      myPrint('Failed to create export directory');
      okInfoBarRed(lw('Error exporting to CSV'));
      return lw('Error exporting to CSV');
    }

    final List<Map<String, dynamic>> items = await mainDb.query('items');
    if (items.isEmpty) {
      myPrint('No data to export');
      okInfoBarRed(lw('No data to export'));
      return lw('No data to export');
    }

    final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
    final csvFile = File('${backupDir.path}/items-$dateStr.csv');
    final sink = csvFile.openWrite();

    // Column headers
    final headers = items.first.keys.toList();
    sink.writeln(headers.join(','));

    for (var item in items) {
      final values = headers.map((header) {
        var value = item[header];

        // Handle NULL and numeric fields
        if (value == null) {
          return ''; // Empty string for NULL
        }

        // Escape strings: quotes, newlines, carriage returns
        if (value is String) {
          var escaped = value.replaceAll('\\', '\\\\');
          escaped = escaped.replaceAll('\r', '\\r');
          escaped = escaped.replaceAll('\n', '\\n');
          escaped = escaped.replaceAll('"', '""');
          return '"$escaped"';
        }

        // All other types (numbers, bool) - as is
        return value.toString();
      }).toList();

      sink.writeln(values.join(','));
    }

    await sink.flush();
    await sink.close();

    myPrint('CSV export completed successfully at ${csvFile.path}');
    okInfoBarGreen('${lw('CSV export completed successfully')} ${lw('in Documents folder')}');
    return lw('CSV export completed successfully');
  } catch (e) {
    myPrint('Error exporting to CSV: $e');
    okInfoBarRed(lw('Error exporting to CSV'));
    return lw('Error exporting to CSV');
  }
}

// Restore from backup
Future<String> restoreBackup() async {
  try {
    myPrint('Starting restore process...');

    // Check backup directory
    await listBackupFiles();

    // Get directory for backup file selection
    if (documentsDirectory == null) {
      await initStoragePaths();
    }
    final documentsDir = documentsDirectory;
    if (documentsDir == null) {
      myPrint('Failed to get documents directory');
      okInfoBarRed(lw('Error'));
      return lw('Error');
    }

    final memorizerDir = Directory('${documentsDir.path}/Memorizer');
    if (!await memorizerDir.exists()) {
      myPrint('Memorizer directory does not exist');
      okInfoBarRed(lw('No backups found. Create a backup first.'));
      return lw('No backups found. Create a backup first.');
    }

    // Open file picker directly (not directory picker)
    myPrint('Opening file picker...');
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      initialDirectory: memorizerDir.path,
      dialogTitle: lw('Select DB backup file'),
    );

    if (result == null || result.files.isEmpty) {
      myPrint('No file selected or picker cancelled');
      return lw('Cancel');
    }

    final file = result.files.first;
    final filePath = file.path;

    myPrint('Selected file: $filePath');

    if (filePath == null) {
      myPrint('Selected file path is null');
      okInfoBarRed(lw('Error'));
      return lw('Error');
    }

    // Check that selected file has .db extension
    if (!filePath.toLowerCase().endsWith('.db')) {
      myPrint('Selected file is not a database file');
      okInfoBarRed(lw('Error: selected file is not a database'));
      return lw('Error: selected file is not a database');
    }

    // Show data replacement warning
    final shouldRestore = await showCustomDialog(
      title: lw('Warning'),
      content: lw('Restore will replace all current data with backup'),
      actions: [
        {
          'label': lw('Cancel'),
          'value': false,
          'isDestructive': false,
        },
        {
          'label': lw('Restore'),
          'value': true,
          'isDestructive': true,
        },
      ],
    );

    if (shouldRestore != true) {
      myPrint('Restore cancelled by user');
      return lw('Cancel');
    }

    // Close database connection
    myPrint('Closing database connection...');
    await mainDb.close();

    // Get database path
    final databasesPath = await getDatabasesPath();
    final mainDbPath = path.join(databasesPath, mainDbFile);
    myPrint('Target DB path: $mainDbPath');

    // Copy backup file
    myPrint('Copying backup file to database location...');
    try {
      final sourceFile = File(filePath);
      final sourceSize = await sourceFile.length();
      myPrint('Source file size: $sourceSize bytes');

      final targetFile = await sourceFile.copy(mainDbPath);
      final targetSize = await targetFile.length();
      myPrint('Target file size: $targetSize bytes');

      if (sourceSize != targetSize) {
        myPrint('Warning: source and target file sizes differ!');
      }
    } catch (copyError) {
      myPrint('Error copying backup file: $copyError');
      // Reopen mainDb since it was closed before copy attempt
      try {
        mainDb = await openDatabase(mainDbPath);
      } catch (e) {
        myPrint('Error reopening mainDb after copy failure: $e');
      }
      okInfoBarRed(lw('Error copying backup file'));
      return lw('Error copying backup file');
    }

    // Reopen database with version check (triggers migrations for older backups)
    myPrint('Reopening database...');
    try {
      mainDb = await openDatabase(
        mainDbPath,
        version: mainDbVersion,
        onUpgrade: mainDbOnUpgrade,
      );
      // Validate restored database
      final testQuery = await mainDb.rawQuery('SELECT count(*) as cnt FROM items');
      final count = testQuery.first['cnt'] as int? ?? 0;
      myPrint('Database reopened successfully, $count items');
    } catch (openError) {
      myPrint('Error reopening database: $openError');
      // Try to reopen without version check as fallback
      try {
        mainDb = await openDatabase(mainDbPath);
      } catch (e) {
        myPrint('Error reopening mainDb in fallback: $e');
      }
      okInfoBarRed(lw('Error: selected file is not a database'));
      return lw('Error: selected file is not a database');
    }

    // Restore Photo and Sounds folders from backup
    // File picker may return a cached copy, so parent dir might not be the actual backup dir
    final pickedParent = File(filePath).parent.path;
    String backupDirPath = pickedParent;
    myPrint('Picked file parent dir: $pickedParent');

    final hasPhotoInParent = await Directory('$pickedParent/Photo').exists();
    final hasSoundsInParent = await Directory('$pickedParent/Sounds').exists();
    myPrint('Photo in parent: $hasPhotoInParent, Sounds in parent: $hasSoundsInParent');

    if (!hasPhotoInParent && !hasSoundsInParent) {
      // File picker returned a cached copy - find actual backup dir by filename
      final fileName = path.basename(filePath);
      final dateMatch = RegExp(r'memorizer-(\d{8})\.db').firstMatch(fileName);
      if (dateMatch != null) {
        final candidatePath = '${memorizerDir.path}/mem-${dateMatch.group(1)}';
        if (await Directory(candidatePath).exists()) {
          backupDirPath = candidatePath;
          myPrint('Using actual backup dir: $backupDirPath');
        }
      }
    }

    await _restoreSettingsDb(backupDirPath);
    await _restorePhotoFolder(backupDirPath);
    await _restoreSoundsFolder(backupDirPath);

    // Reschedule all reminders after successful restore
    myPrint('Rescheduling reminders after restore...');
    try {
      await SimpleNotifications.rescheduleAllReminders();
      myPrint('Reminders rescheduled successfully');
    } catch (reminderError) {
      myPrint('Error rescheduling reminders: $reminderError');
      // Don't interrupt restore process due to reminder errors
      okInfoBarOrange(lw('Database restored. Please restart the app.'));
    }

    // Return success message with restart recommendation
    myPrint('Database restored successfully');
    okInfoBarGreen(lw('Database restored. Please restart the app.'));
    return lw('Database restored. Please restart the app.');
  } catch (e) {
    myPrint('Error restoring backup: $e');
    // Re-initialize both databases after error
    try {
      final databasesPath = await getDatabasesPath();
      final mainDbPath = path.join(databasesPath, mainDbFile);
      mainDb = await openDatabase(mainDbPath);
      final settDbPath = path.join(databasesPath, settDbFile);
      settDb = await openDatabase(settDbPath);
      myPrint('Databases reopened after error');
    } catch (reInitError) {
      myPrint('Error re-opening databases: $reInitError');
    }
    okInfoBarRed(lw('Error restoring backup'));
    return lw('Error restoring backup');
  }
}

// Restore from CSV file
Future<String> restoreFromCSV() async {
  try {
    myPrint('Starting restore from CSV process...');

    // Get directory for CSV file selection
    if (documentsDirectory == null) {
      await initStoragePaths();
    }
    final documentsDir = documentsDirectory;
    if (documentsDir == null) {
      myPrint('Failed to get documents directory');
      okInfoBarRed(lw('Error'));
      return lw('Error');
    }

    final memorizerDir = Directory('${documentsDir.path}/Memorizer');
    if (!await memorizerDir.exists()) {
      myPrint('Memorizer directory does not exist');
      okInfoBarRed(lw('No backups found. Create a backup first.'));
      return lw('No backups found. Create a backup first.');
    }

    // Select CSV file
    myPrint('Opening file picker...');
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      initialDirectory: memorizerDir.path,
      dialogTitle: lw('Select CSV file to restore'),
    );

    if (result == null || result.files.isEmpty) {
      myPrint('No file selected or picker cancelled');
      return lw('Cancel');
    }

    final file = result.files.first;
    final filePath = file.path;

    myPrint('Selected file: $filePath');

    if (filePath == null) {
      myPrint('Selected file path is null');
      okInfoBarRed(lw('Error'));
      return lw('Error');
    }

    if (!filePath.toLowerCase().endsWith('.csv')) {
      myPrint('Selected file is not a CSV file');
      okInfoBarRed(lw('Error: selected file is not a CSV'));
      return lw('Error: selected file is not a CSV');
    }

    // Confirm restore
    final shouldRestore = await showCustomDialog(
      title: lw('Warning'),
      content: lw('Restore will replace all data in the Items table'),
      actions: [
        {'label': lw('Cancel'), 'value': false, 'isDestructive': false},
        {'label': lw('Restore'), 'value': true, 'isDestructive': true},
      ],
    );

    if (shouldRestore != true) {
      myPrint('Restore cancelled by user');
      return lw('Cancel');
    }

    // Read and process CSV
    myPrint('Reading CSV file...');
    final csvFile = File(filePath);
    final lines = await csvFile.readAsLines();

    if (lines.isEmpty) {
      myPrint('CSV file is empty');
      okInfoBarRed(lw('Error: CSV file is empty'));
      return lw('Error: CSV file is empty');
    }

    // Parse headers
    final headers = _parseCSVLine(lines[0]);
    myPrint('CSV headers: $headers');

    // Restore data
    await mainDb.transaction((txn) async {
      await txn.execute('DELETE FROM items');

      for (int i = 1; i < lines.length; i++) {
        final values = _parseCSVLine(lines[i]);

        if (values.length != headers.length) {
          myPrint('Skipping malformed line: ${lines[i]}');
          continue;
        }

        final Map<String, dynamic> row = {};
        for (int j = 0; j < headers.length; j++) {
          final columnName = headers[j];
          final value = values[j].trim();

          if (value.isEmpty) {
            row[columnName] = null;
          } else {
            switch (columnName) {
              case 'id':
              case 'priority':
              case 'remind':
              case 'created':
              case 'remove':
              case 'hidden':
              case 'yearly':
              case 'monthly':
              case 'daily':
              case 'daily_days':
              case 'fullscreen':
              case 'active':
              case 'period':
              case 'period_days':
              case 'loop_sound':
                row[columnName] = int.tryParse(value) ?? 0;
                break;
              case 'date':
              case 'time':
              case 'period_to':
                row[columnName] = int.tryParse(value); // Can be null
                break;
              default:
                // Unescape newlines and backslashes from CSV export
                var unescaped = value.replaceAll('\\n', '\n');
                unescaped = unescaped.replaceAll('\\r', '\r');
                unescaped = unescaped.replaceAll('\\\\', '\\');
                row[columnName] = unescaped;
            }
          }
        }

        await txn.insert('items', row);
      }
    });

    // Reschedule all reminders after successful CSV restore
    myPrint('Rescheduling reminders after CSV restore...');
    try {
      await SimpleNotifications.rescheduleAllReminders();
      myPrint('Reminders rescheduled successfully after CSV restore');
    } catch (reminderError) {
      myPrint('Error rescheduling reminders after CSV restore: $reminderError');
      // Don't interrupt restore process due to reminder errors
      okInfoBarOrange(lw('Data restored from CSV. Please restart the app.'));
    }

    myPrint('CSV restore completed successfully');
    okInfoBarGreen(lw('Data restored from CSV. Please restart the app.'));
    return lw('Data restored from CSV. Please restart the app.');
  } catch (e) {
    myPrint('Error restoring from CSV: $e');
    okInfoBarRed(lw('Error restoring from CSV'));
    return lw('Error restoring from CSV');
  }
}

// Helper function for parsing CSV lines
List<String> _parseCSVLine(String line) {
  List<String> result = [];
  bool inQuotes = false;
  String currentValue = '';

  for (int i = 0; i < line.length; i++) {
    String char = line[i];

    if (char == '"') {
      // Check for escaped quotes (double quotes)
      if (i + 1 < line.length && line[i + 1] == '"') {
        currentValue += '"';
        i++; // Skip next quote
      } else {
        // Toggle quotes flag
        inQuotes = !inQuotes;
      }
    } else if (char == ',' && !inQuotes) {
      // End of value
      result.add(currentValue);
      currentValue = '';
    } else {
      // Append character to current value
      currentValue += char;
    }
  }

  // Add last value
  result.add(currentValue);

  return result;
}

// List and display backup files
Future<void> listBackupFiles() async {
  try {
    final documentsDir = await getDocumentsDirectory();
    if (documentsDir == null) {
      myPrint('Documents directory not available');
      return;
    }

    final memorizerDir = Directory('${documentsDir.path}/Memorizer');
    if (!await memorizerDir.exists()) {
      myPrint('Memorizer directory does not exist');
      return;
    }

    myPrint('Listing directories in Memorizer directory: ${memorizerDir.path}');

    // Get list of directories in Memorizer
    final entities = await memorizerDir.list().toList();
    final backupDirs = entities.whereType<Directory>().where(
            (dir) => path.basename(dir.path).startsWith('mem-')
    ).toList();

    if (backupDirs.isEmpty) {
      myPrint('No backup directories found');
      return;
    }

    // Sort directories by name (date) in reverse order
    backupDirs.sort((a, b) => path.basename(b.path).compareTo(path.basename(a.path)));

    for (var dir in backupDirs) {
      myPrint('Backup directory: ${dir.path}');

      // Get contents of each directory
      final dirEntities = await dir.list().toList();

      for (var entity in dirEntities) {
        if (entity is File) {
          final size = await entity.length();
          myPrint('File: ${entity.path}, Size: $size bytes');
        } else if (entity is Directory) {
          myPrint('Directory: ${entity.path}');
        }
      }
    }
  } catch (e) {
    myPrint('Error listing backup files: $e');
  }
}