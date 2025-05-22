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
            } catch (e: Exception) {
                Log.e("MemorizerApp", "Error invoking checkEvents: ${e.message}")
            }
        }
    }

    private lateinit var notificationService: NotificationService

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        try {
            // Запрос необходимых разрешений
            requestRequiredPermissions()

            // Инициализируем сервис уведомлений
            notificationService = NotificationService(applicationContext)

            // Настраиваем канал связи с Flutter
            methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.memorizer/notifications")
            methodChannel?.setMethodCallHandler(notificationService)

            // Проверяем настройки уведомлений и планируем задачу
            notificationService.restoreNotificationSchedule()
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error configuring flutter engine: ${e.message}")
        }
    }

    private fun requestRequiredPermissions() {
        try {
            // Запрос разрешения на показ уведомлений для Android 13+
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
            // Очищаем все уведомления при запуске приложения
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancelAll()

            // Проверяем, есть ли payload в intent
            if (intent.hasExtra("notification_payload")) {
                val payload = intent.getStringExtra("notification_payload")
                methodChannel?.invokeMethod("notificationClick", payload ?: "")
            }
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error in onNewIntent: ${e.message}")
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode == 100 && grantResults.isNotEmpty()) {
            if (grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                // Если разрешение получено, восстанавливаем планирование уведомлений
                notificationService.restoreNotificationSchedule()
            } else {
                // Информируем Flutter, что разрешение не получено
                methodChannel?.invokeMethod("permissionDenied", "notifications")
            }
        }
    }
}


/**
 * Сервис для работы с уведомлениями.
 * Обрабатывает вызовы из Flutter и планирует ежедневные проверки.
 */
class NotificationService(private val context: Context) : MethodChannel.MethodCallHandler {
    private val channelId = "memorizer_channel"
    private val notificationManager = NotificationManagerCompat.from(context)

    companion object {
        const val REMINDER_REQUEST_CODE = 12345
    }

    init {
        createNotificationChannel()
    }

