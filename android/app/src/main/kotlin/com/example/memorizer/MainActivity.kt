package com.example.memorizer

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import android.content.Context
import android.app.NotificationManager
import android.content.SharedPreferences


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
                    Log.d("MemorizerApp", "Requesting SCHEDULE_EXACT_ALARM permission")
                    // На Android 12+ для этого разрешения нужно отправить пользователя в настройки
                    // Здесь можно показать диалог с объяснением и кнопкой для перехода в настройки
                    // или запрашивать разрешение только при необходимости
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
