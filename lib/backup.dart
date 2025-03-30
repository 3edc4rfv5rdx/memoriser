// backup.dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import 'globals.dart';

// Получение директории документов
Future<Directory?> _getDocumentsDirectory() async {
  try {
    if (Platform.isAndroid) {
      // На Android используем внешнее хранилище
      final directory = await getExternalStorageDirectory();
      if (directory != null) {
        final androidPath = directory.path.split('/Android')[0];
        final documentsDir = Directory('$androidPath/Documents');
        // Создаем директорию, если она не существует
        if (!await documentsDir.exists()) {
          await documentsDir.create(recursive: true);
        }
        return documentsDir;
      }
      return await getApplicationDocumentsDirectory();
    } else if (Platform.isLinux) {
      // На Linux обычно используем ~/Documents
      final home = Platform.environment['HOME'];
      if (home != null) {
        final documentsDir = Directory('$home/Documents');
        if (await documentsDir.exists()) {
          return documentsDir;
        }
        // Если директория не существует, создаем ее
        try {
          await documentsDir.create(recursive: true);
          return documentsDir;
        } catch (e) {
          myPrint('Error creating Documents directory: $e');
        }
      }
      return await getApplicationDocumentsDirectory();
    } else {
      // Другие платформы - используем директорию приложения
      return await getApplicationDocumentsDirectory();
    }
  } catch (e) {
    myPrint('Error getting documents directory: $e');
    return null;
  }
}

// Создание каталога для резервной копии с указанием даты
Future<String?> _createBackupDirWithDate() async {
  try {
    // Получение директории документов
    final documentsDir = await _getDocumentsDirectory();
    if (documentsDir == null) {
      myPrint('Failed to get documents directory');
      return null;
    }

    // Создание базовой директории Memorizer
    final memorizerDir = Directory('${documentsDir.path}/Memorizer');
    if (!await memorizerDir.exists()) {
      await memorizerDir.create(recursive: true);
    }

    // Генерация имени подкаталога с датой
    final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
    final backupDirPath = '${memorizerDir.path}/bak-$dateStr';

    // Создание подкаталога с датой
    final backupDir = Directory(backupDirPath);
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    return backupDirPath;
  } catch (e) {
    myPrint('Error creating backup directory with date: $e');
    return null;
  }
}

// Создание резервной копии базы данных
Future<String> createBackup() async {
  try {
    myPrint('Starting backup process...');

    // Создание каталога с датой для резервной копии
    final backupDirPath = await _createBackupDirWithDate();
    myPrint('Backup directory path: $backupDirPath');

    if (backupDirPath == null) {
      myPrint('Failed to create backup directory');
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
      return lw('Error copying database file');
    }

    // Проверка, что файл бэкапа создан
    bool backupExists = await File(mainBackupPath).exists();
    myPrint('Backup file created: $backupExists');

    if (!backupExists) {
      myPrint('Backup file was not created for some reason');
      return lw('Error: backup file was not created');
    }

    // Список всех файлов в директории бэкапа
    await listBackupFiles();

    myPrint('Backup created successfully at $mainBackupPath');
    return lw('Backup created successfully');
  } catch (e) {
    myPrint('Error creating backup: $e');
    return lw('Error creating backup');
  }
}

// Экспорт данных в CSV
Future<String> exportToCSV() async {
  try {
    myPrint('Starting CSV export...');

    // Создание каталога с датой для экспорта
    final backupDirPath = await _createBackupDirWithDate();

    if (backupDirPath == null) {
      myPrint('Failed to create export directory');
      return lw('Error exporting to CSV');
    }

    // Получаем все записи из таблицы items
    final List<Map<String, dynamic>> items = await mainDb.query('items');

    if (items.isEmpty) {
      myPrint('No data to export');
      return lw('No data to export');
    }

    // Создаем CSV файл
    final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
    final csvFile = File('$backupDirPath/items-$dateStr.csv');
    final sink = csvFile.openWrite();

    // Записываем заголовки колонок
    final headers = items.first.keys.toList();
    sink.writeln(headers.join(','));

    // Записываем данные
    for (var item in items) {
      final values = headers.map((header) {
        var value = item[header];
        // Обработка специальных символов в CSV
        if (value is String) {
          // Экранирование кавычек и добавление кавычек вокруг строки
          value = '"${value.replaceAll('"', '""')}"';
        } else if (value == null) {
          value = '""';
        }
        return value;
      }).toList();

      sink.writeln(values.join(','));
    }

    await sink.flush();
    await sink.close();

    myPrint('CSV export completed successfully at ${csvFile.path}');
    return lw('CSV export completed successfully');
  } catch (e) {
    myPrint('Error exporting to CSV: $e');
    return lw('Error exporting to CSV');
  }
}

