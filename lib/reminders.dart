// reminders.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'globals.dart';
import 'additem.dart';

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
      final remindTime = await getSetting("Remind time") ?? "10:00";
      
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
// Проверка событий на сегодня и показ уведомлений
  static Future<void> checkTodayEvents() async {
    // Проверяем, включены ли напоминания
    final enableReminders = await getSetting("Enable reminders") ?? defSettings["Enable reminders"];

    if (enableReminders != "true") {
      myPrint('Напоминания отключены, пропускаю проверку событий на сегодня');
      return;
    }

    myPrint('Проверка событий на сегодня...');

    try {
      // Получаем временные метки начала и конца сегодняшнего дня
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59).millisecondsSinceEpoch;

      // Запрашиваем в базе данных события на сегодня с включенными напоминаниями
      final todayEvents = await mainDb.query(
          'items',
          where: 'remind = 1 AND date >= ? AND date <= ?',
          whereArgs: [startOfDay, endOfDay],
          orderBy: 'date ASC'
      );

      myPrint('Найдено ${todayEvents.length} событий на сегодня');

      if (todayEvents.isEmpty) {
        // Если нет событий, показываем сообщение в приложении
        if (scaffoldMessengerKey.currentState != null) {
          okInfoBarBlue(lw('На сегодня нет запланированных событий'));
        }
        return;
      }

      // Обрабатываем события - показываем уведомление для каждого
      for (var item in todayEvents) {
        // Если в скрытом режиме, обрабатываем запись для отображения
        final processedItem = xvHiddenMode && (item['hidden'] as int? ?? 0) == 1
            ? processItemForView(item)
            : item;

        // Показываем уведомление для этого события с корректным приведением типов
        await showNotification(
            item['id'] as int,
            lw('Напоминание') + ': ' + (processedItem['title'] as String? ?? ''),
            processedItem['content'] as String? ?? '',
            payload: (item['id'] as int).toString()
        );
      }

      // Показываем итоговое уведомление, если несколько событий
      if (todayEvents.length > 1) {
        await showNotification(
            999999,
            lw('События на сегодня'),
            lw('У вас запланировано ${todayEvents.length} событий на сегодня')
        );
      }

    } catch (e) {
      myPrint('Ошибка проверки событий на сегодня: $e');
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
