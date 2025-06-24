package com.example.memorizer

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.sqlite.SQLiteDatabase
import android.os.Build
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale


/**
 * Main activity for the application.
 * Initializes Method Channel for Flutter communication and sets up notifications.
 */
class MainActivity : FlutterActivity() {

    private lateinit var notificationService: NotificationService

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        try {
            // Request required permissions
            requestRequiredPermissions()

            // Initialize notification service
            notificationService = NotificationService(applicationContext)

            // Set up method channel for Flutter communication
            val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.memorizer/notifications")
            methodChannel.setMethodCallHandler(notificationService)

        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error configuring flutter engine: ${e.message}")
        }
    }

    private fun requestRequiredPermissions() {
        try {
            // Request notification permission for Android 13+
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                    ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 100)
                }
            }
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error requesting permissions: ${e.message}")
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)

        try {
            // Clear all notifications when app is launched
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancelAll()

            // Check if there's payload in intent
            if (intent.hasExtra("notification_payload")) {
                val payload = intent.getStringExtra("notification_payload")
                // Handle notification click if needed
            }
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error in onNewIntent: ${e.message}")
        }
    }
}


/**
 * Service for handling notifications.
 * Processes calls from Flutter and schedules individual reminders.
 */
class NotificationService(private val context: Context) : MethodChannel.MethodCallHandler {
    private val channelId = "memorizer_reminders"
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
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
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

                showNotification(id, title, body, payload)
                result.success(null)
            }
            "scheduleSpecificReminder" -> {
                val itemId = call.argument<Int>("itemId") ?: 0
                val year = call.argument<Int>("year") ?: 0
                val month = call.argument<Int>("month") ?: 0
                val day = call.argument<Int>("day") ?: 0
                val hour = call.argument<Int>("hour") ?: 0
                val minute = call.argument<Int>("minute") ?: 0
                val title = call.argument<String>("title") ?: ""
                val body = call.argument<String>("body") ?: ""

                scheduleSpecificReminder(itemId, year, month, day, hour, minute, title, body)
                result.success(true)
            }
            "cancelSpecificReminder" -> {
                val itemId = call.argument<Int>("itemId") ?: 0
                cancelSpecificReminder(itemId)
                result.success(true)
            }
            "cancelAllNotifications" -> {
                cancelAllNotifications()
                result.success(true)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    // Schedule a specific reminder for individual item
    private fun scheduleSpecificReminder(itemId: Int, year: Int, month: Int, day: Int, hour: Int, minute: Int, title: String, body: String) {
        try {
            Log.d("MemorizerApp", "Scheduling specific reminder for item $itemId at $year-$month-$day $hour:$minute")

            // Create intent for specific reminder
            val intent = Intent(context, NotificationReceiver::class.java).apply {
                action = "com.example.memorizer.SPECIFIC_REMINDER"
                putExtra("itemId", itemId)
                putExtra("title", title)
                putExtra("body", body)
            }

            // Use itemId as unique requestCode for PendingIntent
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                itemId, // Use itemId as unique code
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Set time for reminder
            val calendar = Calendar.getInstance().apply {
                set(Calendar.YEAR, year)
                set(Calendar.MONTH, month - 1) // Calendar months start from 0
                set(Calendar.DAY_OF_MONTH, day)
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, minute)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }

            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

            // Schedule exact reminder only if time is in the future
            if (calendar.timeInMillis > System.currentTimeMillis()) {
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

                Log.d("MemorizerApp", "Specific reminder scheduled for item $itemId at ${calendar.time}")
            } else {
                Log.d("MemorizerApp", "Reminder time is in the past for item $itemId, not scheduling")
            }
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error scheduling specific reminder: ${e.message}")
            e.printStackTrace()
        }
    }

    // Cancel a specific reminder
    private fun cancelSpecificReminder(itemId: Int) {
        try {
            Log.d("MemorizerApp", "Cancelling specific reminder for item $itemId")

            val intent = Intent(context, NotificationReceiver::class.java).apply {
                action = "com.example.memorizer.SPECIFIC_REMINDER"
            }

            val pendingIntent = PendingIntent.getBroadcast(
                context,
                itemId, // Use same itemId as code
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.cancel(pendingIntent)

            Log.d("MemorizerApp", "Specific reminder cancelled for item $itemId")
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error cancelling specific reminder: ${e.message}")
        }
    }

    private fun showNotification(id: Int, title: String, body: String, payload: String = "") {
        try {
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

            // Orange color
            val orangeColor = 0xFFfb8500.toInt()

            // Big text style
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
                .setOngoing(false)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .setColor(orangeColor)
                .setColorized(true)

            try {
                notificationManager.notify(id, builder.build())
            } catch (e: SecurityException) {
                Log.e("MemorizerApp", "Permission denied: ${e.message}")
            } catch (e: Exception) {
                Log.e("MemorizerApp", "Error showing notification: ${e.message}")
            }
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error in showNotification: ${e.message}")
        }
    }

    private fun cancelAllNotifications() {
        try {
            // Cancel all active notifications
            notificationManager.cancelAll()
            Log.d("MemorizerApp", "All notifications cancelled")
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error cancelling notifications: ${e.message}")
        }
    }
}

