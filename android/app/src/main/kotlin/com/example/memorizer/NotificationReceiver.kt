package com.example.memorizer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.database.Cursor
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

            // Запрашиваем события на сегодня с включенными напоминаниями
            val cursor = db.rawQuery(
                "SELECT id, title, content FROM items WHERE remind = 1 AND date = ? AND (hidden = 0 OR hidden IS NULL)",
                arrayOf(todayDate.toString())
            )

            // Получаем количество событий
            val eventCount = cursor.count

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
                val id = cursor.getInt(cursor.getColumnIndex("id"))
                val title = cursor.getString(cursor.getColumnIndex("title")) ?: ""
                val content = cursor.getString(cursor.getColumnIndex("content")) ?: ""

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

        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error in NotificationReceiver.onReceive: ${e.message}")
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
            val notificationIntent = Intent(context, MainActivity::class.java)
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

            // Показываем уведомление
            val notificationManager = NotificationManagerCompat.from(context)
            notificationManager.notify(notificationId, builder.build())

            Log.d("MemorizerApp", "Notification shown with ID: $notificationId")

        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error showing notification: ${e.message}")
        }
    }
}
