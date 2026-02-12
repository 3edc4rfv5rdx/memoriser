package com.example.memorizer

import android.app.Activity
import android.app.AlarmManager
import android.app.KeyguardManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import java.util.Calendar

/**
 * FullScreenAlertActivity displays a fullscreen alert window for reminders.
 * Features:
 * - Shows on lock screen
 * - Plays sound once
 * - Draggable circle barrier to prevent accidental dismissal
 * - [OK] button to dismiss (only accessible after dragging circle down)
 */
class FullScreenAlertActivity : Activity() {
    private var mediaPlayer: MediaPlayer? = null
    private lateinit var draggableCircle: View
    private lateinit var barrierOverlay: View
    private var dragStartY = 0f
    private var initialY = 0f

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        Log.d("MemorizerApp", "FullScreenAlertActivity.onCreate() called")

        // Setup window flags for lock screen display
        setupWindowFlags()

        setContentView(R.layout.activity_fullscreen_alert)

        // Get intent data
        val itemId = intent.getIntExtra("itemId", -1)
        val title = intent.getStringExtra("title") ?: "Reminder"
        val content = intent.getStringExtra("content") ?: ""
        val soundValue = intent.getStringExtra("sound")

        // Get translated labels (fallback to English if not provided)
        val labelReminder = intent.getStringExtra("label_reminder") ?: "Reminder:"
        val labelPostpone = intent.getStringExtra("label_postpone") ?: "Postpone for:"
        val labelMin = intent.getStringExtra("label_min") ?: "min"
        val labelHour = intent.getStringExtra("label_hour") ?: "hour"
        val labelHours = intent.getStringExtra("label_hours") ?: "hours"
        val labelDay = intent.getStringExtra("label_day") ?: "day"
        val isDaily = intent.getBooleanExtra("isDaily", false)

        Log.d("MemorizerApp", "FullScreenAlert - itemId: $itemId, title: $title, sound: $soundValue")
        Log.d("MemorizerApp", "Labels - reminder: $labelReminder, postpone: $labelPostpone")

