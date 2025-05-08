package com.example.memorizer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

class NotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("MemorizerApp", "NotificationReceiver: onReceive triggered with action: ${intent.action}")

        try {
            // Проверяем, что это не перезагрузка устройства
            if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
                // Передаем управление в BootReceiver
                Log.d("MemorizerApp", "Boot completed, forwarding to BootReceiver")
                return
            }

            // Проверяем, включены ли напоминания
            val prefs = context.getSharedPreferences("memorizer_notifications", Context.MODE_PRIVATE)
            val remindersEnabled = prefs.getBoolean(NotificationService.PREF_REMINDER_ENABLED, false)

            if (!remindersEnabled) {
                Log.d("MemorizerApp", "Reminders are disabled, skipping notification check")
                return
            }

            // Получаем сегодняшнюю дату в формате YYYYMMDD
            val calendar = Calendar.getInstance()
            val dateFormat = SimpleDateFormat("yyyyMMdd", Locale.getDefault())
            val todayDate = dateFormat.format(calendar.time).toInt()

            Log.d("MemorizerApp", "Checking events for today: $todayDate")

            // Пробуем открыть базу данных напрямую
            val dbPath = context.getDatabasePath("memorizer.db")

            if (!dbPath.exists()) {
                Log.e("MemorizerApp", "Database file does not exist at path: ${dbPath.absolutePath}")
                return
            }

            val db = SQLiteDatabase.openDatabase(
                dbPath.absolutePath, null, SQLiteDatabase.OPEN_READONLY
            )

            // Запрашиваем события на сегодня с включенными напоминаниями
            val cursor = db.rawQuery(
                "SELECT id, title, content FROM items WHERE remind = 1 AND date = ? AND (hidden = 0 OR hidden IS NULL)",
                arrayOf(todayDate.toString())
            )

            // Получаем количество событий
            val eventCount = cursor.count
            Log.d("MemorizerApp", "Found $eventCount events with reminders for today")

            // Если нет событий, просто выходим
            if (eventCount == 0) {
                cursor.close()
                db.close()
                Log.d("MemorizerApp", "No events for today, skipping notifications")
                return
            }

            // Создаем канал уведомлений
            createNotificationChannel(context)

            // Для каждого события создаем отдельное уведомление
            var notificationId = 1
            while (cursor.moveToNext()) {
                // Используем getColumnIndexOrThrow для безопасного получения индексов колонок
                val idColumn = cursor.getColumnIndexOrThrow("id")
                val titleColumn = cursor.getColumnIndexOrThrow("title")
                val contentColumn = cursor.getColumnIndexOrThrow("content")

                val id = cursor.getInt(idColumn)
                val title = cursor.getString(titleColumn) ?: ""
                val content = cursor.getString(contentColumn) ?: ""

                Log.d("MemorizerApp", "Showing reminder for event ID: $id, Title: $title")
                showEventNotification(context, id, "Reminder: $title", content, notificationId)
                notificationId++
            }

            // Если событий больше одного, показываем общее уведомление
            if (eventCount > 1) {
                showEventNotification(
                    context,
                    0,
                    "Today's events",
                    "You have $eventCount scheduled events for today",
                    999999
                )
            }

            cursor.close()
            db.close()

            // Отправляем сообщение в Flutter для проверки событий
            MainActivity.checkEvents()

        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error in NotificationReceiver.onReceive: ${e.message}")
            e.printStackTrace()
        }
    }

    private fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
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
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun showEventNotification(context: Context, itemId: Int, title: String, content: String, notificationId: Int) {
        try {
            // Create notification intent that opens the app
            val notificationIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                putExtra("notification_payload", itemId.toString())
            }

            val pendingIntent = PendingIntent.getActivity(
                context,
                notificationId,
                notificationIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Оранжевый цвет
            val orangeColor = 0xFFfb8500.toInt()

            // Стиль для большого текста
            val bigTextStyle = NotificationCompat.BigTextStyle()
                .bigText(content)
                .setBigContentTitle(title)

            // Создаем уведомление
            val builder = NotificationCompat.Builder(context, "memorizer_colored_channel")
                .setSmallIcon(R.drawable.notification_icon)
                .setContentTitle(title)
                .setContentText(content)
                .setStyle(bigTextStyle)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setColor(orangeColor)
                .setColorized(true)

            // Добавляем звук, вибрацию и свет
            builder.setDefaults(NotificationCompat.DEFAULT_ALL)

            // Показываем уведомление с проверкой разрешений
            try {
                val notificationManager = NotificationManagerCompat.from(context)
                notificationManager.notify(notificationId, builder.build())
                Log.d("MemorizerApp", "Notification shown with ID: $notificationId")
            } catch (se: SecurityException) {
                Log.e("MemorizerApp", "Security exception showing notification: ${se.message}")
            }

        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error showing notification: ${e.message}")
            e.printStackTrace()
        }
    }
}
