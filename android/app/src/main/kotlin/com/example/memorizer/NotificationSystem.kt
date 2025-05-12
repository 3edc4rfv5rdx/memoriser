package com.example.memorizer

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ContentValues // Добавлен импорт ContentValues
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
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
 * Основная активность приложения.
 * Инициализирует Method Channel для связи с Flutter и настраивает уведомления.
 */
class MainActivity : FlutterActivity() {

    companion object {
        const val DEFAULT_NOTIFICATION_TIME = "08:00"
        private var methodChannel: MethodChannel? = null

        // Function to send message to Flutter
        fun checkEvents() {
            try {
                methodChannel?.invokeMethod("checkEvents", null)
                Log.d("MemorizerApp", "checkEvents method invoked")
            } catch (e: Exception) {
                Log.e("MemorizerApp", "Error invoking checkEvents: ${e.message}")
            }
        }
    }

    private lateinit var notificationService: NotificationService
    private lateinit var prefs: SharedPreferences

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Инициализируем SharedPreferences
        prefs = getSharedPreferences("memorizer_notifications", Context.MODE_PRIVATE)

        // Запрос необходимых разрешений
        requestRequiredPermissions()

        try {
            // Инициализируем сервис уведомлений
            notificationService = NotificationService(applicationContext)

            // Set up method channel
            methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.memorizer/notifications")
            methodChannel?.setMethodCallHandler(notificationService)
            Log.d("MemorizerApp", "Method channel initialized")

            // Проверяем, нужно ли восстановить напоминания
            checkAndRestoreReminders()

        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error configuring flutter engine: ${e.message}")
        }
    }

    private fun checkAndRestoreReminders() {
        // Проверяем, включены ли напоминания
        val remindersEnabled = prefs.getBoolean(NotificationService.PREF_REMINDER_ENABLED, false)

        if (remindersEnabled) {
            // Получаем сохраненные настройки напоминаний
            val reminderTime = prefs.getString(NotificationService.PREF_REMINDER_TIME, DEFAULT_NOTIFICATION_TIME)
                ?: DEFAULT_NOTIFICATION_TIME
            val reminderTitle = prefs.getString(NotificationService.PREF_REMINDER_TITLE, "") ?: ""
            val reminderBody = prefs.getString(NotificationService.PREF_REMINDER_BODY, "") ?: ""

            // Перепланируем напоминания
            notificationService.rescheduleRemindersAfterReboot()
            Log.d("MemorizerApp", "Reminders restored during app start for time: $reminderTime")
        }
    }

    private fun requestRequiredPermissions() {
        try {
            // Запрос разрешения на показ уведомлений для Android 13+
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                    Log.d("MemorizerApp", "Requesting POST_NOTIFICATIONS permission")
                    ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 100)
                } else {
                    Log.d("MemorizerApp", "POST_NOTIFICATIONS permission already granted")
                }
            }

            // Запрос разрешения на работу с точными будильниками для Android 12+
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (!canScheduleExactAlarms()) {
                    Log.d("MemorizerApp", "SCHEDULE_EXACT_ALARM permission not granted")
                    // На Android 12+ для этого разрешения нужно отправить пользователя в настройки
                    // Но для повторяющихся будильников это разрешение не обязательно
                } else {
                    Log.d("MemorizerApp", "SCHEDULE_EXACT_ALARM permission already granted")
                }
            }
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error requesting permissions: ${e.message}")
        }
    }

    // Проверка разрешения на работу с точными будильниками
    private fun canScheduleExactAlarms(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
            return alarmManager.canScheduleExactAlarms()
        }
        return true // На более старых версиях Android это разрешение не требуется
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)

        try {
            // Очищаем все уведомления при запуске приложения
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancelAll()

            // Проверяем, есть ли payload в intent
            if (intent.hasExtra("notification_payload")) {
                val payload = intent.getStringExtra("notification_payload")
                Log.d("MemorizerApp", "Notification clicked with payload: $payload")
                methodChannel?.invokeMethod("notificationClick", payload ?: "")
            } else {
                Log.d("MemorizerApp", "Intent received but no notification payload found")
            }
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error in onNewIntent: ${e.message}")
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode == 100) {
            // Проверяем массив на пустоту
            if (grantResults.isNotEmpty()) {
                when (grantResults[0]) {
                    PackageManager.PERMISSION_GRANTED -> {
                        Log.d("MemorizerApp", "POST_NOTIFICATIONS permission granted by user")
                        // Если разрешение получено, проверяем настройки напоминаний
                        checkAndRestoreReminders()
                    }
                    PackageManager.PERMISSION_DENIED -> {
                        Log.d("MemorizerApp", "POST_NOTIFICATIONS permission denied by user")
                        // Информируем Flutter, что разрешение не получено
                        methodChannel?.invokeMethod("permissionDenied", "notifications")
                    }
                    else -> {
                        Log.d("MemorizerApp", "Unexpected permission result: ${grantResults[0]}")
                    }
                }
            } else {
                // Массив может быть пустым, если пользователь отменил диалог запроса
                Log.d("MemorizerApp", "Permission request was cancelled")
            }
        }
    }
}

