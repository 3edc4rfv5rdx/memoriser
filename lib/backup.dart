// backup.dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import 'globals.dart';

// Получение директории загрузок
Future<Directory?> _getDownloadsDirectory() async {
  try {
    if (Platform.isAndroid) {
      // На Android используем внешнее хранилище
      final directory = await getExternalStorageDirectory();
      if (directory != null) {
        final androidPath = directory.path.split('/Android')[0];
        final downloadDir = Directory('$androidPath/Download');
        if (await downloadDir.exists()) {
          return downloadDir;
        }
      }
      return await getApplicationDocumentsDirectory();
    } else if (Platform.isLinux) {
      // На Linux обычно используем ~/Downloads
      final home = Platform.environment['HOME'];
      if (home != null) {
        final downloadDir = Directory('$home/Downloads');
        if (await downloadDir.exists()) {
          return downloadDir;
        }
      }
      return await getApplicationDocumentsDirectory();
    } else {
      // Другие платформы - используем директорию приложения
      return await getApplicationDocumentsDirectory();
    }
  } catch (e) {
    myPrint('Error getting downloads directory: $e');
    return null;
  }
}

// Создание резервной копии базы данных
Future<String> createBackup() async {
  try {
    myPrint('Starting backup process...');

    // Получение директории загрузок
    final downloadsDir = await _getDownloadsDirectory();
    myPrint('Downloads directory: ${downloadsDir?.path}');

    if (downloadsDir == null) {
      myPrint('Failed to get downloads directory');
      return lw('Error creating backup');
    }

    // Создание директории Memorizer
    final backupDir = Directory('${downloadsDir.path}/Memorizer');
    myPrint('Backup directory path: ${backupDir.path}');

    bool dirExists = await backupDir.exists();
    myPrint('Backup directory exists: $dirExists');

    if (!dirExists) {
      try {
        await backupDir.create(recursive: true);
        myPrint('Created backup directory successfully');
      } catch (dirError) {
        myPrint('Error creating backup directory: $dirError');
        return lw('Error creating backup directory');
      }
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

    // Генерация имени файла
    final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
    final mainBackupPath = '${backupDir.path}/memorizer-$dateStr.db';
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

// Восстановление из резервной копии
Future<String> restoreBackup() async {
  try {
    myPrint('Starting restore process...');

    // Проверяем директорию бэкапа
    await listBackupFiles();

    final downloadsDir = await _getDownloadsDirectory();
    if (downloadsDir == null) {
      myPrint('Failed to get downloads directory');
      return lw('Error');
    }

    final backupDir = Directory('${downloadsDir.path}/Memorizer');
    myPrint('Backup directory path: ${backupDir.path}');

    if (!await backupDir.exists()) {
      myPrint('Backup directory does not exist');
      await backupDir.create(recursive: true);
      return lw('No backups found. Create a backup first.');
    }

    // Проверяем наличие .db файлов в директории
    final entities = await backupDir.list().toList();
    final dbFiles = entities.whereType<File>().where((f) => f.path.endsWith('.db')).toList();

    myPrint('Found ${dbFiles.length} database files in backup directory');

    if (dbFiles.isEmpty) {
      myPrint('No database backups found');
      return lw('No database backups found in Memorizer folder.');
    }

    // Выбор файла резервной копии
    myPrint('Opening file picker...');
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
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

// Функция для проверки наличия и отображения файлов бэкапа
Future<void> listBackupFiles() async {
  try {
    final downloadsDir = await _getDownloadsDirectory();
    if (downloadsDir == null) {
      myPrint('Downloads directory not available');
      return;
    }

    final backupDir = Directory('${downloadsDir.path}/Memorizer');
    if (!await backupDir.exists()) {
      myPrint('Backup directory does not exist');
      return;
    }

    myPrint('Listing files in backup directory: ${backupDir.path}');

    // Получаем список файлов
    final entities = await backupDir.list().toList();

    if (entities.isEmpty) {
      myPrint('Backup directory is empty');
      return;
    }

    for (var entity in entities) {
      if (entity is File) {
        final size = await entity.length();
        myPrint('File: ${entity.path}, Size: $size bytes');
      } else if (entity is Directory) {
        myPrint('Directory: ${entity.path}');
      } else {
        myPrint('Unknown entity: ${entity.path}');
      }
    }
  } catch (e) {
    myPrint('Error listing backup files: $e');
  }
}
