package com.example.memorizer

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

class NotificationService(private val context: Context) : MethodChannel.MethodCallHandler {
    private val channelId = "memorizer_channel"
    private val notificationManager = NotificationManagerCompat.from(context)

    init {
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Memorizer Reminders",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Reminders for Memorizer app"
                enableLights(true)
                enableVibration(true)
            }
            // Регистрируем канал в системе
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
            Log.d("MemorizerApp", "Notification channel created")
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.d("MemorizerApp", "Method called: ${call.method}")
        when (call.method) {
            "initializeNotifications" -> {
                createNotificationChannel()
                result.success(null)
            }
            "showNotification" -> {
                val id = call.argument<Int>("id") ?: 0
                val title = call.argument<String>("title") ?: ""
                val body = call.argument<String>("body") ?: ""
                val payload = call.argument<String>("payload") ?: ""

                Log.d("MemorizerApp", "Show notification requested: ID=$id, Title=$title")
                showNotification(id, title, body, payload)
                result.success(null)
            }
            "scheduleDaily" -> {
                val time = call.argument<String>("time") ?: "08:00"
                val title = call.argument<String>("title") ?: ""
                val body = call.argument<String>("body") ?: ""

                scheduleDaily(time, title, body)
                result.success(null)
            }
            "cancelAllNotifications" -> {
                cancelAllNotifications()
                result.success(null)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun showNotification(id: Int, title: String, body: String, payload: String = "") {
        try {
            Log.d("MemorizerApp", "Showing notification: ID=$id, Title=$title")

            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                putExtra("notification_payload", payload)
            }

            val pendingIntent = PendingIntent.getActivity(
                context,
                id,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Создаем цвет - оранжевый
            val orangeColor = 0xFFfb8500.toInt()

            // Создаем стиль для большего текста
            val bigTextStyle = NotificationCompat.BigTextStyle()
                .bigText(body)
                .setBigContentTitle(title)

            val builder = NotificationCompat.Builder(context, channelId)
                .setSmallIcon(R.drawable.notification_icon)
                .setContentTitle(title)
                .setContentText(body)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setContentIntent(pendingIntent)
                .setStyle(bigTextStyle)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setAutoCancel(true)
                .setOngoing(false) // Для более важного вида
                .setDefaults(NotificationCompat.DEFAULT_ALL) // Звук, вибрация и т.д.
                .setColor(orangeColor)
                .setColorized(true)

            // Добавляем цвет для Android 5.0+ (Lollipop)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                builder.setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            }

            // На некоторых устройствах нужен явный канал для цветных уведомлений
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

                // Создаем специальный канал для цветных уведомлений
                val coloredChannel = NotificationChannel(
                    "memorizer_colored_channel",
                    "Memorizer Colored Reminders",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Colored reminders for Memorizer app"
                    enableLights(true)
                    enableVibration(true)
                    setShowBadge(true)
                }
                notificationManager.createNotificationChannel(coloredChannel)

                // Используем новый канал
                builder.setChannelId("memorizer_colored_channel")
            }

            // Показываем уведомление
            try {
                // Используем новый метод для heads-up уведомления
                val notification = builder.build()
                notification.flags = notification.flags or android.app.Notification.FLAG_SHOW_LIGHTS

                notificationManager.notify(id, notification)
                Log.d("MemorizerApp", "Notification shown successfully: ID=$id")
            } catch (e: SecurityException) {
                Log.e("MemorizerApp", "Permission denied: ${e.message}")
            } catch (e: Exception) {
                Log.e("MemorizerApp", "Error showing notification: ${e.message}")
            }
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error in showNotification: ${e.message}")
        }
    }

    private fun scheduleDaily(timeString: String, title: String, body: String) {
        try {
            // Parse time string (format: HH:MM)
            val parts = timeString.split(":")
            val hour = parts[0].toIntOrNull() ?: 10
            val minute = parts[1].toIntOrNull() ?: 0

            Log.d("MemorizerApp", "Scheduling daily notification at: $hour:$minute")

            // Create intent for the alarm
            val intent = Intent(context, NotificationReceiver::class.java).apply {
                putExtra("title", title)
                putExtra("body", body)
            }

            val pendingIntent = PendingIntent.getBroadcast(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Set the alarm to trigger at the specified time
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val calendar = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, minute)
                set(Calendar.SECOND, 0)

                // If time has already passed today, set for tomorrow
                if (timeInMillis < System.currentTimeMillis()) {
                    add(Calendar.DAY_OF_YEAR, 1)
                }
            }

            Log.d("MemorizerApp", "Alarm scheduled for: ${calendar.time}")

            // Schedule the alarm to repeat daily
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    calendar.timeInMillis,
                    pendingIntent
                )
            } else {
                alarmManager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    calendar.timeInMillis,
                    pendingIntent
                )
            }

            // Также сразу показываем уведомление для проверки
            // showNotification(100, "Тестовое уведомление", "Уведомления запланированы на $timeString")
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error in scheduleDaily: ${e.message}")
        }
    }

    private fun cancelAllNotifications() {
        try {
            notificationManager.cancelAll()

            // Cancel scheduled alarms
            val intent = Intent(context, NotificationReceiver::class.java)
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.cancel(pendingIntent)

            Log.d("MemorizerApp", "All notifications cancelled")
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error in cancelAllNotifications: ${e.message}")
        }
    }
}