        // Cancel the notification now that fullscreen is shown
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            notificationManager.cancel(itemId)
            Log.d("MemorizerApp", "Cancelled notification for item $itemId")
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error cancelling notification: ${e.message}")
        }

        // Set current time
        val currentTime = java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault())
            .format(java.util.Date())
        findViewById<TextView>(R.id.alert_time).text = currentTime

        // Set translated labels
        findViewById<TextView>(R.id.label_reminder).text = labelReminder
        findViewById<TextView>(R.id.label_postpone).text = labelPostpone

        // Set text in views
        findViewById<TextView>(R.id.alert_title).text = title
        findViewById<TextView>(R.id.alert_content).apply {
            text = content
            visibility = if (content.isEmpty()) View.GONE else View.VISIBLE
        }

        // Set button texts with translations
        findViewById<Button>(R.id.snooze_10min).text = "10 $labelMin"
        findViewById<Button>(R.id.snooze_20min).text = "20 $labelMin"
        findViewById<Button>(R.id.snooze_30min).text = "30 $labelMin"
        findViewById<Button>(R.id.snooze_1hour).text = "1 $labelHour"
        findViewById<Button>(R.id.snooze_3hours).text = "3 $labelHours"

        // Setup OK button
        findViewById<Button>(R.id.alert_ok_button).setOnClickListener {
            dismissAlert()
        }

        // Setup snooze buttons
        findViewById<Button>(R.id.snooze_10min).setOnClickListener {
            snoozeReminder(itemId, title, content, soundValue, 10)
        }
        findViewById<Button>(R.id.snooze_20min).setOnClickListener {
            snoozeReminder(itemId, title, content, soundValue, 20)
        }
        findViewById<Button>(R.id.snooze_30min).setOnClickListener {
            snoozeReminder(itemId, title, content, soundValue, 30)
        }
        findViewById<Button>(R.id.snooze_1hour).setOnClickListener {
            snoozeReminder(itemId, title, content, soundValue, 60)
        }
        findViewById<Button>(R.id.snooze_3hours).setOnClickListener {
            snoozeReminder(itemId, title, content, soundValue, 180)
        }

        // Setup postpone 1 day button (hidden for daily reminders)
        val postpone1day = findViewById<Button>(R.id.postpone_1day)
        if (isDaily) {
            postpone1day.visibility = View.GONE
        } else {
            postpone1day.text = "1 $labelDay"
            postpone1day.setOnClickListener {
                snoozeReminder(itemId, title, content, soundValue, 1440)
            }
        }

        // Setup barrier overlay and draggable circle
        barrierOverlay = findViewById(R.id.barrier_overlay)
        draggableCircle = findViewById(R.id.draggable_circle)
        setupDragGesture()

        // Play sound once
        playSound(soundValue)

        Log.d("MemorizerApp", "FullScreenAlertActivity created for item $itemId")
    }

    /**
     * Setup window flags to show on lock screen and turn screen on
     */
    private fun setupWindowFlags() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)

            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            keyguardManager.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    /**
     * Setup drag gesture for the draggable circle barrier
     */
    private fun setupDragGesture() {
        draggableCircle.setOnTouchListener { view, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    dragStartY = view.y
                    initialY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val deltaY = event.rawY - initialY
                    if (deltaY > 0) {  // Only allow dragging down
                        view.y = dragStartY + deltaY
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    val deltaY = event.rawY - initialY
                    if (deltaY > 600) {  // Dragged down at least 600 pixels (longer path)
                        hideCircle()
                    } else {
                        // Snap back to original position
                        view.animate()
                            .y(dragStartY)
                            .setDuration(200)
                            .start()
                    }
                    true
                }
                else -> false
            }
        }
    }

    /**
     * Hide the barrier overlay and draggable circle with fade animation
     */
    private fun hideCircle() {
        // Remove touch listener first to stop consuming events
        draggableCircle.setOnTouchListener(null)

        // Hide both overlay and circle with animation
        barrierOverlay.animate()
            .alpha(0f)
            .setDuration(300)
            .withEndAction {
                barrierOverlay.visibility = View.GONE
            }
            .start()

        draggableCircle.animate()
            .alpha(0f)
            .setDuration(300)
            .withEndAction {
                draggableCircle.visibility = View.GONE
            }
            .start()
    }

    /**
     * Play sound once using MediaPlayer with USAGE_ALARM
     */
    private fun playSound(soundValue: String?) {
        try {
            val soundUri = when {
                soundValue.isNullOrEmpty() || soundValue == "default" -> {
                    // Use default alarm sound
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                        ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                }
                soundValue.startsWith("content://") -> {
                    // System sound URI
                    Uri.parse(soundValue)
                }
                soundValue.startsWith("/") -> {
                    // File path
                    Uri.parse("file://$soundValue")
                }
                else -> {
                    // Default fallback
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                }
            }

            Log.d("MemorizerApp", "Starting to play sound: $soundValue, URI: $soundUri")

            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setDataSource(applicationContext, soundUri)
                prepare()
                start()

                val duration = this.duration
                Log.d("MemorizerApp", "Sound started playing, duration: $duration ms")

                setOnCompletionListener {
                    Log.d("MemorizerApp", "Sound playback completed")
                    release()
                    mediaPlayer = null
                }

                setOnErrorListener { mp, what, extra ->
                    Log.e("MemorizerApp", "MediaPlayer error: what=$what, extra=$extra")
                    false
                }
            }

            Log.d("MemorizerApp", "MediaPlayer created and started")
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error playing sound: ${e.message}")
            // Continue without sound if error occurs
        }
    }

    /**
     * Snooze the reminder - reschedule for X minutes from now
     */
    private fun snoozeReminder(itemId: Int, title: String, content: String, soundValue: String?, minutesFromNow: Int) {
        try {
            Log.d("MemorizerApp", "=== SNOOZE REMINDER START ===")
            Log.d("MemorizerApp", "itemId: $itemId, minutes: $minutesFromNow")
            Log.d("MemorizerApp", "title: $title, content: $content, sound: $soundValue")

            // Calculate snooze time (round to minutes, no seconds)
            val calendar = Calendar.getInstance()
            calendar.add(Calendar.MINUTE, minutesFromNow)
            calendar.set(Calendar.SECOND, 0)
            calendar.set(Calendar.MILLISECOND, 0)
            val now = Calendar.getInstance().time
            val snoozeTime = calendar.time

            Log.d("MemorizerApp", "Current time: $now")
            Log.d("MemorizerApp", "Snooze time: $snoozeTime (${calendar.timeInMillis}ms)")

            // Create intent for the snoozed reminder - store all data in intent (no DB lookup)
            val intent = Intent(this, NotificationReceiver::class.java).apply {
                action = "com.example.memorizer.SNOOZED_REMINDER"
                putExtra("itemId", itemId)
                putExtra("title", title)
                putExtra("content", content)
                putExtra("sound", soundValue)
            }

            // Use unique requestCode for snoozed reminders (1000000 + itemId to avoid conflicts)
            val requestCode = 1000000 + itemId

            Log.d("MemorizerApp", "Using requestCode: $requestCode")

            val pendingIntent = PendingIntent.getBroadcast(
                this,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager

            // Check permission on Android 12+
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (!alarmManager.canScheduleExactAlarms()) {
                    Log.w("MemorizerApp", "SCHEDULE_EXACT_ALARM permission not granted (setAlarmClock should still work)")
                }
            }

            // Schedule the snoozed reminder using setAlarmClock for guaranteed exact timing
            // This ensures it fires even in Doze mode and shows in system alarms
            val alarmClockInfo = AlarmManager.AlarmClockInfo(
                calendar.timeInMillis,
                pendingIntent
            )
            alarmManager.setAlarmClock(alarmClockInfo, pendingIntent)

            Log.d("MemorizerApp", "setAlarmClock called successfully")
            Log.d("MemorizerApp", "=== SNOOZE REMINDER SCHEDULED ===")

            // Close the alert
            dismissAlert()

        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error snoozing reminder: ${e.message}")
            e.printStackTrace()
            // Close anyway
            dismissAlert()
        }
    }

    /**
     * Dismiss the alert activity
     */
    private fun dismissAlert() {
        Log.d("MemorizerApp", "dismissAlert() called")
        try {
            // Stop and release media player
            mediaPlayer?.let {
                Log.d("MemorizerApp", "Stopping MediaPlayer, isPlaying: ${it.isPlaying}")
                if (it.isPlaying) {
                    it.stop()
                }
                it.release()
                mediaPlayer = null
            }
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error stopping media player: ${e.message}")
        }

        finish()
        Log.d("MemorizerApp", "FullScreenAlertActivity finished")
    }

    /**
     * Disable back button - user must drag circle and tap OK
     */
    override fun onBackPressed() {
        // Do nothing - user must use OK button
    }

    override fun onDestroy() {
        super.onDestroy()
        // Clean up media player if still playing
        try {
            mediaPlayer?.release()
            mediaPlayer = null
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error in onDestroy: ${e.message}")
        }
    }
}
