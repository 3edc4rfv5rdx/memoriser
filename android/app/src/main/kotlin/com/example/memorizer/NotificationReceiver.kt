package com.example.memorizer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

class NotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("MemorizerApp", "NotificationReceiver: onReceive triggered")

        // Сначала проверяем, есть ли события на сегодня
        val hasEventsForToday = checkForTodayEvents(context)

        // Если нет событий, просто выходим без показа уведомления
        if (!hasEventsForToday) {
            Log.d("MemorizerApp", "No events for today, skipping notification")
            return
        }

        // Если события есть, показываем уведомление
        val title = intent.getStringExtra("title") ?: "Memorizer"
        val body = intent.getStringExtra("body") ?: "Check your events for today"

        try {
            // Создаем специальный цветной канал
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
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
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.createNotificationChannel(coloredChannel)
            }

            // Create notification intent
            val notificationIntent = Intent(context, MainActivity::class.java)
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                notificationIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Цвет оранжевый
            val orangeColor = 0xFFfb8500.toInt()

            // Создаем стиль для текста
            val bigTextStyle = NotificationCompat.BigTextStyle()
                .bigText(body)
                .setBigContentTitle(title)

            // Создаем уведомление
            val builder = NotificationCompat.Builder(context, "memorizer_colored_channel")
                .setSmallIcon(R.drawable.notification_icon)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(bigTextStyle)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .setColor(orangeColor)
                .setColorized(true)

            // Для Android 5.0+ (Lollipop)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                builder.setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            }

            // Show the notification
            val notificationManager = NotificationManagerCompat.from(context)
            try {
                // Дополнительные флаги для усиления важности
                val notification = builder.build()
                notification.flags = notification.flags or android.app.Notification.FLAG_SHOW_LIGHTS

                notificationManager.notify(0, notification)
                Log.d("MemorizerApp", "Notification shown from receiver")
            } catch (e: SecurityException) {
                Log.e("MemorizerApp", "Permission denied in receiver: ${e.message}")
            } catch (e: Exception) {
                Log.e("MemorizerApp", "Error showing notification in receiver: ${e.message}")
            }

            // Also send a message to Flutter to check for today's events
            MainActivity.checkEvents()
            Log.d("MemorizerApp", "checkEvents called from receiver")
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error in NotificationReceiver.onReceive: ${e.message}")
        }
    }

    // Метод для проверки наличия событий на сегодня
    private fun checkForTodayEvents(context: Context): Boolean {
        try {
            // Получаем сегодняшнюю дату в формате YYYYMMDD
            val calendar = Calendar.getInstance()
            val dateFormat = SimpleDateFormat("yyyyMMdd", Locale.getDefault())
            val todayDate = dateFormat.format(calendar.time).toInt()

            // Открываем базу данных SQLite
            val dbPath = context.getDatabasePath("memorizer.db").absolutePath
            val db = android.database.sqlite.SQLiteDatabase.openDatabase(
                dbPath, null, android.database.sqlite.SQLiteDatabase.OPEN_READONLY
            )

            // Запрашиваем количество событий на сегодня с включенными напоминаниями
            val cursor = db.rawQuery(
                "SELECT COUNT(*) FROM items WHERE remind = 1 AND date = ? AND (hidden = 0 OR hidden IS NULL)",
                arrayOf(todayDate.toString())
            )

            var count = 0
            if (cursor.moveToFirst()) {
                count = cursor.getInt(0)
            }

            cursor.close()
            db.close()

            Log.d("MemorizerApp", "Found $count events for today")
            return count > 0

        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error checking events for today: ${e.message}")
            // В случае ошибки лучше показать уведомление, чем пропустить его
            return true
        }
    }
}
