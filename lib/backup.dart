// backup.dart
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import 'globals.dart';
import 'reminders.dart';

// Создание резервной копии базы данных
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

    // Получение пути к основной базе данных
    final databasesPath = await getDatabasesPath();
    myPrint('Database path: $databasesPath');

    final mainDbPath = path.join(databasesPath, mainDbFile);
    myPrint('Main DB file path: $mainDbPath');

    // Проверка существования файла
    bool dbExists = await File(mainDbPath).exists();
    myPrint('Database file exists: $dbExists');

    if (!dbExists) {
      myPrint('Database file not found');
      okInfoBarRed(lw('Error creating backup: database file not found'));
      return lw('Error creating backup: database file not found');
    }

    // Генерация имени файла с датой
    final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
    final mainBackupPath = '$backupDirPath/memorizer-$dateStr.db';
    myPrint('Target backup file path: $mainBackupPath');

    // Копирование файла с проверкой размера
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

    // Проверка, что файл бэкапа создан
    bool backupExists = await File(mainBackupPath).exists();
    myPrint('Backup file created: $backupExists');

    if (!backupExists) {
      myPrint('Backup file was not created for some reason');
      okInfoBarRed(lw('Error: backup file was not created'));
      return lw('Error: backup file was not created');
    }

    // Backup Photo folder
    await _backupPhotoFolder(backupDirPath);

    // Backup Sounds folder
    await _backupSoundsFolder(backupDirPath);

    // Список всех файлов в директории бэкапа
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
    final name = entity.path.split('/').last;
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
      final name = entity.path.split('/').last;
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
        final fileName = entity.path.split('/').last;
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
      if (entity is File) {
        final fileName = entity.path.split('/').last;
        final targetPath = '${soundsDirectory!.path}/$fileName';

        // Skip if file already exists
        if (!await File(targetPath).exists()) {
          await entity.copy(targetPath);
          restoredFiles++;
        }
      }
    }

    myPrint('Restored $restoredFiles sound files');
  } catch (e) {
    myPrint('Error restoring Sounds folder: $e');
  }
}