    // Планирование конкретного напоминания для отдельного элемента
    private fun scheduleSpecificReminder(itemId: Int, year: Int, month: Int, day: Int, hour: Int, minute: Int, title: String, body: String) {
        try {
            Log.d("MemorizerApp", "Scheduling specific reminder for item $itemId at $year-$month-$day $hour:$minute")

            // Создаем intent для конкретного напоминания
            val intent = Intent(context, NotificationReceiver::class.java).apply {
                action = "com.example.memorizer.SPECIFIC_REMINDER"
                putExtra("itemId", itemId)
                putExtra("title", title)
                putExtra("body", body)
            }

            // Используем itemId как уникальный requestCode для PendingIntent
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                itemId, // Используем itemId как уникальный код
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Устанавливаем время для напоминания
            val calendar = Calendar.getInstance().apply {
                set(Calendar.YEAR, year)
                set(Calendar.MONTH, month - 1) // Calendar месяцы начинаются с 0
                set(Calendar.DAY_OF_MONTH, day)
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, minute)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }

            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

            // Планируем точное напоминание только если время в будущем
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

    // Отмена конкретного напоминания
    private fun cancelSpecificReminder(itemId: Int) {
        try {
            Log.d("MemorizerApp", "Cancelling specific reminder for item $itemId")

            val intent = Intent(context, NotificationReceiver::class.java).apply {
                action = "com.example.memorizer.SPECIFIC_REMINDER"
            }

            val pendingIntent = PendingIntent.getBroadcast(
                context,
                itemId, // Используем тот же itemId как код
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
            "scheduleDaily" -> {
                val time = call.argument<String>("time") ?: MainActivity.DEFAULT_NOTIFICATION_TIME
                val title = call.argument<String>("title") ?: ""
                val body = call.argument<String>("body") ?: ""

                // Сохраняем время проверки в базу данных
                if (saveSqliteSetting("Notification time", time)) {
                    // Планируем ежедневную проверку
                    scheduleDaily(time, title, body)
                    result.success(true)
                } else {
                    result.error("DB_ERROR", "Failed to save notification time", null)
                }
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
                saveSqliteSetting("Enable reminders", "false")
                result.success(true)
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

    // Сохранение настроек в SQLite
    private fun saveSqliteSetting(key: String, value: String): Boolean {
        try {
            val dbPath = context.getDatabasePath("settings.db")
            if (!dbPath.exists()) {
                Log.e("MemorizerApp", "Settings database not found")
                return false
            }

            val db = SQLiteDatabase.openDatabase(
                dbPath.absolutePath,
                null,
                SQLiteDatabase.OPEN_READWRITE
            )

            // Проверяем существует ли запись
            val cursor = db.rawQuery(
                "SELECT value FROM settings WHERE key = ?",
                arrayOf(key)
            )

            val values = ContentValues().apply {
                put("value", value)
            }

            if (cursor.moveToFirst()) {
                // Запись существует, обновляем
                db.update("settings", values, "key = ?", arrayOf(key))
            } else {
                // Записи нет, вставляем новую
                values.put("key", key)
                db.insert("settings", null, values)
            }

            cursor.close()
            db.close()
            return true
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error updating SQLite database: ${e.message}")
            return false
        }
    }

    // Получение настройки из SQLite
    private fun getSqliteSetting(key: String, defaultValue: String): String {
        try {
            val dbPath = context.getDatabasePath("settings.db")
            if (!dbPath.exists()) {
                return defaultValue
            }

            val db = SQLiteDatabase.openDatabase(
                dbPath.absolutePath,
                null,
                SQLiteDatabase.OPEN_READONLY
            )

            val cursor = db.rawQuery(
                "SELECT value FROM settings WHERE key = ?",
                arrayOf(key)
            )

            val result = if (cursor.moveToFirst()) {
                cursor.getString(0)
            } else {
                defaultValue
            }

            cursor.close()
            db.close()
            return result
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error reading from SQLite database: ${e.message}")
            return defaultValue
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

    private fun scheduleDaily(timeString: String, title: String, body: String) {
        try {
            // Проверяем формат времени
            var timeToUse = timeString
            if (!isValidTimeFormat(timeToUse)) {
                timeToUse = MainActivity.DEFAULT_NOTIFICATION_TIME
                saveSqliteSetting("Notification time", timeToUse)
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

            // Сначала отменяем предыдущие будильники
            alarmManager.cancel(pendingIntent)

            // Устанавливаем точный будильник на нужное время
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                // Для более новых версий Android используем setExactAndAllowWhileIdle
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    calendar.timeInMillis,
                    pendingIntent
                )
            } else {
                // Для старых версий используем setExact
                alarmManager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    calendar.timeInMillis,
                    pendingIntent
                )
            }

            // Также планируем повторение на следующий день
            val tomorrowCalendar = Calendar.getInstance().apply {
                timeInMillis = calendar.timeInMillis
                add(Calendar.DAY_OF_YEAR, 1)
            }

            val tomorrowIntent = PendingIntent.getBroadcast(
                context,
                REMINDER_REQUEST_CODE + 1,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    tomorrowCalendar.timeInMillis,
                    tomorrowIntent
                )
            } else {
                alarmManager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    tomorrowCalendar.timeInMillis,
                    tomorrowIntent
                )
            }

            Log.d("MemorizerApp", "Daily alarm set successfully")
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error in scheduleDaily: ${e.message}")
            e.printStackTrace()
        }
    }

    // Восстановление расписания уведомлений при запуске или после перезагрузки
    fun restoreNotificationSchedule() {
        try {
            // Проверяем, включены ли уведомления
            val enableReminders = getSqliteSetting("Enable reminders", "true")

            if (enableReminders != "true") {
                Log.d("MemorizerApp", "Reminders are disabled, not restoring schedule")
                cancelAllNotifications()
                return
            }

            // Получаем настройки времени уведомления
            val notificationTime = getSqliteSetting("Notification time", MainActivity.DEFAULT_NOTIFICATION_TIME)

            // Перепланируем уведомления
            scheduleDaily(
                notificationTime,
                "Memorizer",
                "Checking for today's events"
            )

            Log.d("MemorizerApp", "Notification schedule restored for time: $notificationTime")
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error restoring notification schedule: ${e.message}")
        }
    }

    private fun cancelAllNotifications() {
        try {
            // Отменяем все активные уведомления
            notificationManager.cancelAll()

            // Отменяем запланированные проверки
            val intent = Intent(context, NotificationReceiver::class.java)

            val pendingIntent = PendingIntent.getBroadcast(
                context,
                REMINDER_REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val tomorrowPendingIntent = PendingIntent.getBroadcast(
                context,
                REMINDER_REQUEST_CODE + 1,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.cancel(pendingIntent)
            alarmManager.cancel(tomorrowPendingIntent)

            Log.d("MemorizerApp", "All notifications and scheduled checks cancelled")
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error cancelling notifications: ${e.message}")
        }
    }
}


/**
 * BroadcastReceiver для обработки напоминаний.
 * Показывает уведомления о событиях, запланированных на сегодня.
 */
/**
 * BroadcastReceiver для обработки напоминаний.
 * Показывает уведомления о событиях, запланированных на сегодня.
 */
class NotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("MemorizerApp", "NotificationReceiver: onReceive triggered with action: ${intent.action}")

        try {
            when (intent.action) {
                Intent.ACTION_BOOT_COMPLETED -> {
                    // Передаем управление в BootReceiver
                    Log.d("MemorizerApp", "Boot completed, forwarding to BootReceiver")
                    return
                }
                "com.example.memorizer.SPECIFIC_REMINDER" -> {
                    // Обрабатываем конкретное напоминание
                    handleSpecificReminder(context, intent)
                    return
                }
                "com.example.memorizer.CHECK_REMINDERS" -> {
                    // Обрабатываем общую проверку (как раньше)
                    handleGeneralReminderCheck(context, intent)
                    return
                }
            }
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error in NotificationReceiver.onReceive: ${e.message}")
            e.printStackTrace()
        }
    }

    // Обработка конкретного напоминания
    private fun handleSpecificReminder(context: Context, intent: Intent) {
        try {
            val itemId = intent.getIntExtra("itemId", 0)
            val title = intent.getStringExtra("title") ?: "Memorizer"
            val body = intent.getStringExtra("body") ?: "You have a scheduled event"

            Log.d("MemorizerApp", "Handling specific reminder for item $itemId")

            // Проверяем, включены ли напоминания
            if (!isRemindersEnabled(context)) {
                Log.d("MemorizerApp", "Reminders are disabled, skipping specific reminder")
                return
            }

            // Проверяем, существует ли ещё этот элемент в базе данных и имеет ли он напоминание
            if (isItemStillActive(context, itemId)) {
                // Создаем канал уведомлений
                createNotificationChannel(context)

                // Получаем заголовок и содержимое из базы данных
                val itemData = getItemData(context, itemId)
                val itemTitle = if (itemData.first.isNotEmpty()) "Reminder: ${itemData.first}" else title
                val itemContent = itemData.second.ifEmpty { body }

                // Показываем уведомление
                showEventNotification(context, itemId, itemTitle, itemContent, itemId)

                Log.d("MemorizerApp", "Specific reminder shown for item $itemId")
            } else {
                Log.d("MemorizerApp", "Item $itemId no longer exists or reminder disabled, skipping notification")
            }

        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error handling specific reminder: ${e.message}")
        }
    }

    // Получаем данные элемента из базы данных
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

    // Проверяем, активен ли ещё элемент в базе данных
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
                cursor.getInt(0) == 1 // remind должен быть включен
            } else {
                false // элемент не найден
            }

            cursor.close()
            db.close()
            isActive
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error checking if item is active: ${e.message}")
            false
        }
    }

