package com.example.memorizer

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView

/**
 * FullScreenAlertActivity displays a fullscreen alert window for reminders.
 * Features:
 * - Shows on lock screen
 * - Plays sound once
 * - Swipe-down barrier to prevent accidental dismissal
 * - [OK] button to dismiss (only accessible after swipe)
 */
class FullScreenAlertActivity : Activity() {
    private var mediaPlayer: MediaPlayer? = null
    private lateinit var barrierOverlay: View
    private lateinit var gestureDetector: GestureDetector

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Setup window flags for lock screen display
        setupWindowFlags()

        setContentView(R.layout.activity_fullscreen_alert)

        // Get intent data
        val itemId = intent.getIntExtra("itemId", -1)
        val title = intent.getStringExtra("title") ?: "Reminder"
        val content = intent.getStringExtra("content") ?: ""
        val soundValue = intent.getStringExtra("sound")

        // Set text in views
        findViewById<TextView>(R.id.alert_title).text = title
        findViewById<TextView>(R.id.alert_content).apply {
            text = content
            visibility = if (content.isEmpty()) View.GONE else View.VISIBLE
        }

        // Setup OK button
        findViewById<Button>(R.id.alert_ok_button).setOnClickListener {
            dismissAlert()
        }

        // Setup swipe barrier
        barrierOverlay = findViewById(R.id.barrier_overlay)
        setupSwipeGesture()

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
     * Setup swipe gesture detector for the barrier overlay
     */
    private fun setupSwipeGesture() {
        gestureDetector = GestureDetector(this, object : GestureDetector.SimpleOnGestureListener() {
            override fun onFling(
                e1: MotionEvent?,
                e2: MotionEvent,
                velocityX: Float,
                velocityY: Float
            ): Boolean {
                // Detect swipe down: velocityY > 0 (positive = downward)
                if (velocityY > 500) {  // Threshold: 500 pixels/sec
                    hideBarrier()
                    return true
                }
                return false
            }
        })

        barrierOverlay.setOnTouchListener { _, event ->
            gestureDetector.onTouchEvent(event)
            true
        }
    }

    /**
     * Hide the barrier overlay with fade animation
     */
    private fun hideBarrier() {
        barrierOverlay.animate()
            .alpha(0f)
            .setDuration(300)
            .withEndAction {
                barrierOverlay.visibility = View.GONE
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

                setOnCompletionListener {
                    release()
                    mediaPlayer = null
                }
            }

            Log.d("MemorizerApp", "Playing sound: $soundValue")
        } catch (e: Exception) {
            Log.e("MemorizerApp", "Error playing sound: ${e.message}")
            // Continue without sound if error occurs
        }
    }

    /**
     * Dismiss the alert activity
     */
    private fun dismissAlert() {
        try {
            // Stop and release media player
            mediaPlayer?.let {
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
    }

    /**
     * Disable back button - user must swipe and tap OK
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