// Обновленные функции восстановления с улучшенной фильтрацией по расширению
// Восстановление из резервной копии
Future<String> restoreBackup() async {
  try {
    myPrint('Starting restore process...');

    // Проверяем директорию бэкапа
    await listBackupFiles();

    // Получаем директорию для выбора файла бэкапа
    final documentsDir = await _getDocumentsDirectory();
    if (documentsDir == null) {
      myPrint('Failed to get documents directory');
      return lw('Error');
    }

    final memorizerDir = Directory('${documentsDir.path}/Memorizer');
    if (!await memorizerDir.exists()) {
      myPrint('Memorizer directory does not exist');
      await memorizerDir.create(recursive: true);
      return lw('No backups found. Create a backup first.');
    }

    // Сразу открываем выбор файла, а не каталога
    myPrint('Opening file picker...');
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db'],
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
      return lw('Error');
    }

    // Проверяем, что выбранный файл имеет расширение .db
    if (!filePath.toLowerCase().endsWith('.db')) {
      myPrint('Selected file is not a database file');
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
      return lw('Error copying backup file');
    }

    // Пытаемся повторно открыть базу данных
    myPrint('Reopening database...');
    try {
      mainDb = await openDatabase(mainDbPath);
      myPrint('Database reopened successfully');
    } catch (openError) {
      myPrint('Error reopening database: $openError');
      return lw('Error reopening database');
    }

    // Если успешно, возвращаем сообщение с рекомендацией перезапустить
    myPrint('Database restored successfully');
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
    return lw('Error restoring backup');
  }
}

// Восстановление из CSV файла
Future<String> restoreFromCSV() async {
  try {
    myPrint('Starting restore from CSV process...');

    // Получаем директорию для выбора файла CSV
    final documentsDir = await _getDocumentsDirectory();
    if (documentsDir == null) {
      myPrint('Failed to get documents directory');
      return lw('Error');
    }

    final memorizerDir = Directory('${documentsDir.path}/Memorizer');
    if (!await memorizerDir.exists()) {
      myPrint('Memorizer directory does not exist');
      return lw('No backups found. Create a backup first.');
    }

    // Сразу открываем выбор файла CSV, а не каталога
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
      return lw('Error');
    }

    // Проверяем, что выбранный файл имеет расширение .csv
    if (!filePath.toLowerCase().endsWith('.csv')) {
      myPrint('Selected file is not a CSV file');
      return lw('Error: selected file is not a CSV');
    }

    // Показываем предупреждение о замене данных
    final shouldRestore = await showCustomDialog(
      title: lw('Warning'),
      content: lw('Restore will replace all data in the Items table'),
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

    // Читаем CSV файл
    myPrint('Reading CSV file...');
    final csvFile = File(filePath);
    final lines = await csvFile.readAsLines();

    if (lines.isEmpty) {
      myPrint('CSV file is empty');
      return lw('Error: CSV file is empty');
    }

    // Парсим заголовки
    final headers = _parseCSVLine(lines[0]);
    myPrint('CSV headers: $headers');

    // Начинаем транзакцию для восстановления данных
    await mainDb.transaction((txn) async {
      // Очищаем таблицу items
      await txn.execute('DELETE FROM items');

      // Вставляем данные из CSV
      for (int i = 1; i < lines.length; i++) {
        final values = _parseCSVLine(lines[i]);

        if (values.length != headers.length) {
          myPrint('Skipping malformed line: ${lines[i]}');
          continue;
        }

        final Map<String, dynamic> row = {};
        for (int j = 0; j < headers.length; j++) {
          // Преобразуем строковые значения в соответствующие типы
          var value = values[j];

          // Определяем тип данных на основе имени столбца или проверки значения
          if (value.isEmpty) {
            row[headers[j]] = null;
          } else if (headers[j] == 'id' || headers[j] == 'hidden') {
            row[headers[j]] = int.tryParse(value) ?? 0;
          } else {
            row[headers[j]] = value;
          }
        }

        await txn.insert('items', row);
      }
    });

    myPrint('CSV restore completed successfully');
    return lw('Data restored from CSV. Please restart the app.');
  } catch (e) {
    myPrint('Error restoring from CSV: $e');
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
    final documentsDir = await _getDocumentsDirectory();
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
            (dir) => path.basename(dir.path).startsWith('bak-')
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