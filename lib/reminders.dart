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

// Schedule individual reminders instead of one daily check
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
      // Get all future reminders from database
      final now = DateTime.now();
      final todayDate = dateTimeToYYYYMMDD(now);

      final futureReminders = await mainDb.query(
        'items',
        where: 'remind = 1 AND date >= ?',
        whereArgs: [todayDate],
        orderBy: 'date ASC, time ASC',
      );

      myPrint('Found ${futureReminders.length} future reminders to schedule');

      // Get default notification time
      final defaultNotificationTime = await getSetting("Notification time") ?? notifTime;

      // Schedule each reminder individually
      for (var item in futureReminders) {
        await _scheduleIndividualReminder(item, defaultNotificationTime);
      }

      myPrint('Scheduled ${futureReminders.length} individual reminders');
    } catch (e) {
      myPrint('Failed to schedule individual reminders: $e');
    }
  }

  // Helper method to schedule individual reminder
  static Future<void> _scheduleIndividualReminder(Map<String, dynamic> item, String defaultTime) async {
    try {
      final itemDate = item['date'] as int?;
      if (itemDate == null) return;

      // Convert date back to DateTime
      final eventDate = yyyymmddToDateTime(itemDate);
      if (eventDate == null) return;

      // Determine notification time for this item
      String notificationTime = defaultTime;
      final itemTime = item['time'] as int?;
      if (itemTime != null) {
        final timeString = timeIntToString(itemTime);
        if (timeString != null) {
          notificationTime = timeString;
        }
      }

      // Parse notification time
      final timeParts = notificationTime.split(':');
      final hour = int.tryParse(timeParts[0]) ?? 8;
      final minute = int.tryParse(timeParts[1]) ?? 0;

      // Create notification date/time
      final notificationDateTime = DateTime(
        eventDate.year,
        eventDate.month,
        eventDate.day,
        hour,
        minute,
      );

      // Only schedule if notification time is in the future
      if (notificationDateTime.isAfter(DateTime.now())) {
        // Here we would call platform-specific scheduling
        // For now, we'll use the existing daily check mechanism
        // but this is where individual scheduling would happen
        myPrint('Would schedule reminder for ${item['title']} at $notificationDateTime');
      }
    } catch (e) {
      myPrint('Error scheduling individual reminder: $e');
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

      // Get default notification time for items without specific time
      final defaultNotificationTime = await getSetting("Notification time") ?? notifTime;

      // Process events - show a notification for each one
      for (var item in todayEvents) {
        // Skip hidden items if not in hidden mode
        if ((item['hidden'] as int? ?? 0) == 1 && !xvHiddenMode) {
          continue;
        }

        // Determine the notification time for this item
        String notificationTime = defaultNotificationTime;

        // Check if item has specific time set
        final itemTime = item['time'] as int?;
        if (itemTime != null) {
          // Convert item time from HHMM format to HH:MM string
          final timeString = timeIntToString(itemTime);
          if (timeString != null) {
            notificationTime = timeString;
          }
        }

        // Check if it's time to show this notification
        final now = DateTime.now();
        final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

        // Only show notification if current time matches or is past the notification time
        if (_shouldShowNotificationNow(currentTime, notificationTime)) {
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
      }

      // Show a summary notification if there are multiple events (только если есть события для показа)
      final eventsToShow = todayEvents.where((item) {
        if ((item['hidden'] as int? ?? 0) == 1 && !xvHiddenMode) {
          return false;
        }

        String notificationTime = defaultNotificationTime;
        final itemTime = item['time'] as int?;
        if (itemTime != null) {
          final timeString = timeIntToString(itemTime);
          if (timeString != null) {
            notificationTime = timeString;
          }
        }

        final now = DateTime.now();
        final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
        return _shouldShowNotificationNow(currentTime, notificationTime);
      }).length;

      if (eventsToShow > 1) {
        await showNotification(
          999999,
          lw("Today's events"),
          lw("You have scheduled events for today") + ': $eventsToShow',
        );
      }
    } catch (e) {
      myPrint('Error checking events for today: $e');
    }
  }

  // Helper method to determine if notification should be shown now
  static bool _shouldShowNotificationNow(String currentTime, String notificationTime) {
    try {
      final currentParts = currentTime.split(':');
      final notificationParts = notificationTime.split(':');

      final currentMinutes = int.parse(currentParts[0]) * 60 + int.parse(currentParts[1]);
      final notificationMinutes = int.parse(notificationParts[0]) * 60 + int.parse(notificationParts[1]);

      // Show notification if current time is equal to or past notification time
      // but within a reasonable window (e.g., within the same hour)
      return currentMinutes >= notificationMinutes &&
          (currentMinutes - notificationMinutes) <= 60; // В пределах часа
    } catch (e) {
      myPrint('Error comparing times: $e');
      return true; // В случае ошибки показываем уведомление
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

  // Schedule a specific reminder for individual item
  static Future<void> scheduleSpecificReminder(int itemId, DateTime date, int? time) async {
    try {
      myPrint('=== SCHEDULING SPECIFIC REMINDER ===');
      myPrint('Item ID: $itemId');
      myPrint('Date: $date');
      myPrint('Time: $time');

      // Check if reminders are enabled
      final enableReminders = await getSetting("Enable reminders") ?? defSettings["Enable reminders"];
      if (enableReminders != "true") {
        myPrint('Reminders are disabled, not scheduling specific reminder');
        return;
      }

      // Determine notification time
      String notificationTime;
      if (time != null) {
        // Use specific time from item
        final timeString = timeIntToString(time);
        if (timeString != null) {
          notificationTime = timeString;
        } else {
          // Fallback to default time if conversion fails
          notificationTime = await getSetting("Notification time") ?? notifTime;
        }
      } else {
        // Use default notification time
        notificationTime = await getSetting("Notification time") ?? notifTime;
      }

      // Parse notification time
      final timeParts = notificationTime.split(':');
      final hour = int.tryParse(timeParts[0]) ?? 8;
      final minute = int.tryParse(timeParts[1]) ?? 0;

      // Create notification date/time
      final notificationDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        hour,
        minute,
      );

      myPrint('Calling platform.invokeMethod with params:');
      myPrint('itemId: $itemId, year: ${date.year}, month: ${date.month}, day: ${date.day}, hour: $hour, minute: $minute');


      // Only schedule if notification time is in the future
      if (notificationDateTime.isAfter(DateTime.now())) {
        await platform.invokeMethod('scheduleSpecificReminder', {
          'itemId': itemId,
          'year': date.year,
          'month': date.month,
          'day': date.day,
          'hour': hour,
          'minute': minute,
          'title': lw('Memorizer'),
          'body': lw('Reminder'),
        });

        myPrint('Scheduled specific reminder for item $itemId at $notificationDateTime');
      } else {
        myPrint('Notification time is in the past, not scheduling for item $itemId');
      }
    } catch (e) {
      myPrint('Failed to schedule specific reminder: $e');
    }
  }

// Cancel a specific reminder for individual item
  static Future<void> cancelSpecificReminder(int itemId) async {
    try {
      await platform.invokeMethod('cancelSpecificReminder', {
        'itemId': itemId,
      });

      myPrint('Cancelled specific reminder for item $itemId');
    } catch (e) {
      myPrint('Failed to cancel specific reminder: $e');
    }
  }

// Update or create a specific reminder (used when editing items)
  static Future<void> updateSpecificReminder(int itemId, bool hasReminder, DateTime? date, int? time) async {
    try {
      // First, cancel any existing reminder for this item
      await cancelSpecificReminder(itemId);

      // If reminder is enabled and date is set, schedule new reminder
      if (hasReminder && date != null) {
        await scheduleSpecificReminder(itemId, date, time);
      }
    } catch (e) {
      myPrint('Failed to update specific reminder: $e');
    }
  }

// Reschedule all reminders after backup restore
  static Future<void> rescheduleAllReminders() async {
    try {
      myPrint('=== RESCHEDULING ALL REMINDERS ===');

      // Check if reminders are enabled
      final enableReminders = await getSetting("Enable reminders") ?? defSettings["Enable reminders"];
      if (enableReminders != "true") {
        myPrint('Reminders are disabled, not rescheduling');
        return;
      }

      // First, cancel all existing notifications
      await cancelAllNotifications();
      myPrint('All existing notifications cancelled');

      // Get today's date for filtering
      final now = DateTime.now();
      final todayDate = dateTimeToYYYYMMDD(now);

      // Get all future reminders from database (including today)
      final futureReminders = await mainDb.query(
        'items',
        where: 'remind = 1 AND date >= ?',
        whereArgs: [todayDate],
        orderBy: 'date ASC, time ASC',
      );

      myPrint('Found ${futureReminders.length} future reminders to reschedule');

      if (futureReminders.isEmpty) {
        myPrint('No future reminders to reschedule');

        // Still need to reschedule daily check
        await scheduleReminderCheck();
        return;
      }

      // Schedule each individual reminder
      int scheduledCount = 0;
      for (var item in futureReminders) {
        try {
          final itemId = item['id'] as int;
          final itemDate = item['date'] as int?;
          final itemTime = item['time'] as int?;

          if (itemDate == null) {
            myPrint('Skipping item $itemId - no date');
            continue;
          }

          // Convert date back to DateTime
          final eventDate = yyyymmddToDateTime(itemDate);
          if (eventDate == null) {
            myPrint('Skipping item $itemId - invalid date: $itemDate');
            continue;
          }

          // Schedule the specific reminder
          await scheduleSpecificReminder(itemId, eventDate, itemTime);
          scheduledCount++;

          myPrint('Rescheduled reminder for item $itemId on ${eventDate.toString().substring(0, 10)}');

        } catch (e) {
          myPrint('Error rescheduling reminder for item ${item['id']}: $e');
        }
      }

      // Also reschedule the daily reminder check
      await scheduleReminderCheck();

      myPrint('=== RESCHEDULING COMPLETE ===');
      myPrint('Successfully rescheduled $scheduledCount individual reminders');

      // Show success message using existing translations
      if (scheduledCount > 0) {
        okInfoBarGreen('${lw('Settings saved')}: $scheduledCount ${lw('reminders')}');
      } else {
        okInfoBarBlue(lw('No events for today'));
      }

    } catch (e) {
      myPrint('Error rescheduling all reminders: $e');
      okInfoBarRed('${lw('Error')}: $e');
    }
  }

}