/**
 * BroadcastReceiver for handling individual reminders.
 * Shows notifications for scheduled events.
 */
class NotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("MemorizerApp", "NotificationReceiver: onReceive triggered with action: ${intent.action}")

        try {
            when (intent.action) {
                Intent.ACTION_BOOT_COMPLETED -> {
                    // Let BootReceiver handle this
                    Log.d("MemorizerApp", "Boot completed, forwarding to BootReceiver")
                    return
                }
                "com.example.memorizer.SPECIFIC_REMINDER" -> {
                    // Handle specific reminder
                    handleSpecificReminder(context, intent)
                    return
                }
            }
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error in NotificationReceiver.onReceive: ${e.message}")
            e.printStackTrace()
        }
    }

    // Handle specific reminder
    private fun handleSpecificReminder(context: Context, intent: Intent) {
        try {
            val itemId = intent.getIntExtra("itemId", 0)
            val title = intent.getStringExtra("title") ?: "Memorizer"
            val body = intent.getStringExtra("body") ?: "Reminder"

            Log.d("MemorizerApp", "Handling specific reminder for item $itemId")

            // Check if reminders are enabled
            if (!isRemindersEnabled(context)) {
                Log.d("MemorizerApp", "Reminders are disabled, skipping specific reminder")
                return
            }

            // Check if this item is still active in the database
            if (isItemStillActive(context, itemId)) {
                // Create notification channel
                createNotificationChannel(context)

                // Get item data from database
                val itemData = getItemData(context, itemId)
                val itemTitle = if (itemData.first.isNotEmpty()) "Reminder: ${itemData.first}" else title
                val itemContent = itemData.second.ifEmpty { body }

                // Show notification
                showEventNotification(context, itemId, itemTitle, itemContent, itemId)

                Log.d("MemorizerApp", "Specific reminder shown for item $itemId")
            } else {
                Log.d("MemorizerApp", "Item $itemId no longer exists or reminder disabled, skipping notification")
            }

        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error handling specific reminder: ${e.message}")
        }
    }

    // Get item data from database
    private fun getItemData(context: Context, itemId: Int): Pair<String, String> {
        return try {
            val dbPath = context.getDatabasePath("memorizer.db")
            if (!dbPath.exists()) return Pair("", "")

            val db = SQLiteDatabase.openDatabase(dbPath.absolutePath, null, SQLiteDatabase.OPEN_READONLY)

            val cursor = db.rawQuery(
                "SELECT title, content FROM items WHERE id = ?",
                arrayOf(itemId.toString())
            )

            val result = if (cursor.moveToFirst()) {
                val title = cursor.getString(0) ?: ""
                val content = cursor.getString(1) ?: ""
                Pair(title, content)
            } else {
                Pair("", "")
            }

            cursor.close()
            db.close()
            result
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error getting item data: ${e.message}")
            Pair("", "")
        }
    }

    // Check if item is still active in database
    private fun isItemStillActive(context: Context, itemId: Int): Boolean {
        return try {
            val dbPath = context.getDatabasePath("memorizer.db")
            if (!dbPath.exists()) return false

            val db = SQLiteDatabase.openDatabase(dbPath.absolutePath, null, SQLiteDatabase.OPEN_READONLY)

            val cursor = db.rawQuery(
                "SELECT remind FROM items WHERE id = ?",
                arrayOf(itemId.toString())
            )

            val isActive = if (cursor.moveToFirst()) {
                cursor.getInt(0) == 1 // remind must be enabled
            } else {
                false // item not found
            }

            cursor.close()
            db.close()
            isActive
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error checking if item is active: ${e.message}")
            false
        }
    }

    private fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "memorizer_reminders",
                "Memorizer Reminders",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Reminders for Memorizer app" // ← ИСПРАВЛЕНО описание
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

            // Orange color
            val orangeColor = 0xFFfb8500.toInt()

            // Big text style
            val bigTextStyle = NotificationCompat.BigTextStyle()
                .bigText(content)
                .setBigContentTitle(title)

            // Create notification
            val builder = NotificationCompat.Builder(context, "memorizer_reminders") // ← ИСПРАВЛЕНО
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
                .setDefaults(NotificationCompat.DEFAULT_ALL)

            // Show notification with permission check
            try {
                val notificationManager = NotificationManagerCompat.from(context)
                notificationManager.notify(notificationId, builder.build())
                Log.d("MemorizerApp", "Notification shown with ID: $notificationId")
            } catch (se: SecurityException) {
                Log.e("MemorizerApp", "Security exception showing notification: ${se.message}")
            }

        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error showing notification: ${e.message}")
        }
    }

    // Check if reminders are enabled in settings
    private fun isRemindersEnabled(context: Context): Boolean {
        try {
            val dbPath = context.getDatabasePath("settings.db")
            if (!dbPath.exists()) {
                return true // Default enabled
            }

            val db = SQLiteDatabase.openDatabase(
                dbPath.absolutePath,
                null,
                SQLiteDatabase.OPEN_READONLY
            )

            val cursor = db.rawQuery(
                "SELECT value FROM settings WHERE key = ?",
                arrayOf("Enable reminders")
            )

            val result = if (cursor.moveToFirst()) {
                cursor.getString(0) == "true"
            } else {
                true // Default enabled
            }

            cursor.close()
            db.close()
            return result
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error checking if reminders enabled: ${e.message}")
            return true // Default if error
        }
    }
}


