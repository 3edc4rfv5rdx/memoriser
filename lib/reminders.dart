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
      int hour = 9; // Default to 9:30 AM
      int minute = 30;

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

      // Reschedule period reminders
      int periodScheduledCount = 0;
      final periodReminders = await mainDb.query(
        'items',
        where: 'period = 1 AND active = 1',
      );

      myPrint('Found ${periodReminders.length} period reminders to reschedule');

      for (var item in periodReminders) {
        try {
          final itemId = item['id'] as int;
          final dateFrom = item['date'] as int?;
          final dateTo = item['period_to'] as int?;
          final itemTime = item['time'] as int?;
          final periodDays = item['period_days'] as int? ?? 127;
          final title = item['title'] as String? ?? '';

          if (dateFrom == null || dateTo == null) continue;

          await schedulePeriodReminders(itemId, dateFrom, dateTo, itemTime, periodDays, title);
          periodScheduledCount++;
        } catch (e) {
          myPrint('Error rescheduling period reminder for item ${item['id']}: $e');
        }
      }
      myPrint('Successfully rescheduled $periodScheduledCount period reminders');

      // Check if daily reminders are enabled
      final enableDailyReminders = await getSetting("Enable daily reminders") ?? defSettings["Enable daily reminders"];

      int dailyScheduledCount = 0;
      if (enableDailyReminders == "true") {
        // Also reschedule all daily reminders
        final dailyReminders = await mainDb.query(
        'items',
        where: 'daily = 1 AND active = 1',
      );

        myPrint('Found ${dailyReminders.length} daily reminders to reschedule');

        for (var item in dailyReminders) {
          try {
            final itemId = item['id'] as int;
            final title = item['title'] as String? ?? '';
            final dailyTimesStr = item['daily_times'] as String?;
            final dailyDays = item['daily_days'] as int? ?? 127;

            if (dailyTimesStr == null || dailyTimesStr.isEmpty) {
              myPrint('Skipping daily item $itemId - no times');
              continue;
            }

            final dailyTimes = parseDailyTimes(dailyTimesStr);
            if (dailyTimes.isEmpty) {
              myPrint('Skipping daily item $itemId - empty times');
              continue;
            }

            // Schedule all times for this daily reminder
            await scheduleAllDailyReminders(itemId, dailyTimes, dailyDays, title);
            dailyScheduledCount++;

          } catch (e) {
            myPrint('Error rescheduling daily reminder for item ${item['id']}: $e');
          }
        }

        myPrint('Successfully rescheduled $dailyScheduledCount daily reminders');
      } else {
        myPrint('Daily reminders are disabled, not rescheduling daily reminders');
      }

      // Show success message using existing translations
      if (scheduledCount > 0 || dailyScheduledCount > 0) {
        okInfoBarGreen('${lw('Settings saved')}: $scheduledCount ${lw('reminders')}, $dailyScheduledCount daily');
      } else {
        okInfoBarBlue(lw('No events for today'));
      }

    } catch (e) {
      myPrint('Error rescheduling all reminders: $e');
      okInfoBarRed('${lw('Error')}: $e');
    }
  }

  // Schedule a daily reminder
  static Future<void> scheduleDailyReminder(
    int itemId,
    String time,
    int daysMask,
    String title,
    String body,
  ) async {
    try {
      myPrint('=== SCHEDULING DAILY REMINDER ===');
      myPrint('Item ID: $itemId');
      myPrint('Time: $time');
      myPrint('Days mask: $daysMask');

      // Check if daily reminders are enabled
      final enableDailyReminders = await getSetting("Enable daily reminders") ?? defSettings["Enable daily reminders"];
      if (enableDailyReminders != "true") {
        myPrint('Daily reminders are disabled, not scheduling');
        return;
      }

      // Parse time string (HH:MM)
      final parts = time.split(':');
      if (parts.length != 2) {
        myPrint('Invalid time format: $time');
        return;
      }

      final hour = int.tryParse(parts[0]) ?? 0;
      final minute = int.tryParse(parts[1]) ?? 0;

      await platform.invokeMethod('scheduleDailyReminder', {
        'itemId': itemId,
        'hour': hour,
        'minute': minute,
        'daysMask': daysMask,
        'title': title,
        'body': body,
      });

      myPrint('Daily reminder scheduled for item $itemId at $hour:$minute');
    } catch (e) {
      myPrint('Failed to schedule daily reminder: $e');
    }
  }

  // Cancel a specific daily reminder
  static Future<void> cancelDailyReminder(int itemId, String time) async {
    try {
      final parts = time.split(':');
      if (parts.length != 2) return;

      final hour = int.tryParse(parts[0]) ?? 0;
      final minute = int.tryParse(parts[1]) ?? 0;

      await platform.invokeMethod('cancelDailyReminder', {
        'itemId': itemId,
        'hour': hour,
        'minute': minute,
      });
      myPrint('Daily reminder cancelled for item $itemId at $time');
    } catch (e) {
      myPrint('Failed to cancel daily reminder: $e');
    }
  }

  // Cancel all daily reminders for an item
  static Future<void> cancelAllDailyReminders(int itemId) async {
    try {
      await platform.invokeMethod('cancelAllDailyReminders', {
        'itemId': itemId,
      });
      myPrint('All daily reminders cancelled for item $itemId');
    } catch (e) {
      myPrint('Failed to cancel all daily reminders: $e');
    }
  }

  // Schedule all daily reminders for an item
  static Future<void> scheduleAllDailyReminders(
    int itemId,
    List<String> times,
    int daysMask,
    String title,
  ) async {
    try {
      for (var time in times) {
        await scheduleDailyReminder(itemId, time, daysMask, title, '');
      }
      myPrint('Scheduled ${times.length} daily reminders for item $itemId');
    } catch (e) {
      myPrint('Error scheduling all daily reminders: $e');
    }
  }

  // Update daily reminders for an item (cancel old, schedule new)
  static Future<void> updateDailyReminders(
    int itemId,
    bool enabled,
    List<String> times,
    int daysMask,
    String title,
  ) async {
    try {
      // First cancel all existing daily reminders for this item
      await cancelAllDailyReminders(itemId);

      // If enabled, schedule new ones
      if (enabled && times.isNotEmpty && daysMask > 0) {
        await scheduleAllDailyReminders(itemId, times, daysMask, title);
      }
    } catch (e) {
      myPrint('Error updating daily reminders: $e');
    }
  }

  // Schedule all period reminders for an item
  static Future<void> schedulePeriodReminders(
    int itemId,
    int dateFrom,
    int dateTo,
    int? time,
    int daysMask,
    String title,
  ) async {
    try {
      myPrint('=== SCHEDULING PERIOD REMINDERS ===');
      myPrint('Item ID: $itemId, from: $dateFrom, to: $dateTo, time: $time, daysMask: $daysMask');

      final enableReminders = await getSetting("Enable reminders") ?? defSettings["Enable reminders"];
      if (enableReminders != "true") {
        myPrint('Reminders are disabled, not scheduling period');
        return;
      }

      int hour = 9, minute = 30;
      if (time != null) {
        hour = time ~/ 100;
        minute = time % 100;
      }

      final isMonthly = dateFrom >= 1 && dateFrom <= 31;
      final dates = _calculatePeriodDates(dateFrom, dateTo, daysMask, isMonthly);

      int count = 0;
      for (final date in dates) {
        final dt = DateTime(date.year, date.month, date.day, hour, minute);
        if (dt.isAfter(DateTime.now())) {
          await platform.invokeMethod('schedulePeriodReminder', {
            'itemId': itemId,
            'year': date.year,
            'month': date.month,
            'day': date.day,
            'hour': hour,
            'minute': minute,
            'title': title,
            'body': lw('Reminder'),
          });
          count++;
        }
      }
      myPrint('Scheduled $count period reminders for item $itemId');
    } catch (e) {
      myPrint('Failed to schedule period reminders: $e');
    }
  }

  // Calculate all valid dates for a period
  static List<DateTime> _calculatePeriodDates(int dateFrom, int dateTo, int daysMask, bool isMonthly) {
    final List<DateTime> result = [];
    final now = DateTime.now();

    if (isMonthly) {
      // Day-of-month: schedule for current month and next month
      for (int monthOffset = 0; monthOffset <= 1; monthOffset++) {
        final baseDate = DateTime(now.year, now.month + monthOffset, 1);
        final daysInMonth = DateTime(baseDate.year, baseDate.month + 1, 0).day;
        final startDay = dateFrom.clamp(1, daysInMonth);
        final endDay = dateTo.clamp(1, daysInMonth);

        if (startDay <= endDay) {
          for (int d = startDay; d <= endDay; d++) {
            final date = DateTime(baseDate.year, baseDate.month, d);
            if (_isDayInMask(date, daysMask)) {
              result.add(date);
            }
          }
        } else {
          // Wraps around month boundary (e.g., 28 to 5)
          for (int d = startDay; d <= daysInMonth; d++) {
            final date = DateTime(baseDate.year, baseDate.month, d);
            if (_isDayInMask(date, daysMask)) result.add(date);
          }
          final nextMonth = DateTime(baseDate.year, baseDate.month + 1, 1);
          final nextDaysInMonth = DateTime(nextMonth.year, nextMonth.month + 1, 0).day;
          for (int d = 1; d <= endDay.clamp(1, nextDaysInMonth); d++) {
            final date = DateTime(nextMonth.year, nextMonth.month, d);
            if (_isDayInMask(date, daysMask)) result.add(date);
          }
        }
      }
    } else {
      // Full dates: schedule all days in the range
      final fromDate = yyyymmddToDateTime(dateFrom);
      final toDate = yyyymmddToDateTime(dateTo);
      if (fromDate == null || toDate == null) return result;

      var current = fromDate;
      while (!current.isAfter(toDate)) {
        if (_isDayInMask(current, daysMask)) {
          result.add(current);
        }
        current = current.add(Duration(days: 1));
      }
    }

    return result;
  }

  // Check if a date's weekday matches the daysMask (bit 0=Mon, bit 6=Sun)
  static bool _isDayInMask(DateTime date, int daysMask) {
    // DateTime.weekday: 1=Mon, 7=Sun -> bit index: Mon=0, Sun=6
    final bitIndex = date.weekday == 7 ? 6 : date.weekday - 1;
    return (daysMask & (1 << bitIndex)) != 0;
  }

  // Cancel all period reminders for an item
  static Future<void> cancelPeriodReminders(int itemId) async {
    try {
      await platform.invokeMethod('cancelPeriodReminders', {
        'itemId': itemId,
      });
      myPrint('All period reminders cancelled for item $itemId');
    } catch (e) {
      myPrint('Failed to cancel period reminders: $e');
    }
  }

  // Update period reminders (cancel old, schedule new)
  static Future<void> updatePeriodReminders(
    int itemId,
    bool enabled,
    int? dateFrom,
    int? dateTo,
    int? time,
    int daysMask,
    String title,
  ) async {
    try {
      await cancelPeriodReminders(itemId);
      if (enabled && dateFrom != null && dateTo != null) {
        await schedulePeriodReminders(itemId, dateFrom, dateTo, time, daysMask, title);
      }
    } catch (e) {
      myPrint('Error updating period reminders: $e');
    }
  }

  // Get list of system notification sounds
  static Future<List<Map<String, String>>> getSystemSounds() async {
    try {
      final List<dynamic> result = await platform.invokeMethod('getSystemSounds');
      return result.map((item) {
        final map = item as Map<dynamic, dynamic>;
        return {
          'name': map['name']?.toString() ?? '',
          'uri': map['uri']?.toString() ?? '',
        };
      }).toList();
    } catch (e) {
      myPrint('Error getting system sounds: $e');
      return [];
    }
  }

  // Get default one-time/period sound from settings
  static Future<String?> getDefaultSound() async {
    try {
      final result = await platform.invokeMethod('getDefaultSound');
      return result as String?;
    } catch (e) {
      myPrint('Error getting default sound: $e');
      return null;
    }
  }

  // Get default daily sound from settings (or system default if not set)
  static Future<String?> getDefaultDailySound() async {
    try {
      final result = await platform.invokeMethod('getDefaultDailySound');
      return result as String?;
    } catch (e) {
      myPrint('Error getting default daily sound: $e');
      return null;
    }
  }

  // Play a sound (from system URI or file path)
  static Future<void> playSound({String? soundUri, String? soundPath}) async {
    try {
      await platform.invokeMethod('playSound', {
        'soundUri': soundUri,
        'soundPath': soundPath,
      });
    } catch (e) {
      myPrint('Error playing sound: $e');
    }
  }

  // Stop currently playing sound
  static Future<void> stopSound() async {
    try {
      await platform.invokeMethod('stopSound');
    } catch (e) {
      myPrint('Error stopping sound: $e');
    }
  }
}
