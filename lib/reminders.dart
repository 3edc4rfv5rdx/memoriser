// reminders.dart
import 'package:flutter/services.dart';

import 'globals.dart';

// A simple notification system using direct platform channels
class SimpleNotifications {
  static const platform = MethodChannel('com.example.memorizer/notifications');
  static bool _methodCallHandlerRegistered = false;

  // Initialize the notification system
  static Future<void> initNotifications() async {
    try {
      await platform.invokeMethod('initializeNotifications');
      myPrint('Notification system initialized');

      // Регистрируем обработчик сообщений из нативного кода только один раз
      if (!_methodCallHandlerRegistered) {
        platform.setMethodCallHandler((call) async {
          myPrint('Received method call from native: ${call.method}');

          if (call.method == 'checkEvents') {
            await removeExpiredItems(); // First remove expired items
            await checkTodayEvents(); // Then check today's events
          } else if (call.method == 'permissionDenied') {
            final permissionType = call.arguments as String? ?? 'unknown';
            myPrint('Permission denied: $permissionType');

            if (permissionType == 'notifications') {
              okInfoBarRed(lw('Notification permission denied. Reminders may not work properly.'));
            }
          }
        });
        _methodCallHandlerRegistered = true;
        myPrint('Method call handler registered');
      }
    } catch (e) {
      myPrint('Failed to initialize notifications: $e');
    }
  }

// Schedule a daily reminder check
  static Future<void> scheduleReminderCheck() async {
    // Check if reminders are enabled
    final enableReminders =
        await getSetting("Enable reminders") ?? defSettings["Enable reminders"];

    if (enableReminders != "true") {
      myPrint('Reminders are disabled, cancelling all scheduled notifications');
      await cancelAllNotifications();
      return;
    }

    try {
      // Получаем текущее значение времени напоминания
      final remindTime = await getSetting("Notification time") ?? notifTime;

      // Проверяем формат времени и корректируем при необходимости
      String validatedTime = remindTime;
      if (!_isValidTimeFormat(remindTime)) {
        validatedTime = notifTime; // Используем значение по умолчанию
        myPrint('Invalid time format: $remindTime, using default: $validatedTime');

        // Сохраняем исправленное значение (только если нужна коррекция)
        await saveSetting("Notification time", validatedTime);
      }

      await platform.invokeMethod('scheduleDaily', {
        'time': validatedTime,
        'title': lw('Memorizer'),
        'body': lw('Checking for today\'s events'),
      });

      myPrint('Scheduled daily reminder check at $validatedTime');
    } catch (e) {
      myPrint('Failed to schedule reminder: $e');
    }
  }

// Метод для проверки формата времени
  static bool _isValidTimeFormat(String time) {
    try {
      final parts = time.split(':');
      if (parts.length != 2) return false;

      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);

      if (hour == null || minute == null) return false;
      if (hour < 0 || hour > 23) return false;
      if (minute < 0 || minute > 59) return false;

      return true;
    } catch (e) {
      return false;
    }
  }


  // New method to handle removal of expired items
  static Future<void> removeExpiredItems() async {
    try {
      // Get today's date in YYYYMMDD format
      final today = dateTimeToYYYYMMDD(DateTime.now());

      // Find items with dates before today that have remove flag set
      final itemsToRemove = await mainDb.query(
        'items',
        where: 'date < ? AND remove = 1',
        whereArgs: [today],
      );

      // Delete these items
      for (var item in itemsToRemove) {
        await mainDb.delete('items', where: 'id = ?', whereArgs: [item['id']]);
        myPrint(
          'Automatically removed past item: ${item['id']} with date ${item['date']}',
        );
      }

      // Log the number of items removed
      if (itemsToRemove.isNotEmpty) {
        myPrint('${itemsToRemove.length} old items automatically removed');
      }
    } catch (e) {
      myPrint('Error removing past items: $e');
    }
  }

  // Show a notification
  static Future<void> showNotification(
      int id,
      String title,
      String body, {
        String? payload,
      }) async {
    try {
      await platform.invokeMethod('showNotification', {
        'id': id,
        'title': title,
        'body': body,
        'payload': payload ?? '',
      });
      myPrint('Showed notification: $title');
    } catch (e) {
      myPrint('Failed to show notification: $e');
    }
  }

  // Cancel all notifications
  static Future<void> cancelAllNotifications() async {
    try {
      await platform.invokeMethod('cancelAllNotifications');
      myPrint('All notifications cancelled');
    } catch (e) {
      myPrint('Failed to cancel notifications: $e');
    }
  }

  // Check for today's events and show notifications
  static Future<void> checkTodayEvents() async {
    // Check if reminders are enabled
    final enableReminders =
        await getSetting("Enable reminders") ?? defSettings["Enable reminders"];

    if (enableReminders != "true") {
      myPrint("Reminders are disabled, skipping today's events check");
      return;
    }

    myPrint('Check events for today...');

    try {
      // Get today's date in YYYYMMDD format
      final now = DateTime.now();
      final todayDate = dateTimeToYYYYMMDD(now);

      // Query the database for today's events with reminders enabled
      final todayEvents = await mainDb.query(
        'items',
        where: 'remind = 1 AND date = ?',
        whereArgs: [todayDate],
        orderBy: 'priority DESC', // Сначала показываем события с высоким приоритетом
      );

      myPrint('Found ${todayEvents.length} events for today');

      // Если нет событий на сегодня, просто выходим
      if (todayEvents.isEmpty) {
        return;
      }

      // Process events - show a notification for each one
      for (var item in todayEvents) {
        // Skip hidden items if not in hidden mode
        if ((item['hidden'] as int? ?? 0) == 1 && !xvHiddenMode) {
          continue;
        }

        // If in hidden mode, process the record for display
        final processedItem =
        xvHiddenMode && (item['hidden'] as int? ?? 0) == 1
            ? processItemForView(item)
            : item;

        // Show notification for this event with correct type casting
        await showNotification(
          item['id'] as int,
          lw('Memorizer') + ': ' + (processedItem['title'] as String? ?? ''),
          processedItem['content'] as String? ?? '',
          payload: (item['id'] as int).toString(),
        );
      }

      // Show a summary notification if there are multiple events
      if (todayEvents.length > 1) {
        await showNotification(
          999999,
          lw("Today's events"),
          lw("You have scheduled events for today") + ': ${todayEvents.length}',
        );
      }
    } catch (e) {
      myPrint('Error checking events for today: $e');
    }
  }


  // Function for manual reminder check (called from UI)
  static Future<void> manualCheckReminders() async {
    // Check if reminders are enabled
    final enableReminders =
        await getSetting("Enable reminders") ?? defSettings["Enable reminders"];

    if (enableReminders == "true") {
      // FIRST handle removal of items marked for deletion
      try {
        // Get today's date in YYYYMMDD format
        final today = dateTimeToYYYYMMDD(DateTime.now());

        // Find items with dates before today that have remove flag set
        final itemsToRemove = await mainDb.query(
          'items',
          where: 'date < ? AND remove = 1',
          whereArgs: [today],
        );

        // Delete these items
        for (var item in itemsToRemove) {
          await mainDb.delete(
            'items',
            where: 'id = ?',
            whereArgs: [item['id']],
          );
          myPrint(
            'Manually removed past item: ${item['id']} with date ${item['date']}',
          );
        }

        // Show notification if items were removed
        if (itemsToRemove.isNotEmpty) {
          okInfoBarBlue('${itemsToRemove.length} ${lw('old items removed')}');
        }
      } catch (e) {
        myPrint('Error removing past items: $e');
      }

      // THEN check for today's events
      await checkTodayEvents();
    } else {
      // If reminders are disabled, show a message
      okInfoBarOrange(lw('Reminders are disabled in settings'));
    }
  }
}
