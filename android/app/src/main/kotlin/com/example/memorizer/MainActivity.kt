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
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Запрос разрешений для Android 13+
        requestNotificationPermission()
        
        try {
            // Set up method channel
            methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.memorizer/notifications")
            methodChannel?.setMethodCallHandler(NotificationService(applicationContext))
            Log.d("MemorizerApp", "Method channel initialized")
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error configuring flutter engine: ${e.message}")
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager.cancelAll()

        try {
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
    
    private fun requestNotificationPermission() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                    Log.d("MemorizerApp", "Requesting POST_NOTIFICATIONS permission")
                    ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 100)
                } else {
                    Log.d("MemorizerApp", "POST_NOTIFICATIONS permission already granted")
                }
            } else {
                Log.d("MemorizerApp", "POST_NOTIFICATIONS permission not needed on this Android version")
            }
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error requesting notification permission: ${e.message}")
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
                        // Можно уведомить Flutter об успешном получении разрешения
                    }
                    PackageManager.PERMISSION_DENIED -> {
                        Log.d("MemorizerApp", "POST_NOTIFICATIONS permission denied by user")
                        // Информируем Flutter, что разрешение не получено
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
