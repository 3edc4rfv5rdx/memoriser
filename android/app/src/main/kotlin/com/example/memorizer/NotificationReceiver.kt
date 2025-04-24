package com.example.memorizer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class NotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("MemorizerApp", "NotificationReceiver: onReceive triggered")

        // Просто вызываем checkEvents, без показа собственных уведомлений
        MainActivity.checkEvents()
    }
}

