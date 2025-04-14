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

class NotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("MemorizerApp", "NotificationReceiver: onReceive triggered")

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
}