/**
 * Сервис для работы с уведомлениями.
 * Обрабатывает вызовы из Flutter и планирует напоминания.
 */
class NotificationService(private val context: Context) : MethodChannel.MethodCallHandler {
    private val channelId = "memorizer_channel"
    private val notificationManager = NotificationManagerCompat.from(context)
    private val prefs: SharedPreferences by lazy {
        context.getSharedPreferences("memorizer_notifications", Context.MODE_PRIVATE)
    }

    companion object {
        const val PREF_REMINDER_TIME = "reminder_time"
        const val PREF_REMINDER_ENABLED = "reminder_enabled"
        const val PREF_REMINDER_TITLE = "reminder_title"
        const val PREF_REMINDER_BODY = "reminder_body"
        const val REMINDER_REQUEST_CODE = 12345
    }

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
                val time = call.argument<String>("time") ?: MainActivity.DEFAULT_NOTIFICATION_TIME
                val title = call.argument<String>("title") ?: ""
                val body = call.argument<String>("body") ?: ""

                Log.d("MemorizerApp", "Schedule daily check requested for time: $time")

                // Проверяем формат времени
                if (!isValidTimeFormat(time)) {
                    Log.e("MemorizerApp", "Invalid time format: $time, using default")
                    // Используем значение по умолчанию
                    val defaultTime = MainActivity.DEFAULT_NOTIFICATION_TIME
                    saveReminderSettings(defaultTime, title, body, true)
                    scheduleDaily(defaultTime, title, body)
                } else {
                    // Сохраняем настройки напоминаний
                    saveReminderSettings(time, title, body, true)
                    // Планируем ежедневную проверку
                    scheduleDaily(time, title, body)
                }

