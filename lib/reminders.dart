// reminders.dart
import 'package:flutter/services.dart';

import 'globals.dart';

// A simple notification system using direct platform channels
class SimpleNotifications {
  static const platform = MethodChannel('com.example.memorizer/notifications');

  // Initialize the notification system
  static Future<void> initNotifications() async {
    try {
      await platform.invokeMethod('initializeNotifications');
      myPrint('Notification system initialized');

      // Set up method call handler for messages from native code
      platform.setMethodCallHandler((call) async {
        if (call.method == 'checkEvents') {
          await removeExpiredItems(); // First remove expired items
          await checkTodayEvents(); // Then check today's events
        }
      });
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
      // Get reminder time from settings
      final remindTime = await getSetting("Remind time") ?? notifTime;

      await platform.invokeMethod('scheduleDaily', {
        'time': remindTime,
        'title': lw('Reminder Check'),
        'body': lw('Checking for today\'s events'),
      });

      myPrint('Scheduled daily reminder check at $remindTime');

      // Do an immediate check, but with removal first
      await removeExpiredItems(); // New method to handle removals first
      await checkTodayEvents(); // Then check today's events
    } catch (e) {
      myPrint('Failed to schedule reminder: $e');
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
        orderBy: 'date ASC',
      );

      myPrint('Found ${todayEvents.length} events for today');

      // Если нет событий на сегодня, просто выходим
      if (todayEvents.isEmpty) {
        return;
      }

      // Process events - show a notification for each one
      for (var item in todayEvents) {
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