// Экспорт данных в CSV
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

    // Заголовки колонок
    final headers = items.first.keys.toList();
    sink.writeln(headers.join(','));

    for (var item in items) {
      final values = headers.map((header) {
        var value = item[header];

        // Обработка NULL и числовых полей
        if (value == null) {
          return ''; // Пустая строка для NULL
        }

        // Для строк - экранирование кавычек
        if (value is String) {
          return '"${value.replaceAll('"', '""')}"';
        }

        // Все остальные типы (числа, bool) - как есть
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

// Восстановление из резервной копии
Future<String> restoreBackup() async {
  try {
    myPrint('Starting restore process...');

    // Проверяем директорию бэкапа
    await listBackupFiles();

    // Получаем директорию для выбора файла бэкапа
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

    // Сразу открываем выбор файла, а не каталога
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

    // Проверяем, что выбранный файл имеет расширение .db
    if (!filePath.toLowerCase().endsWith('.db')) {
      myPrint('Selected file is not a database file');
      okInfoBarRed(lw('Error: selected file is not a database'));
      return lw('Error: selected file is not a database');
    }

    // Показываем предупреждение о замене данных (если не было показано ранее)
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

    // Закрытие соединения с базой данных
    myPrint('Closing database connection...');
    await mainDb.close();

    // Получение пути к базе данных
    final databasesPath = await getDatabasesPath();
    final mainDbPath = path.join(databasesPath, mainDbFile);
    myPrint('Target DB path: $mainDbPath');

    // Копирование файла резервной копии
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
      okInfoBarRed(lw('Error copying backup file'));
      return lw('Error copying backup file');
    }

    // Пытаемся повторно открыть базу данных
    myPrint('Reopening database...');
    try {
      mainDb = await openDatabase(mainDbPath);
      myPrint('Database reopened successfully');
    } catch (openError) {
      myPrint('Error reopening database: $openError');
      okInfoBarRed(lw('Error reopening database'));
      return lw('Error reopening database');
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

    await _restorePhotoFolder(backupDirPath);
    await _restoreSoundsFolder(backupDirPath);

    // НОВОЕ: Перепланируем все напоминания после успешного восстановления
    myPrint('Rescheduling reminders after restore...');
    try {
      await SimpleNotifications.rescheduleAllReminders();
      myPrint('Reminders rescheduled successfully');
    } catch (reminderError) {
      myPrint('Error rescheduling reminders: $reminderError');
      // Не прерываем процесс восстановления из-за ошибки напоминаний
      okInfoBarOrange(lw('Database restored. Please restart the app.'));
    }

    // Если успешно, возвращаем сообщение с рекомендацией перезапустить
    myPrint('Database restored successfully');
    okInfoBarGreen(lw('Database restored. Please restart the app.'));
    return lw('Database restored. Please restart the app.');
  } catch (e) {
    myPrint('Error restoring backup: $e');
    // Повторная инициализация баз данных
    try {
      // Пытаемся повторно открыть базу данных
      final databasesPath = await getDatabasesPath();
      final mainDbPath = path.join(databasesPath, mainDbFile);
      mainDb = await openDatabase(mainDbPath);
      myPrint('Database reopened after error');
    } catch (reInitError) {
      myPrint('Error re-opening database: $reInitError');
    }
    okInfoBarRed(lw('Error restoring backup'));
    return lw('Error restoring backup');
  }
}

// Восстановление из CSV файла
Future<String> restoreFromCSV() async {
  try {
    myPrint('Starting restore from CSV process...');

    // Получаем директорию для выбора файла CSV
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

    // Выбор CSV файла
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

    // Подтверждение восстановления
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

    // Чтение и обработка CSV
    myPrint('Reading CSV file...');
    final csvFile = File(filePath);
    final lines = await csvFile.readAsLines();

    if (lines.isEmpty) {
      myPrint('CSV file is empty');
      okInfoBarRed(lw('Error: CSV file is empty'));
      return lw('Error: CSV file is empty');
    }

    // Парсинг заголовков
    final headers = _parseCSVLine(lines[0]);
    myPrint('CSV headers: $headers');

    // Восстановление данных
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
                row[columnName] = int.tryParse(value) ?? 0;
                break;
              case 'date':
              case 'time':
                row[columnName] = int.tryParse(value); // Может быть null
                break;
              default:
                row[columnName] = value;
            }
          }
        }

        await txn.insert('items', row);
      }
    });

    // НОВОЕ: Перепланируем все напоминания после успешного восстановления CSV
    myPrint('Rescheduling reminders after CSV restore...');
    try {
      await SimpleNotifications.rescheduleAllReminders();
      myPrint('Reminders rescheduled successfully after CSV restore');
    } catch (reminderError) {
      myPrint('Error rescheduling reminders after CSV restore: $reminderError');
      // Не прерываем процесс восстановления из-за ошибки напоминаний
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

// Вспомогательная функция для парсинга строк CSV
List<String> _parseCSVLine(String line) {
  List<String> result = [];
  bool inQuotes = false;
  String currentValue = '';

  for (int i = 0; i < line.length; i++) {
    String char = line[i];

    if (char == '"') {
      // Проверяем на экранированные кавычки (двойные кавычки)
      if (i + 1 < line.length && line[i + 1] == '"') {
        currentValue += '"';
        i++; // Пропускаем следующую кавычку
      } else {
        // Переключаем флаг кавычек
        inQuotes = !inQuotes;
      }
    } else if (char == ',' && !inQuotes) {
      // Конец значения
      result.add(currentValue);
      currentValue = '';
    } else {
      // Добавляем символ к текущему значению
      currentValue += char;
    }
  }

  // Добавляем последнее значение
  result.add(currentValue);

  return result;
}

// Функция для проверки наличия и отображения файлов бэкапа
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

    // Получаем список каталогов в Memorizer
    final entities = await memorizerDir.list().toList();
    final backupDirs = entities.whereType<Directory>().where(
            (dir) => path.basename(dir.path).startsWith('mem-')
    ).toList();

    if (backupDirs.isEmpty) {
      myPrint('No backup directories found');
      return;
    }

    // Сортируем каталоги по имени (по дате) в обратном порядке
    backupDirs.sort((a, b) => path.basename(b.path).compareTo(path.basename(a.path)));

    for (var dir in backupDirs) {
      myPrint('Backup directory: ${dir.path}');

      // Получаем содержимое каждого каталога
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