                result.success(null)
            }
            "cancelAllNotifications" -> {
                cancelAllNotifications()
                // Сохраняем, что напоминания отключены
                saveReminderSettings(
                    prefs.getString(PREF_REMINDER_TIME, MainActivity.DEFAULT_NOTIFICATION_TIME) ?: MainActivity.DEFAULT_NOTIFICATION_TIME,
                    prefs.getString(PREF_REMINDER_TITLE, "") ?: "",
                    prefs.getString(PREF_REMINDER_BODY, "") ?: "",
                    false
                )
                result.success(null)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    // Проверка правильного формата времени HH:MM
    private fun isValidTimeFormat(time: String): Boolean {
        try {
            val parts = time.split(":")
            if (parts.size != 2) return false

            val hour = parts[0].toIntOrNull() ?: return false
            val minute = parts[1].toIntOrNull() ?: return false

            if (hour < 0 || hour > 23) return false
            if (minute < 0 || minute > 59) return false

            return true
        } catch (e: Exception) {
            return false
        }
    }

    private fun saveReminderSettings(time: String, title: String, body: String, isEnabled: Boolean) {
        prefs.edit().apply {
            putString(PREF_REMINDER_TIME, time)
            putString(PREF_REMINDER_TITLE, title)
            putString(PREF_REMINDER_BODY, body)
            putBoolean(PREF_REMINDER_ENABLED, isEnabled)
            apply()
        }

        // Также пробуем записать время в SQLite для отладки
        try {
            val dbPath = context.getDatabasePath("settings.db")
            if (dbPath.exists()) {
                val db = SQLiteDatabase.openDatabase(
                    dbPath.absolutePath,
                    null,
                    SQLiteDatabase.OPEN_READWRITE
                )

                // Проверяем существует ли запись
                val cursor = db.rawQuery(
                    "SELECT value FROM settings WHERE key = ?",
                    arrayOf("Notification time")
                )

                if (cursor.moveToFirst()) {
                    // Запись существует, обновляем значение через SQL запрос
                    db.execSQL(
                        "UPDATE settings SET value = ? WHERE key = ?",
                        arrayOf(time, "Notification time")
                    )
                    Log.d("MemorizerApp", "Updated SQLite record for Notification time: $time")
                }

                cursor.close()
                db.close()
            }
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error updating SQLite database: ${e.message}")
        }

        Log.d("MemorizerApp", "Saved reminder settings: time=$time, enabled=$isEnabled")
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

            // Показываем уведомление
            try {
                notificationManager.notify(id, builder.build())
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
            Log.d("MemorizerApp", "scheduleDaily called with timeString: '$timeString'")

            // Изначально используем переданное время
            var timeToUse = timeString

            // Если переданное время пустое или некорректное, ищем в базе данных
            if (timeToUse.isBlank() || !isValidTimeFormat(timeToUse)) {
                // Ищем только в SQLite базе данных с правильным ключом "Notification time"
                try {
                    val dbPath = context.getDatabasePath("settings.db")
                    if (dbPath.exists()) {
                        val db = SQLiteDatabase.openDatabase(
                            dbPath.absolutePath,
                            null,
                            SQLiteDatabase.OPEN_READONLY
                        )

                        // Запрашиваем значение с ключом "Notification time"
                        val cursor = db.rawQuery(
                            "SELECT value FROM settings WHERE key = ?",
                            arrayOf("Notification time")
                        )

                        if (cursor.moveToFirst()) {
                            val sqliteValue = cursor.getString(0)
                            if (!sqliteValue.isNullOrEmpty() && isValidTimeFormat(sqliteValue)) {
                                timeToUse = sqliteValue
                                Log.d("MemorizerApp", "Found valid time in SQLite: '$timeToUse'")
                            }
                        }

                        cursor.close()
                        db.close()
                    }
                } catch (e: Exception) {
                    Log.e("MemorizerApp", "Error reading from SQLite database: ${e.message}")
                }
            }

            // Если все равно не нашли валидное время, используем значение по умолчанию
            if (timeToUse.isBlank() || !isValidTimeFormat(timeToUse)) {
                timeToUse = MainActivity.DEFAULT_NOTIFICATION_TIME
                Log.d("MemorizerApp", "Using default time: '$timeToUse'")
            }

            // Parse time string (format: HH:MM)
            val parts = timeToUse.split(":")
            val hour = parts[0].toIntOrNull() ?: 8
            val minute = parts[1].toIntOrNull() ?: 0

            Log.d("MemorizerApp", "Scheduling daily notification at: $hour:$minute")

            // Create intent for the alarm
            val intent = Intent(context, NotificationReceiver::class.java).apply {
                action = "com.example.memorizer.CHECK_REMINDERS"
                putExtra("title", title)
                putExtra("body", body)
            }

            val pendingIntent = PendingIntent.getBroadcast(
                context,
                REMINDER_REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Set the alarm to trigger at the specified time
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val calendar = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, minute)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)

                // If time has already passed today, set for tomorrow
                if (timeInMillis <= System.currentTimeMillis()) {
                    add(Calendar.DAY_OF_YEAR, 1)
                }
            }

            Log.d("MemorizerApp", "Alarm scheduled for: ${calendar.time}")

            // Сохраняем настройки (включая использованное время)
            saveReminderSettings(timeToUse, title, body, true)

            // Сначала отменяем предыдущие будильники
            alarmManager.cancel(pendingIntent)

            // Устанавливаем повторяющийся будильник
            alarmManager.setRepeating(
                AlarmManager.RTC_WAKEUP,
                calendar.timeInMillis,
                AlarmManager.INTERVAL_DAY, // Повторять ежедневно
                pendingIntent
            )

            Log.d("MemorizerApp", "Daily alarm set successfully")
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error in scheduleDaily: ${e.message}")
            e.printStackTrace()
        }
    }

    fun rescheduleRemindersAfterReboot() {
        try {
            // Проверяем, включены ли напоминания
            val isEnabled = prefs.getBoolean(PREF_REMINDER_ENABLED, false)

            if (!isEnabled) {
                Log.d("MemorizerApp", "Reminders disabled, not rescheduling after reboot")
                return
            }

            // Получаем сохраненные настройки напоминаний
            val reminderTime = prefs.getString(PREF_REMINDER_TIME, MainActivity.DEFAULT_NOTIFICATION_TIME)
                ?: MainActivity.DEFAULT_NOTIFICATION_TIME
            val reminderTitle = prefs.getString(PREF_REMINDER_TITLE, "") ?: ""
            val reminderBody = prefs.getString(PREF_REMINDER_BODY, "") ?: ""

            // Перепланируем напоминания
            scheduleDaily(reminderTime, reminderTitle, reminderBody)
            Log.d("MemorizerApp", "Reminders rescheduled after reboot for time: $reminderTime")
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error rescheduling reminders after reboot: ${e.message}")
        }
    }

    private fun cancelAllNotifications() {
        try {
            notificationManager.cancelAll()

            // Cancel scheduled alarms
            val intent = Intent(context, NotificationReceiver::class.java)
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                REMINDER_REQUEST_CODE,
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

/**
 * BroadcastReceiver для восстановления запланированных напоминаний
 * после перезагрузки устройства
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.d("MemorizerApp", "Device rebooted, rescheduling notifications")

            try {
                // Восстановление запланированных напоминаний
                // Добавляем небольшую задержку, чтобы система успела полностью инициализироваться
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    val notificationService = NotificationService(context)
                    notificationService.rescheduleRemindersAfterReboot()
                    Log.d("MemorizerApp", "Reminders successfully rescheduled after boot")
                }, 5000) // Задержка 5 секунд
            } catch (e: Exception) {
                Log.e("MemorizerApp", "Error rescheduling reminders after boot: ${e.message}")
                e.printStackTrace()
            }
        }
    }
}

/**
 * BroadcastReceiver для обработки напоминаний.
 * Показывает уведомления о событиях, запланированных на сегодня.
 */
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
