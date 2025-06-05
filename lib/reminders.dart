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

      // Register handler for messages from native code only once
      if (!_methodCallHandlerRegistered) {
        platform.setMethodCallHandler((call) async {
          myPrint('Received method call from native: ${call.method}');

          if (call.method == 'permissionDenied') {
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
      int hour = 8; // Default to 8:00 AM
      int minute = 0;

      if (time != null) {
        // Use specific time from item
        hour = time ~/ 100;
        minute = time % 100;
      }

      // Create notification date/time
      final notificationDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        hour,
        minute,
      );

      myPrint('Notification scheduled for: $notificationDateTime');

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
