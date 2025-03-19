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
          await checkTodayEvents();
        }
      });
    } catch (e) {
      myPrint('Failed to initialize notifications: $e');
    }
  }

  // Schedule a daily reminder check
  static Future<void> scheduleReminderCheck() async {
    // Check if reminders are enabled
    final enableReminders = await getSetting("Enable reminders") ?? defSettings["Enable reminders"];

    if (enableReminders != "true") {
      myPrint('Reminders are disabled, cancelling all scheduled notifications');
      await cancelAllNotifications();
      return;
    }

    try {
      // Get reminder time from settings
      final remindTime = await getSetting("Remind time") ?? "08:00";

      await platform.invokeMethod('scheduleDaily', {
        'time': remindTime,
        'title': lw('Reminder Check'),
        'body': lw('Checking for today\'s events')
      });

      myPrint('Scheduled daily reminder check at $remindTime');

      // Do an immediate check
      await checkTodayEvents();
    } catch (e) {
      myPrint('Failed to schedule reminder: $e');
    }
  }

  // Show a notification
  static Future<void> showNotification(int id, String title, String body, {String? payload}) async {
    try {
      await platform.invokeMethod('showNotification', {
        'id': id,
        'title': title,
        'body': body,
        'payload': payload ?? ''
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
    final enableReminders = await getSetting("Enable reminders") ?? defSettings["Enable reminders"];

    if (enableReminders != "true") {
      myPrint("Reminders are disabled, skipping today's events check");
      return;
    }

    myPrint('Check events for today...');

    try {
      // Get timestamps for start and end of today
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59).millisecondsSinceEpoch;

      // Query the database for today's events with reminders enabled
      final todayEvents = await mainDb.query(
          'items',
          where: 'remind = 1 AND date >= ? AND date <= ?',
          whereArgs: [startOfDay, endOfDay],
          orderBy: 'date ASC'
      );

      myPrint('Found ${todayEvents.length} events for today');

      if (todayEvents.isEmpty) {
        // If no events, show a message in the app
        if (scaffoldMessengerKey.currentState != null) {
          okInfoBarBlue(lw('No scheduled events for today'));
        }
        return;
      }

      // Process events - show a notification for each one
      for (var item in todayEvents) {
        // If in hidden mode, process the record for display
        final processedItem = xvHiddenMode && (item['hidden'] as int? ?? 0) == 1
            ? processItemForView(item)
            : item;

        // Show notification for this event with correct type casting
        await showNotification(
            item['id'] as int,
            lw('Reminder') + ': ' + (processedItem['title'] as String? ?? ''),
            processedItem['content'] as String? ?? '',
            payload: (item['id'] as int).toString()
        );
      }

      // Show a summary notification if there are multiple events
      if (todayEvents.length > 1) {
        await showNotification(
            999999,
            lw("Today's events"),
            lw("You have scheduled events for today") + ': ${todayEvents.length}'
        );
      }

    } catch (e) {
      myPrint('Error checking events for today: $e');
    }
  }

  // Function for manual reminder check (called from UI)
  static Future<void> manualCheckReminders() async {
    // Check if reminders are enabled
    final enableReminders = await getSetting("Enable reminders") ?? defSettings["Enable reminders"];

    if (enableReminders == "true") {
      await checkTodayEvents();
    } else {
      // If reminders are disabled, show a message
      okInfoBarOrange(lw('Reminders are disabled in settings'));
    }
  }
}