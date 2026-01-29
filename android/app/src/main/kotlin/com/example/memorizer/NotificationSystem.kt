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
import android.media.RingtoneManager
import android.net.Uri
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
    private val notificationManager = NotificationManagerCompat.from(context)

    init {
        // Create default daily channel on init
        createDailyNotificationChannel()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initializeNotifications" -> {
                // Only create daily channel, reminder channels are created dynamically
                createDailyNotificationChannel()
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
            "scheduleDailyReminder" -> {
                val itemId = call.argument<Int>("itemId") ?: 0
                val hour = call.argument<Int>("hour") ?: 0
                val minute = call.argument<Int>("minute") ?: 0
                val daysMask = call.argument<Int>("daysMask") ?: 127 // All days by default
                val title = call.argument<String>("title") ?: ""
                val body = call.argument<String>("body") ?: ""

                scheduleDailyReminder(itemId, hour, minute, daysMask, title, body)
                result.success(true)
            }
            "cancelDailyReminder" -> {
                val itemId = call.argument<Int>("itemId") ?: 0
                val hour = call.argument<Int>("hour") ?: 0
                val minute = call.argument<Int>("minute") ?: 0
                cancelDailyReminder(itemId, hour, minute)
                result.success(true)
            }
            "cancelAllDailyReminders" -> {
                val itemId = call.argument<Int>("itemId") ?: 0
                cancelAllDailyReminders(itemId)
                result.success(true)
            }
            "getSystemSounds" -> {
                val sounds = getSystemSounds()
                result.success(sounds)
            }
            "getDefaultDailySound" -> {
                val sound = getDefaultDailySound(context)
                result.success(sound)
            }
            "playSound" -> {
                val soundUri = call.argument<String>("soundUri")
                val soundPath = call.argument<String>("soundPath")
                playSound(soundUri, soundPath)
                result.success(true)
            }
            "stopSound" -> {
                stopSound()
                result.success(true)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    // Media player for sound playback
    private var mediaPlayer: android.media.MediaPlayer? = null

    // Get list of system notification sounds
    private fun getSystemSounds(): List<Map<String, String>> {
        val sounds = mutableListOf<Map<String, String>>()

        // Add default notification sound
        val defaultUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        sounds.add(mapOf(
            "name" to "Default",
            "uri" to defaultUri.toString()
        ))

        // Get all notification sounds
        val manager = RingtoneManager(context)
        manager.setType(RingtoneManager.TYPE_NOTIFICATION)
        val cursor = manager.cursor

        while (cursor.moveToNext()) {
            val title = cursor.getString(RingtoneManager.TITLE_COLUMN_INDEX)
            val uri = manager.getRingtoneUri(cursor.position).toString()
            sounds.add(mapOf(
                "name" to title,
                "uri" to uri
            ))
        }

        // Also add alarm sounds
        val alarmManager = RingtoneManager(context)
        alarmManager.setType(RingtoneManager.TYPE_ALARM)
        val alarmCursor = alarmManager.cursor

        while (alarmCursor.moveToNext()) {
            val title = alarmCursor.getString(RingtoneManager.TITLE_COLUMN_INDEX)
            val uri = alarmManager.getRingtoneUri(alarmCursor.position).toString()
            sounds.add(mapOf(
                "name" to "$title (Alarm)",
                "uri" to uri
            ))
        }

        return sounds
    }

    // Play sound from URI or file path
    private fun playSound(soundUri: String?, soundPath: String?) {
        try {
            stopSound() // Stop any currently playing sound

            mediaPlayer = android.media.MediaPlayer().apply {
                when {
                    soundUri != null -> {
                        setDataSource(context, Uri.parse(soundUri))
                    }
                    soundPath != null -> {
                        // Use Uri.fromFile for file paths to handle permissions properly
                        val fileUri = Uri.fromFile(java.io.File(soundPath))
                        setDataSource(context, fileUri)
                    }
                    else -> {
                        // Play default notification sound
                        val defaultUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                        setDataSource(context, defaultUri)
                    }
                }
                prepare()
                start()
                setOnCompletionListener {
                    it.release()
                    mediaPlayer = null
                }
            }
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error playing sound: ${e.message}")
        }
    }

    // Stop currently playing sound
    private fun stopSound() {
        try {
            mediaPlayer?.let {
                if (it.isPlaying) {
                    it.stop()
                }
                it.release()
            }
            mediaPlayer = null
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error stopping sound: ${e.message}")
        }
    }

    // Get default daily sound from settings (or system default if not set)
    private fun getDefaultDailySound(context: Context): String? {
        try {
            val dbPath = context.getDatabasePath("settings.db")

            // Try to read from settings
            if (dbPath.exists()) {
                val db = SQLiteDatabase.openDatabase(
                    dbPath.absolutePath,
                    null,
                    SQLiteDatabase.OPEN_READONLY
                )

                val cursor = db.rawQuery(
                    "SELECT value FROM settings WHERE key = ?",
                    arrayOf("Default daily sound")
                )

                val result = if (cursor.moveToFirst()) {
                    val value = cursor.getString(0)
                    if (value.isNullOrEmpty()) null else value
                } else {
                    null
                }

                cursor.close()
                db.close()

                if (result != null) {
                    return result
                }
            }

            // No setting found - get system default notification sound
            val systemDefaultUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val systemDefaultString = systemDefaultUri?.toString()

            if (systemDefaultString != null) {
                // Save to settings for future use
                saveDefaultDailySound(context, systemDefaultString)
                Log.d("MemorizerApp", "Set system default daily sound: $systemDefaultString")
            }

            return systemDefaultString
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error getting default daily sound: ${e.message}")
            return null
        }
    }

    // Save default daily sound to settings
    private fun saveDefaultDailySound(context: Context, soundUri: String) {
        try {
            val dbPath = context.getDatabasePath("settings.db")
            val db = SQLiteDatabase.openOrCreateDatabase(dbPath.absolutePath, null)

            db.execSQL("CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)")

            db.execSQL(
                "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                arrayOf("Default daily sound", soundUri)
            )

            db.close()
            Log.d("MemorizerApp", "Saved default daily sound to settings: $soundUri")
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error saving default daily sound: ${e.message}")
        }
    }

    // Create notification channel for daily reminders
    private fun createDailyNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "memorizer_daily",
                "Daily Reminders",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Daily reminders for Memorizer app"
                enableLights(true)
                enableVibration(true)
            }
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    // Schedule a daily reminder for specific item
    private fun scheduleDailyReminder(itemId: Int, hour: Int, minute: Int, daysMask: Int, title: String, body: String) {
        try {
            Log.d("MemorizerApp", "Scheduling daily reminder for item $itemId at $hour:$minute, daysMask=$daysMask")

            // Create intent for daily reminder
            val intent = Intent(context, NotificationReceiver::class.java).apply {
                action = "com.example.memorizer.DAILY_REMINDER"
                putExtra("itemId", itemId)
                putExtra("hour", hour)
                putExtra("minute", minute)
                putExtra("daysMask", daysMask)
                putExtra("title", title)
                putExtra("body", body)
            }

            // Use unique requestCode based on itemId, hour and minute
            val requestCode = itemId * 10000 + hour * 100 + minute

            val pendingIntent = PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Set time for next reminder (today or tomorrow)
            val calendar = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, minute)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)

                // If time already passed today, schedule for tomorrow
                if (timeInMillis <= System.currentTimeMillis()) {
                    add(Calendar.DAY_OF_YEAR, 1)
                }
            }

            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

            // Schedule repeating alarm
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

            Log.d("MemorizerApp", "Daily reminder scheduled for item $itemId at ${calendar.time}")
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error scheduling daily reminder: ${e.message}")
            e.printStackTrace()
        }
    }

    // Cancel a specific daily reminder
    private fun cancelDailyReminder(itemId: Int, hour: Int, minute: Int) {
        try {
            Log.d("MemorizerApp", "Cancelling daily reminder for item $itemId at $hour:$minute")

            val intent = Intent(context, NotificationReceiver::class.java).apply {
                action = "com.example.memorizer.DAILY_REMINDER"
            }

            val requestCode = itemId * 10000 + hour * 100 + minute

            val pendingIntent = PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.cancel(pendingIntent)

            Log.d("MemorizerApp", "Daily reminder cancelled for item $itemId at $hour:$minute")
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error cancelling daily reminder: ${e.message}")
        }
    }

    // Cancel all daily reminders for an item
    private fun cancelAllDailyReminders(itemId: Int) {
        try {
            Log.d("MemorizerApp", "Cancelling all daily reminders for item $itemId")
            // Cancel all possible time combinations (this is a simplification)
            // In a production app, you might want to track scheduled times
            for (hour in 0..23) {
                for (minute in listOf(0, 15, 30, 45)) {
                    cancelDailyReminder(itemId, hour, minute)
                }
            }
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error cancelling all daily reminders: ${e.message}")
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

    // Direct notification (not scheduled) - uses daily channel as fallback
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

            // Use daily channel as fallback for direct notifications
            val builder = NotificationCompat.Builder(context, "memorizer_daily")
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
                "com.example.memorizer.DAILY_REMINDER" -> {
                    // Handle daily reminder
                    handleDailyReminder(context, intent)
                    return
                }
            }
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error in NotificationReceiver.onReceive: ${e.message}")
            e.printStackTrace()
        }
    }

    // Handle daily reminder
    private fun handleDailyReminder(context: Context, intent: Intent) {
        try {
            val itemId = intent.getIntExtra("itemId", 0)
            val hour = intent.getIntExtra("hour", 0)
            val minute = intent.getIntExtra("minute", 0)
            val daysMask = intent.getIntExtra("daysMask", 127)
            val title = intent.getStringExtra("title") ?: "Daily Reminder"
            val body = intent.getStringExtra("body") ?: ""

            Log.d("MemorizerApp", "Handling daily reminder for item $itemId at $hour:$minute")

            // Check if daily reminders are enabled globally
            if (!isDailyRemindersEnabled(context)) {
                Log.d("MemorizerApp", "Daily reminders are disabled, skipping")
                rescheduleNextDailyReminder(context, itemId, hour, minute, daysMask, title, body)
                return
            }

            // Check if today is an enabled day (bit 0 = Monday, bit 6 = Sunday)
            val calendar = Calendar.getInstance()
            // Calendar.DAY_OF_WEEK: Sunday=1, Monday=2, ..., Saturday=7
            // Our bitmask: bit 0=Monday, bit 6=Sunday
            val calendarDayOfWeek = calendar.get(Calendar.DAY_OF_WEEK)
            val dayIndex = if (calendarDayOfWeek == Calendar.SUNDAY) 6 else calendarDayOfWeek - 2

            if ((daysMask and (1 shl dayIndex)) == 0) {
                Log.d("MemorizerApp", "Today (day index $dayIndex) is not in daysMask $daysMask, skipping")
                rescheduleNextDailyReminder(context, itemId, hour, minute, daysMask, title, body)
                return
            }

            // Check if item still has daily reminders enabled
            if (!isItemDailyActive(context, itemId)) {
                Log.d("MemorizerApp", "Item $itemId daily reminder is disabled, not rescheduling")
                return
            }

            // Get item data from database
            val itemData = getItemData(context, itemId)
            val itemTitle = if (itemData.title.isNotEmpty()) itemData.title else title
            val itemContent = itemData.content.ifEmpty { body }
            val itemSound = itemData.dailySound

            // Check if fullscreen alert is enabled
            if (itemData.fullscreen == 1) {
                launchFullscreenAlert(context, itemId, itemTitle, itemContent, itemSound)
            } else {
                // Create notification channel for daily reminders with custom sound
                val channelId = createDailyNotificationChannel(context, itemSound)

                // Show notification
                showDailyNotification(context, itemId, hour, minute, itemTitle, itemContent, itemSound, channelId)
            }

            // Reschedule for next occurrence
            rescheduleNextDailyReminder(context, itemId, hour, minute, daysMask, title, body)

        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error handling daily reminder: ${e.message}")
        }
    }

    // Reschedule daily reminder for next day
    private fun rescheduleNextDailyReminder(context: Context, itemId: Int, hour: Int, minute: Int, daysMask: Int, title: String, body: String) {
        try {
            val intent = Intent(context, NotificationReceiver::class.java).apply {
                action = "com.example.memorizer.DAILY_REMINDER"
                putExtra("itemId", itemId)
                putExtra("hour", hour)
                putExtra("minute", minute)
                putExtra("daysMask", daysMask)
                putExtra("title", title)
                putExtra("body", body)
            }

            val requestCode = itemId * 10000 + hour * 100 + minute

            val pendingIntent = PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Schedule for tomorrow at the same time
            val calendar = Calendar.getInstance().apply {
                add(Calendar.DAY_OF_YEAR, 1)
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, minute)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }

            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

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

            Log.d("MemorizerApp", "Daily reminder rescheduled for item $itemId at ${calendar.time}")
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error rescheduling daily reminder: ${e.message}")
        }
    }

    // Get default sound for one-time reminders from settings
    // If not set, gets system default and saves it to settings
    private fun getDefaultSound(context: Context): String? {
        try {
            val dbPath = context.getDatabasePath("settings.db")

            // Try to read from settings
            if (dbPath.exists()) {
                val db = SQLiteDatabase.openDatabase(
                    dbPath.absolutePath,
                    null,
                    SQLiteDatabase.OPEN_READONLY
                )

                val cursor = db.rawQuery(
                    "SELECT value FROM settings WHERE key = ?",
                    arrayOf("Default sound")
                )

                val result = if (cursor.moveToFirst()) {
                    val value = cursor.getString(0)
                    if (value.isNullOrEmpty()) null else value
                } else {
                    null
                }

                cursor.close()
                db.close()

                if (result != null) {
                    return result
                }
            }

            // No setting found - get system default notification sound
            val systemDefaultUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val systemDefaultString = systemDefaultUri?.toString()

            if (systemDefaultString != null) {
                // Save to settings for future use
                saveDefaultSound(context, systemDefaultString)
                Log.d("MemorizerApp", "Set system default sound: $systemDefaultString")
            }

            return systemDefaultString
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error getting default sound: ${e.message}")
            return null
        }
    }

    // Save default sound to settings
    private fun saveDefaultSound(context: Context, soundUri: String) {
        try {
            val dbPath = context.getDatabasePath("settings.db")
            val db = SQLiteDatabase.openOrCreateDatabase(dbPath.absolutePath, null)

            // Create table if not exists
            db.execSQL("CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)")

            // Insert or replace
            db.execSQL(
                "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                arrayOf("Default sound", soundUri)
            )

            db.close()
            Log.d("MemorizerApp", "Saved default sound to settings: $soundUri")
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error saving default sound: ${e.message}")
        }
    }

    // Get default sound for daily reminders from settings
    // If not set, gets system default and saves it to settings
    private fun getDefaultDailySound(context: Context): String? {
        try {
            val dbPath = context.getDatabasePath("settings.db")

            // Try to read from settings
            if (dbPath.exists()) {
                val db = SQLiteDatabase.openDatabase(
                    dbPath.absolutePath,
                    null,
                    SQLiteDatabase.OPEN_READONLY
                )

                val cursor = db.rawQuery(
                    "SELECT value FROM settings WHERE key = ?",
                    arrayOf("Default daily sound")
                )

                val result = if (cursor.moveToFirst()) {
                    val value = cursor.getString(0)
                    if (value.isNullOrEmpty()) null else value
                } else {
                    null
                }

                cursor.close()
                db.close()

                if (result != null) {
                    return result
                }
            }

            // No setting found - get system default notification sound
            val systemDefaultUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val systemDefaultString = systemDefaultUri?.toString()

            if (systemDefaultString != null) {
                // Save to settings for future use
                saveDefaultDailySound(context, systemDefaultString)
                Log.d("MemorizerApp", "Set system default daily sound: $systemDefaultString")
            }

            return systemDefaultString
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error getting default daily sound: ${e.message}")
            return null
        }
    }

    // Save default daily sound to settings
    private fun saveDefaultDailySound(context: Context, soundUri: String) {
        try {
            val dbPath = context.getDatabasePath("settings.db")
            val db = SQLiteDatabase.openOrCreateDatabase(dbPath.absolutePath, null)

            db.execSQL("CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)")

            db.execSQL(
                "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                arrayOf("Default daily sound", soundUri)
            )

            db.close()
            Log.d("MemorizerApp", "Saved default daily sound to settings: $soundUri")
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error saving default daily sound: ${e.message}")
        }
    }

    // Check if daily reminders are enabled in settings
    private fun isDailyRemindersEnabled(context: Context): Boolean {
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
                arrayOf("Enable daily reminders")
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
            Log.e("MemorizerApp", "Error checking if daily reminders enabled: ${e.message}")
            return true
        }
    }

    // Check if item has daily reminders active
    private fun isItemDailyActive(context: Context, itemId: Int): Boolean {
        return try {
            val dbPath = context.getDatabasePath("memorizer.db")
            if (!dbPath.exists()) return false

            val db = SQLiteDatabase.openDatabase(dbPath.absolutePath, null, SQLiteDatabase.OPEN_READONLY)

            val cursor = db.rawQuery(
                "SELECT daily FROM items WHERE id = ?",
                arrayOf(itemId.toString())
            )

            val isActive = if (cursor.moveToFirst()) {
                cursor.getInt(0) == 1
            } else {
                false
            }

            cursor.close()
            db.close()
            isActive
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error checking if item daily is active: ${e.message}")
            false
        }
    }

    // Convert sound path/uri to proper Uri for notification channel
    private fun getSoundUri(soundValue: String?): Uri? {
        if (soundValue == null) return null

        return if (soundValue.startsWith("/")) {
            // File path - convert to file:// URI
            Uri.fromFile(java.io.File(soundValue))
        } else {
            // Already a URI (content://, etc.)
            Uri.parse(soundValue)
        }
    }

    // Create notification channel for one-time reminders with sound from Settings
    private fun createReminderNotificationChannel(context: Context, soundValue: String?): String {
        // Always use hash-based channel ID (0 for null/system default)
        val channelId = "memorizer_reminder_${soundValue?.hashCode() ?: 0}"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelName = if (soundValue != null) "Reminders (Custom)" else "Reminders (System)"
            val channel = NotificationChannel(
                channelId,
                channelName,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "One-time reminders for Memorizer app"
                enableLights(true)
                enableVibration(true)
                setShowBadge(true)
                // Set custom sound for channel (null = system default)
                val soundUri = getSoundUri(soundValue)
                if (soundUri != null) {
                    val audioAttributes = android.media.AudioAttributes.Builder()
                        .setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION)
                        .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                    setSound(soundUri, audioAttributes)
                }
                Log.d("MemorizerApp", "Created reminder channel $channelId with sound: $soundValue")
            }
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
        return channelId
    }

    // Create notification channel for daily reminders with optional custom sound
    private fun createDailyNotificationChannel(context: Context, soundValue: String?): String {
        val channelId = if (soundValue != null) {
            // Create unique channel ID based on sound value hash
            "memorizer_daily_${soundValue.hashCode()}"
        } else {
            "memorizer_daily"
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // For file paths, sound is played manually (not via channel)
            val isFilePath = soundValue?.startsWith("/") == true
            val channelName = if (soundValue != null) "Daily Reminders (Custom)" else "Daily Reminders"
            val channel = NotificationChannel(
                channelId,
                channelName,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Daily reminders for Memorizer app"
                enableLights(true)
                enableVibration(true)
                setShowBadge(true)
                // Only set channel sound for content:// URIs (not file paths)
                if (!isFilePath) {
                    val soundUri = getSoundUri(soundValue)
                    if (soundUri != null) {
                        val audioAttributes = android.media.AudioAttributes.Builder()
                            .setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION)
                            .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build()
                        setSound(soundUri, audioAttributes)
                        Log.d("MemorizerApp", "Created channel $channelId with sound URI: $soundValue")
                    }
                } else {
                    // Disable default sound for file paths (will be played manually)
                    setSound(null, null)
                    Log.d("MemorizerApp", "Created channel $channelId for file sound: $soundValue (played manually)")
                }
            }
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
        return channelId
    }

    // Show daily notification
    private fun showDailyNotification(context: Context, itemId: Int, hour: Int, minute: Int, title: String, content: String, soundUri: String?, channelId: String) {
        try {
            val notificationIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                putExtra("notification_payload", itemId.toString())
            }

            // Use unique notification ID based on itemId, hour and minute
            val notificationId = itemId * 10000 + hour * 100 + minute

            val pendingIntent = PendingIntent.getActivity(
                context,
                notificationId,
                notificationIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Blue color for daily reminders
            val blueColor = 0xFF2196F3.toInt()

            val bigTextStyle = NotificationCompat.BigTextStyle()
                .bigText(content)
                .setBigContentTitle(title)

            // Use the channel with custom sound
            val builder = NotificationCompat.Builder(context, channelId)
                .setSmallIcon(R.drawable.notification_icon)
                .setContentTitle(title)
                .setContentText(content)
                .setStyle(bigTextStyle)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setColor(blueColor)
                .setColorized(true)

            // For Android < 8, set sound directly on notification
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                if (soundUri != null) {
                    builder.setSound(Uri.parse(soundUri))
                    builder.setDefaults(NotificationCompat.DEFAULT_VIBRATE or NotificationCompat.DEFAULT_LIGHTS)
                } else {
                    builder.setDefaults(NotificationCompat.DEFAULT_ALL)
                }
            }

            try {
                val notificationManager = NotificationManagerCompat.from(context)
                notificationManager.notify(notificationId, builder.build())
                Log.d("MemorizerApp", "Daily notification shown with ID: $notificationId, channel: $channelId")

                // For file paths, play sound manually (channel sounds don't work with file:// URIs)
                if (soundUri != null && soundUri.startsWith("/")) {
                    playSoundFile(context, soundUri)
                }
            } catch (se: SecurityException) {
                Log.e("MemorizerApp", "Security exception showing daily notification: ${se.message}")
            }

        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error showing daily notification: ${e.message}")
        }
    }

    // Play sound file manually for notifications (workaround for file:// URI restrictions)
    private fun playSoundFile(context: Context, filePath: String) {
        try {
            val mediaPlayer = android.media.MediaPlayer().apply {
                setDataSource(filePath)
                setAudioAttributes(
                    android.media.AudioAttributes.Builder()
                        .setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION)
                        .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                prepare()
                start()
                setOnCompletionListener { it.release() }
            }
            Log.d("MemorizerApp", "Playing sound file: $filePath")
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error playing sound file: ${e.message}")
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
                // Get item data from database
                val itemData = getItemData(context, itemId)
                val itemTitle = if (itemData.title.isNotEmpty()) "Reminder: ${itemData.title}" else title
                val itemContent = itemData.content.ifEmpty { body }

                // Get default sound from app settings (not from item)
                val defaultSound = getDefaultSound(context)

                // Check if fullscreen alert is enabled
                if (itemData.fullscreen == 1) {
                    launchFullscreenAlert(context, itemId, itemTitle, itemContent, defaultSound)
                } else {
                    // Create notification channel with sound from settings
                    val channelId = createReminderNotificationChannel(context, defaultSound)

                    // Show notification with the channel
                    showEventNotification(context, itemId, itemTitle, itemContent, itemId, channelId)

                    Log.d("MemorizerApp", "Specific reminder shown for item $itemId with channel $channelId, sound: $defaultSound")
                }
            } else {
                Log.d("MemorizerApp", "Item $itemId no longer exists or reminder disabled, skipping notification")
            }

        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error handling specific reminder: ${e.message}")
        }
    }

    // Data class for item data with sound and fullscreen
    data class ItemData(
        val title: String,
        val content: String,
        val sound: String?,
        val dailySound: String?,
        val hidden: Int,
        val fullscreen: Int
    )

    // Decode Base64 obfuscated text (same logic as Flutter's deobfuscateText)
    private fun deobfuscateText(encodedText: String): String {
        if (encodedText.isEmpty()) return encodedText
        return try {
            // Check if string is valid Base64
            if (encodedText.matches(Regex("^[A-Za-z0-9+/=]+$"))) {
                val decodedBytes = android.util.Base64.decode(encodedText, android.util.Base64.DEFAULT)
                String(decodedBytes, Charsets.UTF_8)
            } else {
                // If not Base64, return as is
                encodedText
            }
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error decoding text: ${e.message}")
            encodedText
        }
    }

    // Get item data from database including sound, daily_sound, hidden, and fullscreen
    private fun getItemData(context: Context, itemId: Int): ItemData {
        return try {
            val dbPath = context.getDatabasePath("memorizer.db")
            if (!dbPath.exists()) return ItemData("", "", null, null, 0, 0)

            val db = SQLiteDatabase.openDatabase(dbPath.absolutePath, null, SQLiteDatabase.OPEN_READONLY)

            val cursor = db.rawQuery(
                "SELECT title, content, sound, daily_sound, hidden, fullscreen FROM items WHERE id = ?",
                arrayOf(itemId.toString())
            )

            val result = if (cursor.moveToFirst()) {
                var title = cursor.getString(0) ?: ""
                var content = cursor.getString(1) ?: ""
                val sound = cursor.getString(2)
                val dailySound = cursor.getString(3)
                val hidden = cursor.getInt(4)
                val fullscreen = cursor.getInt(5)

                // Decode hidden items for notifications (always show readable text in notifications)
                if (hidden == 1) {
                    title = deobfuscateText(title)
                    content = deobfuscateText(content)
                }

                ItemData(title, content, sound, dailySound, hidden, fullscreen)
            } else {
                ItemData("", "", null, null, 0, 0)
            }

            cursor.close()
            db.close()
            result
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error getting item data: ${e.message}")
            ItemData("", "", null, null, 0, 0)
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

    // Launch fullscreen alert activity
    private fun launchFullscreenAlert(context: Context, itemId: Int, title: String, content: String, soundValue: String?) {
        try {
            val intent = Intent(context, FullScreenAlertActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                putExtra("itemId", itemId)
                putExtra("title", title)
                putExtra("content", content)
                putExtra("sound", soundValue)
            }
            context.startActivity(intent)
            Log.d("MemorizerApp", "Launched fullscreen alert for item $itemId")
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error launching fullscreen alert: ${e.message}")
            // Fallback to notification if fullscreen launch fails
            try {
                val channelId = createReminderNotificationChannel(context, soundValue)
                showEventNotification(context, itemId, title, content, itemId, channelId)
                Log.d("MemorizerApp", "Fallback: Showed notification instead of fullscreen alert")
            } catch (fallbackException: Exception) {
                Log.e("MemorizerApp", "Fallback notification also failed: ${fallbackException.message}")
            }
        }
    }

    private fun showEventNotification(context: Context, itemId: Int, title: String, content: String, notificationId: Int, channelId: String) {
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

            // Create notification with specified channel
            val builder = NotificationCompat.Builder(context, channelId)
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
                .setDefaults(NotificationCompat.DEFAULT_VIBRATE or NotificationCompat.DEFAULT_LIGHTS)

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
                    val hour = time?.let { it / 100 } ?: 9
                    val minute = time?.let { it % 100 } ?: 30

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

