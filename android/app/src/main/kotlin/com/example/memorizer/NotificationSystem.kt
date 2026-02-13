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
import android.os.Environment
import android.os.PowerManager
import android.provider.Settings
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

            // Request MANAGE_EXTERNAL_STORAGE for Android 11+ (needed for photo backup/restore)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                if (!Environment.isExternalStorageManager()) {
                    Log.d("MemorizerApp", "Requesting MANAGE_EXTERNAL_STORAGE permission")
                    val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                        data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
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
            "schedulePeriodReminder" -> {
                val itemId = call.argument<Int>("itemId") ?: 0
                val year = call.argument<Int>("year") ?: 0
                val month = call.argument<Int>("month") ?: 0
                val day = call.argument<Int>("day") ?: 0
                val hour = call.argument<Int>("hour") ?: 0
                val minute = call.argument<Int>("minute") ?: 0
                val title = call.argument<String>("title") ?: ""
                val body = call.argument<String>("body") ?: ""

                schedulePeriodReminder(itemId, year, month, day, hour, minute, title, body)
                result.success(true)
            }
            "cancelPeriodReminders" -> {
                val itemId = call.argument<Int>("itemId") ?: 0
                cancelPeriodReminders(itemId)
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

    // Media player for sound playback (companion for access from NotificationReceiver)
    companion object {
        var mediaPlayer: android.media.MediaPlayer? = null

        fun stopSoundStatic() {
            try {
                mediaPlayer?.let {
                    if (it.isPlaying) {
                        it.stop()
                    }
                    it.release()
                }
                mediaPlayer = null
            } catch (e: Exception) {
                Log.e("MemorizerApp", "Error stopping sound (static): ${e.message}")
            }
        }
    }

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
        stopSoundStatic()
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

            // Set time for next reminder (find next valid day from daysMask)
            // Spread conflicting times by 3 seconds based on itemId
            val calendar = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, minute)
                set(Calendar.SECOND, ((itemId ?: 0) % 20) * 3)
                set(Calendar.MILLISECOND, 0)
            }

            val timePassed = calendar.timeInMillis < System.currentTimeMillis()

            // Check if today matches daysMask
            val todayDayOfWeek = calendar.get(Calendar.DAY_OF_WEEK)
            val todayIndex = if (todayDayOfWeek == Calendar.SUNDAY) 6 else todayDayOfWeek - 2
            val todayInMask = (daysMask and (1 shl todayIndex)) != 0

            // If time hasn't passed and today is in mask, use today
            // Otherwise, search for next valid day
            if (timePassed || !todayInMask) {
                // Start search from tomorrow
                calendar.add(Calendar.DAY_OF_YEAR, 1)

                // Find next valid day that matches daysMask (search up to 7 days)
                var foundValidDay = false
                for (i in 0 until 7) {
                    val calendarDayOfWeek = calendar.get(Calendar.DAY_OF_WEEK)
                    val dayIndex = if (calendarDayOfWeek == Calendar.SUNDAY) 6 else calendarDayOfWeek - 2

                    if ((daysMask and (1 shl dayIndex)) != 0) {
                        // This day is in the mask
                        foundValidDay = true
                        break
                    }

                    // Try next day
                    calendar.add(Calendar.DAY_OF_YEAR, 1)
                }

                if (!foundValidDay) {
                    Log.e("MemorizerApp", "No valid day found in daysMask $daysMask for item $itemId")
                    return
                }
            }

            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

            // Check permission on Android 12+ (setAlarmClock works without permission, but log for info)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (!alarmManager.canScheduleExactAlarms()) {
                    Log.w("MemorizerApp", "SCHEDULE_EXACT_ALARM permission not granted (setAlarmClock should still work)")
                }
            }

            // Use setAlarmClock for guaranteed exact timing even in Doze mode
            // This is appropriate for user-scheduled daily reminders
            val alarmClockInfo = AlarmManager.AlarmClockInfo(
                calendar.timeInMillis,
                pendingIntent
            )
            alarmManager.setAlarmClock(alarmClockInfo, pendingIntent)

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

    // Schedule a single period reminder alarm for a specific date
    private fun schedulePeriodReminder(itemId: Int, year: Int, month: Int, day: Int, hour: Int, minute: Int, title: String, body: String) {
        try {
            Log.d("MemorizerApp", "Scheduling period reminder for item $itemId at $year-$month-$day $hour:$minute")

            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

            val intent = Intent(context, NotificationReceiver::class.java).apply {
                action = "com.example.memorizer.PERIOD_REMINDER"
                putExtra("itemId", itemId)
                putExtra("title", title)
                putExtra("body", body)
            }

            // requestCode must be unique per item + month + day
            val requestCode = itemId * 10000 + month * 100 + day
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                requestCode,
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

            if (calendar.timeInMillis > System.currentTimeMillis()) {
                // Use setAlarmClock for guaranteed delivery on Samsung (Freecess blocks setExactAndAllowWhileIdle)
                val alarmClockInfo = AlarmManager.AlarmClockInfo(
                    calendar.timeInMillis,
                    pendingIntent
                )
                alarmManager.setAlarmClock(alarmClockInfo, pendingIntent)
                Log.d("MemorizerApp", "Period reminder scheduled for item $itemId at ${calendar.time}")
            } else {
                Log.d("MemorizerApp", "Period reminder time is in the past for item $itemId day $day")
            }
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error scheduling period reminder: ${e.message}")
        }
    }

    // Cancel all period reminders for an item (all months x days)
    private fun cancelPeriodReminders(itemId: Int) {
        try {
            Log.d("MemorizerApp", "Cancelling all period reminders for item $itemId")
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

            for (month in 1..12) {
                for (day in 1..31) {
                    val intent = Intent(context, NotificationReceiver::class.java).apply {
                        action = "com.example.memorizer.PERIOD_REMINDER"
                    }
                    val requestCode = itemId * 10000 + month * 100 + day
                    val pendingIntent = PendingIntent.getBroadcast(
                        context,
                        requestCode,
                        intent,
                        PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
                    )
                    pendingIntent?.let {
                        alarmManager.cancel(it)
                        it.cancel()
                    }
                }
            }
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error cancelling period reminders: ${e.message}")
        }
    }

    // Schedule a specific reminder for individual item
    private fun scheduleSpecificReminder(itemId: Int, year: Int, month: Int, day: Int, hour: Int, minute: Int, title: String, body: String) {
        try {
            Log.d("MemorizerApp", "Scheduling specific reminder for item $itemId at $year-$month-$day $hour:$minute")

            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

            // Check permission on Android 12+
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (!alarmManager.canScheduleExactAlarms()) {
                    Log.e("MemorizerApp", "SCHEDULE_EXACT_ALARM permission not granted! Alarms may not fire.")
                    Log.e("MemorizerApp", "User needs to enable 'Alarms & reminders' in Settings > Apps > Memorizer")
                }
            }

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
                "com.example.memorizer.SNOOZED_REMINDER" -> {
                    // Handle snoozed reminder (no DB, just from intent)
                    handleSnoozedReminder(context, intent)
                    return
                }
                "com.example.memorizer.PERIOD_REMINDER" -> {
                    // Handle period reminder (same as specific - loads from DB)
                    handlePeriodReminder(context, intent)
                    return
                }
                "com.example.memorizer.STOP_SOUND" -> {
                    // Stop playing sound and dismiss notification
                    NotificationService.stopSoundStatic()
                    val notifId = intent.getIntExtra("notificationId", 0)
                    if (notifId != 0) {
                        NotificationManagerCompat.from(context).cancel(notifId)
                    }
                    return
                }
            }
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error in NotificationReceiver.onReceive: ${e.message}")
            e.printStackTrace()
        }
    }

    // Wake screen briefly for notification (when fullscreen alert is not used)
    private fun wakeScreen(context: Context) {
        try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!powerManager.isInteractive) {
                @Suppress("DEPRECATION")
                val wakeLock = powerManager.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                    PowerManager.ACQUIRE_CAUSES_WAKEUP or
                    PowerManager.ON_AFTER_RELEASE,
                    "memorizer:reminder"
                )
                wakeLock.acquire(5000) // Wake screen for 5 seconds
                Log.d("MemorizerApp", "Screen woken up for reminder")
            }
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error waking screen: ${e.message}")
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

            // Check if reminder is active
            if (itemData.active == 0) {
                Log.d("MemorizerApp", "Daily reminder for item $itemId is INACTIVE, skipping notification")
                rescheduleNextDailyReminder(context, itemId, hour, minute, daysMask, title, body)
                return
            }

            val itemTitle = if (itemData.title.isNotEmpty()) itemData.title else title
            val itemContent = itemData.content.ifEmpty { body }
            // Use item's custom sound, or fall back to default daily sound from settings
            val itemSound = itemData.dailySound ?: getDefaultDailySound(context)

            Log.d("MemorizerApp", "Daily reminder - itemId: $itemId, fullscreen: ${itemData.fullscreen}, active: ${itemData.active}")
            Log.d("MemorizerApp", "Sound: item=${itemData.dailySound}, final=$itemSound")

            // Check if fullscreen alert is enabled
            if (itemData.fullscreen == 1) {
                Log.d("MemorizerApp", "Fullscreen is ENABLED for daily reminder $itemId, launching fullscreen alert")
                launchFullscreenAlert(context, itemId, itemTitle, itemContent, itemSound, isDaily = true)
            } else {
                Log.d("MemorizerApp", "Fullscreen is DISABLED for daily reminder $itemId, showing notification")
                wakeScreen(context)
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

            // Find next day that matches daysMask
            val calendar = Calendar.getInstance().apply {
                // Start from tomorrow
                add(Calendar.DAY_OF_YEAR, 1)
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, minute)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }

            // Search for next valid day (up to 7 days ahead)
            var foundValidDay = false
            for (i in 0 until 7) {
                val calendarDayOfWeek = calendar.get(Calendar.DAY_OF_WEEK)
                val dayIndex = if (calendarDayOfWeek == Calendar.SUNDAY) 6 else calendarDayOfWeek - 2

                if ((daysMask and (1 shl dayIndex)) != 0) {
                    // This day is in the mask
                    foundValidDay = true
                    break
                }

                // Try next day
                calendar.add(Calendar.DAY_OF_YEAR, 1)
            }

            if (!foundValidDay) {
                Log.e("MemorizerApp", "No valid day found in daysMask $daysMask for item $itemId")
                return
            }

            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

            // Use setAlarmClock for guaranteed exact timing even in Doze mode
            val alarmClockInfo = AlarmManager.AlarmClockInfo(
                calendar.timeInMillis,
                pendingIntent
            )
            alarmManager.setAlarmClock(alarmClockInfo, pendingIntent)

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
                        .setUsage(android.media.AudioAttributes.USAGE_ALARM)
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
                            .setUsage(android.media.AudioAttributes.USAGE_ALARM)
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

            // Stop sound intent (for action button and swipe dismiss)
            val stopIntent = Intent(context, NotificationReceiver::class.java).apply {
                action = "com.example.memorizer.STOP_SOUND"
                putExtra("notificationId", notificationId)
            }
            val stopPendingIntent = PendingIntent.getBroadcast(
                context,
                notificationId + 900000,
                stopIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

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
                .setDeleteIntent(stopPendingIntent)
                .addAction(R.drawable.notification_icon, "Stop", stopPendingIntent)

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
            // Stop any currently playing sound first
            NotificationService.stopSoundStatic()
            NotificationService.mediaPlayer = android.media.MediaPlayer().apply {
                setDataSource(filePath)
                setAudioAttributes(
                    android.media.AudioAttributes.Builder()
                        .setUsage(android.media.AudioAttributes.USAGE_ALARM)
                        .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                prepare()
                start()
                setOnCompletionListener {
                    it.release()
                    NotificationService.mediaPlayer = null
                }
            }
            Log.d("MemorizerApp", "Playing sound file: $filePath")
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error playing sound file: ${e.message}")
        }
    }

    // Reschedule recurring reminder (yearly or monthly)
    private fun rescheduleRecurringReminder(context: Context, itemId: Int, itemData: ItemData) {
        try {
            if (itemData.date == null) {
                Log.e("MemorizerApp", "Cannot reschedule recurring reminder for item $itemId - no date")
                return
            }

            // Parse original date (YYYYMMDD)
            val originalYear = itemData.date / 10000
            val originalMonth = (itemData.date % 10000) / 100
            val originalDay = itemData.date % 100

            // Get time (HH and MM)
            val hour = itemData.time?.let { it / 100 } ?: 9
            val minute = itemData.time?.let { it % 100 } ?: 30

            // Calculate next occurrence
            val calendar = Calendar.getInstance()

            if (itemData.yearly == 1) {
                // Yearly: same month and day, next year
                calendar.set(Calendar.YEAR, calendar.get(Calendar.YEAR) + 1)
                calendar.set(Calendar.MONTH, originalMonth - 1)
                calendar.set(Calendar.DAY_OF_MONTH, originalDay)
                Log.d("MemorizerApp", "Rescheduling YEARLY reminder for item $itemId to next year")
            } else if (itemData.monthly == 1) {
                // Monthly: same day, next month (handle month overflow)
                calendar.add(Calendar.MONTH, 1)
                // Get max day in target month
                val maxDayInMonth = calendar.getActualMaximum(Calendar.DAY_OF_MONTH)
                // Use original day or last day of month if original day doesn't exist
                val targetDay = if (originalDay > maxDayInMonth) maxDayInMonth else originalDay
                calendar.set(Calendar.DAY_OF_MONTH, targetDay)
                Log.d("MemorizerApp", "Rescheduling MONTHLY reminder for item $itemId to next month (day $targetDay)")
            } else {
                Log.d("MemorizerApp", "Item $itemId is not recurring, skipping reschedule")
                return
            }

            calendar.set(Calendar.HOUR_OF_DAY, hour)
            calendar.set(Calendar.MINUTE, minute)
            calendar.set(Calendar.SECOND, 0)
            calendar.set(Calendar.MILLISECOND, 0)

            // Schedule the next occurrence
            val nextYear = calendar.get(Calendar.YEAR)
            val nextMonth = calendar.get(Calendar.MONTH) + 1
            val nextDay = calendar.get(Calendar.DAY_OF_MONTH)

            // Create intent for next reminder
            val intent = Intent(context, NotificationReceiver::class.java).apply {
                action = "com.example.memorizer.SPECIFIC_REMINDER"
                putExtra("itemId", itemId)
                putExtra("title", itemData.title ?: "")
                putExtra("body", itemData.content ?: "")
            }

            val pendingIntent = PendingIntent.getBroadcast(
                context,
                itemId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

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

            // Update date in database for next occurrence
            try {
                val dbPath = context.getDatabasePath("memorizer.db")
                val db = SQLiteDatabase.openDatabase(dbPath.absolutePath, null, SQLiteDatabase.OPEN_READWRITE)

                val newDate = nextYear * 10000 + nextMonth * 100 + nextDay
                val values = ContentValues().apply {
                    put("date", newDate)
                }
                db.update("items", values, "id = ?", arrayOf(itemId.toString()))
                db.close()

                Log.d("MemorizerApp", "Updated database date for item $itemId to $newDate")
            } catch (dbError: Exception) {
                Log.e("MemorizerApp", "Error updating database date: ${dbError.message}")
            }

            Log.d("MemorizerApp", "Recurring reminder rescheduled for item $itemId: $nextYear-$nextMonth-$nextDay $hour:$minute")

        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error rescheduling recurring reminder: ${e.message}")
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
                // Get item data from database
                val itemData = getItemData(context, itemId)

                // Check if reminder is active
                if (itemData.active == 0) {
                    Log.d("MemorizerApp", "Specific reminder for item $itemId is INACTIVE, skipping notification")
                    return
                }

                val itemTitle = if (itemData.title.isNotEmpty()) itemData.title else title
                val itemContent = itemData.content.ifEmpty { body }

                // Get default sound from app settings (not from item)
                val defaultSound = getDefaultSound(context)

                Log.d("MemorizerApp", "Specific reminder - itemId: $itemId, fullscreen: ${itemData.fullscreen}, active: ${itemData.active}, yearly: ${itemData.yearly}, monthly: ${itemData.monthly}")

                // Check if fullscreen alert is enabled
                if (itemData.fullscreen == 1) {
                    Log.d("MemorizerApp", "Fullscreen is ENABLED for specific reminder $itemId, launching fullscreen alert")
                    launchFullscreenAlert(context, itemId, itemTitle, itemContent, defaultSound)
                } else {
                    Log.d("MemorizerApp", "Fullscreen is DISABLED for specific reminder $itemId, showing notification")
                    wakeScreen(context)
                    // Create notification channel with sound from settings
                    val channelId = createReminderNotificationChannel(context, defaultSound)

                    // Show notification with the channel
                    showEventNotification(context, itemId, itemTitle, itemContent, itemId, channelId)

                    Log.d("MemorizerApp", "Specific reminder shown for item $itemId with channel $channelId, sound: $defaultSound")
                }

                // Reschedule if yearly or monthly
                if (itemData.yearly == 1 || itemData.monthly == 1) {
                    rescheduleRecurringReminder(context, itemId, itemData)
                }
            } else {
                Log.d("MemorizerApp", "Item $itemId no longer exists or reminder disabled, skipping notification")
            }

        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error handling specific reminder: ${e.message}")
        }
    }

    // Handle snoozed reminder - use data from intent, no DB lookup
    private fun handleSnoozedReminder(context: Context, intent: Intent) {
        try {
            Log.d("MemorizerApp", "=== SNOOZED REMINDER FIRED ===")

            val itemId = intent.getIntExtra("itemId", 0)
            val title = intent.getStringExtra("title") ?: "Memorizer"
            val content = intent.getStringExtra("content") ?: ""
            val soundValue = intent.getStringExtra("sound")

            Log.d("MemorizerApp", "Snooze fired at: ${java.util.Date()}")
            Log.d("MemorizerApp", "Data: itemId=$itemId, title=$title")

            // Always show fullscreen alert with data from intent (no DB check)
            launchFullscreenAlert(context, itemId, title, content, soundValue)

        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error handling snoozed reminder: ${e.message}")
            e.printStackTrace()
        }
    }

    // Handle period reminder - loads item from DB, shows notification/fullscreen
    private fun handlePeriodReminder(context: Context, intent: Intent) {
        try {
            val itemId = intent.getIntExtra("itemId", 0)
            Log.d("MemorizerApp", "Handling period reminder for item $itemId")

            // Check if reminders are enabled
            if (!isRemindersEnabled(context)) {
                Log.d("MemorizerApp", "Reminders are disabled, skipping period reminder")
                return
            }

            if (isItemStillActive(context, itemId)) {
                val itemData = getItemData(context, itemId)

                if (itemData.active == 0) {
                    Log.d("MemorizerApp", "Period reminder for item $itemId is INACTIVE, skipping")
                    return
                }

                val itemTitle = if (itemData.title.isNotEmpty()) itemData.title else "Reminder"
                val itemContent = itemData.content
                // Use item's custom sound, or fall back to default sound from settings
                val itemSound = itemData.sound ?: getDefaultSound(context)

                Log.d("MemorizerApp", "Period reminder - itemId: $itemId, fullscreen: ${itemData.fullscreen}")
                Log.d("MemorizerApp", "Sound: item=${itemData.sound}, final=$itemSound")

                if (itemData.fullscreen == 1) {
                    Log.d("MemorizerApp", "Fullscreen is ENABLED for period reminder $itemId")
                    launchFullscreenAlert(context, itemId, itemTitle, itemContent, itemSound)
                } else {
                    Log.d("MemorizerApp", "Showing notification for period reminder $itemId")
                    wakeScreen(context)
                    val channelId = createReminderNotificationChannel(context, itemSound)
                    showEventNotification(context, itemId, itemTitle, itemContent, itemId, channelId)
                }
            } else {
                Log.d("MemorizerApp", "Item $itemId no longer exists, skipping period reminder")
            }
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error handling period reminder: ${e.message}")
        }
    }

    // Data class for item data with sound, fullscreen, active, yearly, monthly
    data class ItemData(
        val title: String,
        val content: String,
        val sound: String?,
        val dailySound: String?,
        val hidden: Int,
        val fullscreen: Int,
        val active: Int,
        val yearly: Int,
        val monthly: Int,
        val date: Int?,
        val time: Int?
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

    // Get item data from database including sound, daily_sound, hidden, fullscreen, active, yearly, monthly, date, time
    private fun getItemData(context: Context, itemId: Int): ItemData {
        return try {
            val dbPath = context.getDatabasePath("memorizer.db")
            if (!dbPath.exists()) return ItemData("", "", null, null, 0, 0, 1, 0, 0, null, null)

            val db = SQLiteDatabase.openDatabase(dbPath.absolutePath, null, SQLiteDatabase.OPEN_READONLY)

            val cursor = db.rawQuery(
                "SELECT title, content, sound, daily_sound, hidden, fullscreen, active, yearly, monthly, date, time FROM items WHERE id = ?",
                arrayOf(itemId.toString())
            )

            val result = if (cursor.moveToFirst()) {
                var title = cursor.getString(0) ?: ""
                var content = cursor.getString(1) ?: ""
                val sound = cursor.getString(2)
                val dailySound = cursor.getString(3)
                val hidden = cursor.getInt(4)
                val fullscreen = cursor.getInt(5)
                val active = cursor.getInt(6)
                val yearly = cursor.getInt(7)
                val monthly = cursor.getInt(8)
                val date = if (cursor.isNull(9)) null else cursor.getInt(9)
                val time = if (cursor.isNull(10)) null else cursor.getInt(10)

                Log.d("MemorizerApp", "getItemData($itemId): fullscreen=$fullscreen, active=$active, yearly=$yearly, monthly=$monthly, title=$title")

                // Decode hidden items for notifications (always show readable text in notifications)
                if (hidden == 1) {
                    title = deobfuscateText(title)
                    content = deobfuscateText(content)
                }

                ItemData(title, content, sound, dailySound, hidden, fullscreen, active, yearly, monthly, date, time)
            } else {
                Log.d("MemorizerApp", "getItemData($itemId): Item not found in database")
                ItemData("", "", null, null, 0, 0, 1, 0, 0, null, null)
            }

            cursor.close()
            db.close()
            result
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error getting item data: ${e.message}")
            ItemData("", "", null, null, 0, 0, 1, 0, 0, null, null)
        }
    }

    // Check if item is still active in database
    private fun isItemStillActive(context: Context, itemId: Int): Boolean {
        return try {
            val dbPath = context.getDatabasePath("memorizer.db")
            if (!dbPath.exists()) return false

            val db = SQLiteDatabase.openDatabase(dbPath.absolutePath, null, SQLiteDatabase.OPEN_READONLY)

            val cursor = db.rawQuery(
                "SELECT remind, period FROM items WHERE id = ?",
                arrayOf(itemId.toString())
            )

            val isActive = if (cursor.moveToFirst()) {
                cursor.getInt(0) == 1 || cursor.getInt(1) == 1 // remind or period must be enabled
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

    // Launch fullscreen alert activity using full-screen intent notification
    private fun launchFullscreenAlert(context: Context, itemId: Int, title: String, content: String, soundValue: String?, isDaily: Boolean = false) {
        try {
            // Check if we can use full-screen intents (Android 10+)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                if (!notificationManager.canUseFullScreenIntent()) {
                    Log.w("MemorizerApp", "Cannot use full-screen intent - permission not granted")
                }
            }
            // Create intent for the fullscreen activity
            val fullScreenIntent = Intent(context, FullScreenAlertActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                putExtra("itemId", itemId)
                putExtra("title", title)
                putExtra("content", content)
                putExtra("sound", soundValue)
                // Pass translations for UI labels (add punctuation programmatically)
                putExtra("label_reminder", translate(context, "Reminder") + ":")
                putExtra("label_postpone", translate(context, "Postpone for") + ":")
                putExtra("label_min", translate(context, "min"))
                putExtra("label_hour", translate(context, "hour"))
                putExtra("label_hours", translate(context, "hours"))
                putExtra("label_day", translate(context, "day"))
                putExtra("isDaily", isDaily)
            }

            val fullScreenPendingIntent = PendingIntent.getActivity(
                context,
                itemId,
                fullScreenIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Create notification channel for fullscreen alerts (without sound - sound plays in Activity)
            val channelId = "fullscreen_alerts"
            val channel = NotificationChannel(
                channelId,
                "Fullscreen Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Fullscreen reminder alerts"
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null) // No sound in notification - Activity will play it
                setBypassDnd(true)
                lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
            }

            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)

            // Build notification with full-screen intent (no sound - Activity plays it)
            val notification = NotificationCompat.Builder(context, channelId)
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentTitle(title)
                .setContentText(content)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setFullScreenIntent(fullScreenPendingIntent, true)
                .setAutoCancel(true)
                .setOngoing(false)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setSound(null) // No sound - Activity will play it
                .build()

            notificationManager.notify(itemId, notification)

            // Note: Notification will be cancelled by FullScreenAlertActivity when it opens
            // Don't auto-cancel here to avoid interrupting Activity startup

            Log.d("MemorizerApp", "Launched fullscreen alert via notification for item $itemId")
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

            // Stop sound intent (for action button and swipe dismiss)
            val stopIntent = Intent(context, NotificationReceiver::class.java).apply {
                action = "com.example.memorizer.STOP_SOUND"
                putExtra("notificationId", notificationId)
            }
            val stopPendingIntent = PendingIntent.getBroadcast(
                context,
                notificationId + 900000,
                stopIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

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
                .setDeleteIntent(stopPendingIntent)
                .addAction(R.drawable.notification_icon, "Stop", stopPendingIntent)

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

    // Get current language from settings
    private fun getCurrentLanguage(context: Context): String {
        return try {
            val dbPath = context.getDatabasePath("settings.db")
            if (!dbPath.exists()) return "en"

            val db = SQLiteDatabase.openDatabase(dbPath.absolutePath, null, SQLiteDatabase.OPEN_READONLY)
            val cursor = db.rawQuery("SELECT value FROM settings WHERE key = ?", arrayOf("Language"))

            val lang = if (cursor.moveToFirst()) {
                cursor.getString(0) ?: "en"
            } else {
                "en"
            }

            cursor.close()
            db.close()
            lang
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error getting language: ${e.message}")
            "en"
        }
    }

    // Translation function - reads from assets/locales.json
    private fun translate(context: Context, key: String): String {
        return try {
            val lang = getCurrentLanguage(context)

            // Read locales.json from assets
            val json = context.assets.open("flutter_assets/assets/locales.json")
                .bufferedReader().use { it.readText() }

            val jsonObject = org.json.JSONObject(json)

            // Get translation for key and language
            if (jsonObject.has(key)) {
                val translations = jsonObject.getJSONObject(key)
                if (translations.has(lang)) {
                    translations.getString(lang)
                } else {
                    key // Fallback to key if language not found
                }
            } else {
                key // Fallback to key if key not found
            }
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error translating '$key': ${e.message}")
            key // Fallback to key on error
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

            // Also reschedule daily reminders (check if daily reminders are enabled)
            var rescheduledDailyCount = 0
            if (isDailyRemindersEnabled(context)) {
                val dailyCursor = db.rawQuery(
                    "SELECT id, title, daily_times, daily_days FROM items WHERE daily = 1 AND active = 1",
                    null
                )

                while (dailyCursor.moveToNext()) {
                    try {
                        val itemId = dailyCursor.getInt(0)
                        val title = dailyCursor.getString(1) ?: ""
                        val dailyTimes = dailyCursor.getString(2) ?: ""
                        val dailyDays = dailyCursor.getInt(3)

                        // Parse times from JSON array format: ["06:33","18:33"] or ["16:56"]
                        val cleanedTimes = dailyTimes
                            .replace("[", "")
                            .replace("]", "")
                            .replace("\"", "")
                        val times = cleanedTimes.split(",").filter { it.isNotBlank() }

                        for (timeStr in times) {
                            val parts = timeStr.trim().split(":")
                            if (parts.size == 2) {
                                val hour = parts[0].toIntOrNull() ?: continue
                                val minute = parts[1].toIntOrNull() ?: continue

                                scheduleDailyReminderInBootReceiver(
                                    context,
                                    itemId,
                                    hour,
                                    minute,
                                    dailyDays,
                                    title
                                )

                                rescheduledDailyCount++
                            }
                        }
                    } catch (e: Exception) {
                        Log.e("MemorizerApp", "Error rescheduling daily item: ${e.message}")
                    }
                }

                dailyCursor.close()
                Log.d("MemorizerApp", "Rescheduled $rescheduledDailyCount daily reminders after boot")
            } else {
                Log.d("MemorizerApp", "Daily reminders are disabled, not rescheduling daily reminders after boot")
            }

            // Reschedule yearly reminders
            val yearlyCursor = db.rawQuery(
                "SELECT id, title, content, date, time FROM items WHERE yearly = 1 AND active = 1",
                null
            )

            var rescheduledYearlyCount = 0

            while (yearlyCursor.moveToNext()) {
                try {
                    val itemId = yearlyCursor.getInt(0)
                    val title = yearlyCursor.getString(1) ?: ""
                    val content = yearlyCursor.getString(2) ?: ""
                    val date = yearlyCursor.getInt(3)
                    val time = if (yearlyCursor.isNull(4)) null else yearlyCursor.getInt(4)

                    // Parse date (YYYYMMDD)
                    val month = (date % 10000) / 100
                    val day = date % 100

                    // Parse time or use default
                    val hour = time?.let { it / 100 } ?: 9
                    val minute = time?.let { it % 100 } ?: 30

                    // Find next yearly occurrence
                    val calendar = Calendar.getInstance()
                    calendar.set(Calendar.MONTH, month - 1)
                    calendar.set(Calendar.DAY_OF_MONTH, day)
                    calendar.set(Calendar.HOUR_OF_DAY, hour)
                    calendar.set(Calendar.MINUTE, minute)
                    calendar.set(Calendar.SECOND, 0)
                    calendar.set(Calendar.MILLISECOND, 0)

                    // If this year's date passed, schedule for next year
                    if (calendar.timeInMillis < System.currentTimeMillis()) {
                        calendar.add(Calendar.YEAR, 1)
                    }

                    scheduleSpecificReminder(
                        context,
                        itemId,
                        calendar.get(Calendar.YEAR),
                        month,
                        day,
                        hour,
                        minute,
                        title,
                        content
                    )

                    rescheduledYearlyCount++
                } catch (e: Exception) {
                    Log.e("MemorizerApp", "Error rescheduling yearly item: ${e.message}")
                }
            }

            yearlyCursor.close()

            // Reschedule monthly reminders
            val monthlyCursor = db.rawQuery(
                "SELECT id, title, content, date, time FROM items WHERE monthly = 1 AND active = 1",
                null
            )

            var rescheduledMonthlyCount = 0

            while (monthlyCursor.moveToNext()) {
                try {
                    val itemId = monthlyCursor.getInt(0)
                    val title = monthlyCursor.getString(1) ?: ""
                    val content = monthlyCursor.getString(2) ?: ""
                    val date = monthlyCursor.getInt(3)
                    val time = if (monthlyCursor.isNull(4)) null else monthlyCursor.getInt(4)

                    // Parse date (YYYYMMDD) - use day of month
                    val day = date % 100

                    // Parse time or use default
                    val hour = time?.let { it / 100 } ?: 9
                    val minute = time?.let { it % 100 } ?: 30

                    // Find next monthly occurrence
                    val calendar = Calendar.getInstance()
                    // Handle month overflow: use min of original day and max day in current month
                    val maxDayInMonth = calendar.getActualMaximum(Calendar.DAY_OF_MONTH)
                    val targetDay = if (day > maxDayInMonth) maxDayInMonth else day
                    calendar.set(Calendar.DAY_OF_MONTH, targetDay)
                    calendar.set(Calendar.HOUR_OF_DAY, hour)
                    calendar.set(Calendar.MINUTE, minute)
                    calendar.set(Calendar.SECOND, 0)
                    calendar.set(Calendar.MILLISECOND, 0)

                    // If this month's date passed, schedule for next month
                    if (calendar.timeInMillis < System.currentTimeMillis()) {
                        calendar.add(Calendar.MONTH, 1)
                        // Re-check day validity in next month
                        val maxDayInNextMonth = calendar.getActualMaximum(Calendar.DAY_OF_MONTH)
                        val targetDayNext = if (day > maxDayInNextMonth) maxDayInNextMonth else day
                        calendar.set(Calendar.DAY_OF_MONTH, targetDayNext)
                    }

                    scheduleSpecificReminder(
                        context,
                        itemId,
                        calendar.get(Calendar.YEAR),
                        calendar.get(Calendar.MONTH) + 1,
                        day,
                        hour,
                        minute,
                        title,
                        content
                    )

                    rescheduledMonthlyCount++
                } catch (e: Exception) {
                    Log.e("MemorizerApp", "Error rescheduling monthly item: ${e.message}")
                }
            }

            monthlyCursor.close()

            // Reschedule period reminders
            var rescheduledPeriodCount = 0
            val periodCursor = db.rawQuery(
                "SELECT id, title, date, time, period_to, period_days FROM items WHERE period = 1 AND active = 1",
                null
            )

            while (periodCursor.moveToNext()) {
                try {
                    val itemId = periodCursor.getInt(0)
                    val title = periodCursor.getString(1) ?: ""
                    val dateFrom = periodCursor.getInt(2)
                    val time = if (periodCursor.isNull(3)) null else periodCursor.getInt(3)
                    val dateTo = periodCursor.getInt(4)
                    val periodDays = periodCursor.getInt(5)

                    val hour = time?.let { it / 100 } ?: 9
                    val minute = time?.let { it % 100 } ?: 30

                    val isMonthly = dateFrom in 1..31
                    val dates = calculatePeriodDatesInBoot(dateFrom, dateTo, periodDays, isMonthly)

                    for (date in dates) {
                        schedulePeriodReminderInBoot(context, itemId, date[0], date[1], date[2], hour, minute, title)
                    }

                    rescheduledPeriodCount++
                } catch (e: Exception) {
                    Log.e("MemorizerApp", "Error rescheduling period item: ${e.message}")
                }
            }

            periodCursor.close()
            db.close()

            Log.d("MemorizerApp", "Rescheduled after reboot: $rescheduledCount specific, $rescheduledDailyCount daily, $rescheduledYearlyCount yearly, $rescheduledMonthlyCount monthly, $rescheduledPeriodCount period reminders")
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error in rescheduleAllReminders: ${e.message}")
        }
    }

    private fun scheduleDailyReminderInBootReceiver(
        context: Context,
        itemId: Int,
        hour: Int,
        minute: Int,
        daysMask: Int,
        title: String
    ) {
        try {
            val intent = Intent(context, NotificationReceiver::class.java).apply {
                action = "com.example.memorizer.DAILY_REMINDER"
                putExtra("itemId", itemId)
                putExtra("hour", hour)
                putExtra("minute", minute)
                putExtra("daysMask", daysMask)
                putExtra("title", title)
                putExtra("body", "")
            }

            val requestCode = itemId * 10000 + hour * 100 + minute

            val pendingIntent = PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Find next valid day from daysMask
            val calendar = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, minute)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }

            val timePassed = calendar.timeInMillis < System.currentTimeMillis()

            // Check if today matches daysMask
            val todayDayOfWeek = calendar.get(Calendar.DAY_OF_WEEK)
            val todayIndex = if (todayDayOfWeek == Calendar.SUNDAY) 6 else todayDayOfWeek - 2
            val todayInMask = (daysMask and (1 shl todayIndex)) != 0

            // If time hasn't passed and today is in mask, use today
            // Otherwise, search for next valid day
            if (timePassed || !todayInMask) {
                // Start search from tomorrow
                calendar.add(Calendar.DAY_OF_YEAR, 1)

                // Find next valid day that matches daysMask (search up to 7 days)
                var foundValidDay = false
                for (i in 0 until 7) {
                    val calendarDayOfWeek = calendar.get(Calendar.DAY_OF_WEEK)
                    val dayIndex = if (calendarDayOfWeek == Calendar.SUNDAY) 6 else calendarDayOfWeek - 2

                    if ((daysMask and (1 shl dayIndex)) != 0) {
                        // This day is in the mask
                        foundValidDay = true
                        break
                    }

                    // Try next day
                    calendar.add(Calendar.DAY_OF_YEAR, 1)
                }

                if (!foundValidDay) {
                    Log.e("MemorizerApp", "No valid day found in daysMask $daysMask for item $itemId in boot receiver")
                    return
                }
            }

            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

            // Use setAlarmClock for guaranteed exact timing even in Doze mode
            val alarmClockInfo = AlarmManager.AlarmClockInfo(
                calendar.timeInMillis,
                pendingIntent
            )
            alarmManager.setAlarmClock(alarmClockInfo, pendingIntent)

            Log.d("MemorizerApp", "Daily reminder rescheduled in boot receiver for item $itemId at ${calendar.time}")
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error scheduling daily reminder in boot receiver: ${e.message}")
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
                putExtra("title", title)
                putExtra("body", body)
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

    // Schedule a single period reminder alarm in BootReceiver
    private fun schedulePeriodReminderInBoot(
        context: Context,
        itemId: Int,
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        title: String
    ) {
        try {
            val intent = Intent(context, NotificationReceiver::class.java).apply {
                action = "com.example.memorizer.PERIOD_REMINDER"
                putExtra("itemId", itemId)
                putExtra("title", title)
                putExtra("body", "")
            }

            val requestCode = itemId * 10000 + month * 100 + day
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                requestCode,
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
                // Use setAlarmClock for guaranteed delivery on Samsung
                val alarmClockInfo = AlarmManager.AlarmClockInfo(
                    calendar.timeInMillis,
                    pendingIntent
                )
                alarmManager.setAlarmClock(alarmClockInfo, pendingIntent)
            }
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error scheduling period reminder in boot: ${e.message}")
        }
    }

    // Calculate valid period dates for BootReceiver (returns list of [year, month, day])
    private fun calculatePeriodDatesInBoot(dateFrom: Int, dateTo: Int, daysMask: Int, isMonthly: Boolean): List<IntArray> {
        val result = mutableListOf<IntArray>()

        if (isMonthly) {
            for (offset in 0..1) {
                val baseCalendar = Calendar.getInstance()
                baseCalendar.add(Calendar.MONTH, offset)
                baseCalendar.set(Calendar.DAY_OF_MONTH, 1)

                val year = baseCalendar.get(Calendar.YEAR)
                val month = baseCalendar.get(Calendar.MONTH) + 1
                val daysInMonth = baseCalendar.getActualMaximum(Calendar.DAY_OF_MONTH)
                val startDay = dateFrom.coerceIn(1, daysInMonth)
                val endDay = dateTo.coerceIn(1, daysInMonth)

                if (startDay <= endDay) {
                    for (d in startDay..endDay) {
                        if (isDayInMaskBoot(year, month, d, daysMask)) {
                            result.add(intArrayOf(year, month, d))
                        }
                    }
                } else {
                    for (d in startDay..daysInMonth) {
                        if (isDayInMaskBoot(year, month, d, daysMask)) {
                            result.add(intArrayOf(year, month, d))
                        }
                    }
                    val nextCal = Calendar.getInstance()
                    nextCal.set(Calendar.YEAR, year)
                    nextCal.set(Calendar.MONTH, month)
                    nextCal.set(Calendar.DAY_OF_MONTH, 1)
                    val nextYear = nextCal.get(Calendar.YEAR)
                    val nextMonth = nextCal.get(Calendar.MONTH) + 1
                    val nextDaysInMonth = nextCal.getActualMaximum(Calendar.DAY_OF_MONTH)
                    for (d in 1..dateTo.coerceIn(1, nextDaysInMonth)) {
                        if (isDayInMaskBoot(nextYear, nextMonth, d, daysMask)) {
                            result.add(intArrayOf(nextYear, nextMonth, d))
                        }
                    }
                }
            }
        } else {
            val fromYear = dateFrom / 10000
            val fromMonth = (dateFrom % 10000) / 100
            val fromDay = dateFrom % 100
            val toYear = dateTo / 10000
            val toMonth = (dateTo % 10000) / 100
            val toDay = dateTo % 100

            val calendar = Calendar.getInstance()
            calendar.set(fromYear, fromMonth - 1, fromDay)
            val toCal = Calendar.getInstance()
            toCal.set(toYear, toMonth - 1, toDay)

            while (!calendar.after(toCal)) {
                val y = calendar.get(Calendar.YEAR)
                val m = calendar.get(Calendar.MONTH) + 1
                val d = calendar.get(Calendar.DAY_OF_MONTH)
                if (isDayInMaskBoot(y, m, d, daysMask)) {
                    result.add(intArrayOf(y, m, d))
                }
                calendar.add(Calendar.DAY_OF_YEAR, 1)
            }
        }

        return result
    }

    // Check if weekday is in daysMask (bit 0=Mon, bit 6=Sun)
    private fun isDayInMaskBoot(year: Int, month: Int, day: Int, daysMask: Int): Boolean {
        val calendar = Calendar.getInstance()
        calendar.set(year, month - 1, day)
        val dayOfWeek = calendar.get(Calendar.DAY_OF_WEEK)
        val bitIndex = if (dayOfWeek == Calendar.SUNDAY) 6 else dayOfWeek - 2
        return (daysMask and (1 shl bitIndex)) != 0
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

    private fun isDailyRemindersEnabled(context: Context): Boolean {
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
                arrayOf("Enable daily reminders")
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
            Log.e("MemorizerApp", "Error checking if daily reminders enabled: ${e.message}")
            return true
        }
    }
}