    // Обработка общей проверки напоминаний (старая логика)
    private fun handleGeneralReminderCheck(context: Context, intent: Intent) {
        try {
            // Проверяем, включены ли напоминания
            val enabled = isRemindersEnabled(context)
            if (!enabled) {
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

            // Запрашиваем события на сегодня с включенными напоминаниями, включая поле time
            val cursor = db.rawQuery(
                "SELECT id, title, content, time FROM items WHERE remind = 1 AND date = ? AND (hidden = 0 OR hidden IS NULL)",
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

            // Получаем текущее время
            val currentHour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
            val currentMinute = Calendar.getInstance().get(Calendar.MINUTE)

            // Для каждого события проверяем время и создаем уведомление если нужно
            var notificationId = 1
            var notificationsShown = 0

            while (cursor.moveToNext()) {
                val idColumn = cursor.getColumnIndexOrThrow("id")
                val titleColumn = cursor.getColumnIndexOrThrow("title")
                val contentColumn = cursor.getColumnIndexOrThrow("content")
                val timeColumn = cursor.getColumnIndexOrThrow("time")

                val id = cursor.getInt(idColumn)
                val title = cursor.getString(titleColumn) ?: ""
                val content = cursor.getString(contentColumn) ?: ""
                val itemTime = if (cursor.isNull(timeColumn)) null else cursor.getInt(timeColumn)

                // Определяем время уведомления для этой записи
                val notificationTime = determineNotificationTime(context, itemTime)

                Log.d("MemorizerApp", "Event ID: $id, Title: $title, Item time: $itemTime, Notification time: $notificationTime")

                // Проверяем, нужно ли показывать уведомление сейчас
                if (shouldShowNotificationNow(currentHour, currentMinute, notificationTime)) {
                    Log.d("MemorizerApp", "Showing reminder for event ID: $id, Title: $title")
                    showEventNotification(context, id, "Reminder: $title", content, notificationId)
                    notificationId++
                    notificationsShown++
                }
            }

            // Если показано больше одного уведомления, показываем общее уведомление
            if (notificationsShown > 1) {
                showEventNotification(
                    context,
                    0,
                    "Today's events",
                    "You have $notificationsShown scheduled events for today",
                    999999
                )
            }

            cursor.close()
            db.close()

            // Отправляем сообщение в Flutter для проверки событий
            MainActivity.checkEvents()

            // Планируем следующую проверку
            scheduleNextCheck(context)

        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error in handleGeneralReminderCheck: ${e.message}")
            e.printStackTrace()
        }
    }

    // Определяем время уведомления для конкретной записи
    private fun determineNotificationTime(context: Context, itemTime: Int?): String {
        return if (itemTime != null) {
            // Если у записи есть своё время, используем его
            formatTimeFromInt(itemTime)
        } else {
            // Иначе используем время по умолчанию из настроек
            getNotificationTime(context)
        }
    }

    // Форматируем время из integer в строку HH:MM
    private fun formatTimeFromInt(timeInt: Int): String {
        val hours = timeInt / 100
        val minutes = timeInt % 100
        return String.format("%02d:%02d", hours, minutes)
    }

    // Проверяем, нужно ли показывать уведомление сейчас
    private fun shouldShowNotificationNow(currentHour: Int, currentMinute: Int, notificationTime: String): Boolean {
        return try {
            val parts = notificationTime.split(":")
            if (parts.size != 2) return true // В случае ошибки показываем уведомление

            val notificationHour = parts[0].toIntOrNull() ?: return true
            val notificationMinute = parts[1].toIntOrNull() ?: return true

            val currentTotalMinutes = currentHour * 60 + currentMinute
            val notificationTotalMinutes = notificationHour * 60 + notificationMinute

            // Показываем уведомление если текущее время равно времени уведомления
            // или прошло не более 60 минут с времени уведомления
            currentTotalMinutes >= notificationTotalMinutes &&
                    (currentTotalMinutes - notificationTotalMinutes) <= 60
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error checking notification time: ${e.message}")
            true // В случае ошибки показываем уведомление
        }
    }

    // Планируем следующую проверку через час или на следующий день
    private fun scheduleNextCheck(context: Context) {
        try {
            val intent = Intent(context, NotificationReceiver::class.java).apply {
                action = "com.example.memorizer.CHECK_REMINDERS"
            }

            val pendingIntent = PendingIntent.getBroadcast(
                context,
                NotificationService.REMINDER_REQUEST_CODE + 100, // Используем другой ID
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Планируем проверку через час
            val calendar = Calendar.getInstance().apply {
                add(Calendar.HOUR_OF_DAY, 1)
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

            Log.d("MemorizerApp", "Next check scheduled for: ${calendar.time}")
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error scheduling next check: ${e.message}")
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
                .setDefaults(NotificationCompat.DEFAULT_ALL)

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
        }
    }

    // Проверяем, включены ли напоминания в настройках
    private fun isRemindersEnabled(context: Context): Boolean {
        try {
            val dbPath = context.getDatabasePath("settings.db")
            if (!dbPath.exists()) {
                return true // По умолчанию включено
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
                true // По умолчанию включено
            }

            cursor.close()
            db.close()
            return result
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error checking if reminders enabled: ${e.message}")
            return true // По умолчанию, если ошибка
        }
    }

    // Получаем время напоминаний из настроек
    private fun getNotificationTime(context: Context): String {
        try {
            val dbPath = context.getDatabasePath("settings.db")
            if (!dbPath.exists()) {
                return MainActivity.DEFAULT_NOTIFICATION_TIME
            }

            val db = SQLiteDatabase.openDatabase(
                dbPath.absolutePath,
                null,
                SQLiteDatabase.OPEN_READONLY
            )

            val cursor = db.rawQuery(
                "SELECT value FROM settings WHERE key = ?",
                arrayOf("Notification time")
            )

            val timeValue = if (cursor.moveToFirst()) {
                cursor.getString(0)
            } else {
                MainActivity.DEFAULT_NOTIFICATION_TIME
            }

            cursor.close()
            db.close()

            // Проверяем формат времени
            val isValid = try {
                val parts = timeValue.split(":")
                if (parts.size != 2) return MainActivity.DEFAULT_NOTIFICATION_TIME

                val hour = parts[0].toInt()
                val minute = parts[1].toInt()

                hour in 0..23 && minute in 0..59
            } catch (e: Exception) {
                false
            }

            return if (isValid) timeValue else MainActivity.DEFAULT_NOTIFICATION_TIME
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error getting notification time: ${e.message}")
            return MainActivity.DEFAULT_NOTIFICATION_TIME
        }
    }

}


/**
 * BroadcastReceiver для восстановления запланированных уведомлений
 * после перезагрузки устройства
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.d("MemorizerApp", "Device rebooted, rescheduling notifications")

            try {
                // Добавляем небольшую задержку, чтобы система успела полностью инициализироваться
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    val notificationService = NotificationService(context)
                    notificationService.restoreNotificationSchedule()
                    Log.d("MemorizerApp", "Reminders rescheduled after device reboot")
                }, 15000) // Задержка 15 секунд
            } catch (e: Exception) {
                Log.e("MemorizerApp", "Error rescheduling after boot: ${e.message}")
            }
        }
    }
}