/**
 * BroadcastReceiver for restoring scheduled notifications
 * after device reboot
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.d("MemorizerApp", "Device rebooted, rescheduling notifications")

            try {
                // Add delay to let system fully initialize
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    rescheduleAllReminders(context)
                }, 5000) // 5 second delay
            } catch (e: Exception) {
                Log.e("MemorizerApp", "Error rescheduling after boot: ${e.message}")
            }
        }
    }

    private fun rescheduleAllReminders(context: Context) {
        try {
            // Check if reminders are enabled
            if (!isRemindersEnabled(context)) {
                Log.d("MemorizerApp", "Reminders are disabled, not rescheduling")
                return
            }

            val dbPath = context.getDatabasePath("memorizer.db")
            if (!dbPath.exists()) {
                Log.e("MemorizerApp", "Database file does not exist")
                return
            }

            val db = SQLiteDatabase.openDatabase(
                dbPath.absolutePath,
                null,
                SQLiteDatabase.OPEN_READONLY
            )

            // Get today's date in YYYYMMDD format
            val dateFormat = SimpleDateFormat("yyyyMMdd", Locale.getDefault())
            val todayDate = dateFormat.format(Calendar.getInstance().time).toInt()

            // Query for all future reminders
            val cursor = db.rawQuery(
                "SELECT id, title, content, date, time FROM items WHERE remind = 1 AND date >= ?",
                arrayOf(todayDate.toString())
            )

            var rescheduledCount = 0

            while (cursor.moveToNext()) {
                try {
                    val itemId = cursor.getInt(0)
                    val title = cursor.getString(1) ?: ""
                    val content = cursor.getString(2) ?: ""
                    val date = cursor.getInt(3)
                    val time = if (cursor.isNull(4)) null else cursor.getInt(4)

                    // Parse date
                    val year = date / 10000
                    val month = (date % 10000) / 100
                    val day = date % 100

                    // Parse time or use default
                    val hour = time?.let { it / 100 } ?: 8
                    val minute = time?.let { it % 100 } ?: 0

                    // Schedule the reminder
                    scheduleSpecificReminder(
                        context,
                        itemId,
                        year,
                        month,
                        day,
                        hour,
                        minute,
                        title,
                        content
                    )

                    rescheduledCount++
                } catch (e: Exception) {
                    Log.e("MemorizerApp", "Error rescheduling item: ${e.message}")
                }
            }

            cursor.close()
            db.close()

            Log.d("MemorizerApp", "Rescheduled $rescheduledCount reminders after reboot")
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error in rescheduleAllReminders: ${e.message}")
        }
    }

    private fun scheduleSpecificReminder(
        context: Context,
        itemId: Int,
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        title: String,
        body: String
    ) {
        try {
            val intent = Intent(context, NotificationReceiver::class.java).apply {
                action = "com.example.memorizer.SPECIFIC_REMINDER"
                putExtra("itemId", itemId)
                putExtra("title", "Memorizer")
                putExtra("body", "Reminder")
            }

            val pendingIntent = PendingIntent.getBroadcast(
                context,
                itemId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val calendar = Calendar.getInstance().apply {
                set(Calendar.YEAR, year)
                set(Calendar.MONTH, month - 1)
                set(Calendar.DAY_OF_MONTH, day)
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, minute)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }

            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

            if (calendar.timeInMillis > System.currentTimeMillis()) {
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
            }
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error scheduling reminder in boot receiver: ${e.message}")
        }
    }

    private fun isRemindersEnabled(context: Context): Boolean {
        try {
            val dbPath = context.getDatabasePath("settings.db")
            if (!dbPath.exists()) {
                return true
            }

            val db = SQLiteDatabase.openDatabase(
                dbPath.absolutePath,
                null,
                SQLiteDatabase.OPEN_READONLY
            )

            val cursor = db.rawQuery(
                "SELECT value FROM settings WHERE key = ?",
                arrayOf("Enable reminders")
            )

            val result = if (cursor.moveToFirst()) {
                cursor.getString(0) == "true"
            } else {
                true
            }

            cursor.close()
            db.close()
            return result
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error checking if reminders enabled: ${e.message}")
            return true
        }
    }
}

