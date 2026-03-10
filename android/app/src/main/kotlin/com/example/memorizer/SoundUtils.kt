package com.example.memorizer

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.util.Log

/**
 * Shared sound utilities for notification and fullscreen alert playback.
 * Does NOT manage MediaPlayer lifecycle — callers own their MediaPlayer instances.
 */
object SoundUtils {

    private const val TAG = "MemorizerApp"

    /** Alarm audio attributes used for all reminder sounds */
    val alarmAudioAttributes: AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ALARM)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()

    /** System fallback URI: alarm sound, or notification sound if alarm unavailable */
    fun getSystemFallbackUri(): Uri? {
        return RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
    }

    /**
     * Resolve a sound value string to a URI.
     * Handles null/empty/"default" → system fallback, file paths, content:// URIs.
     */
    fun resolveUri(soundValue: String?): Uri? {
        return when {
            soundValue.isNullOrEmpty() || soundValue == "default" -> getSystemFallbackUri()
            soundValue.startsWith("/") -> Uri.fromFile(java.io.File(soundValue))
            else -> try { Uri.parse(soundValue) } catch (_: Exception) { getSystemFallbackUri() }
        }
    }

    /**
     * Route MediaPlayer output to built-in speaker (bypass Bluetooth/other outputs).
     */
    fun routeToSpeaker(player: MediaPlayer, context: Context) {
        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
            val speaker = audioManager.getDevices(android.media.AudioManager.GET_DEVICES_OUTPUTS)
                .firstOrNull { it.type == android.media.AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
            if (speaker != null) {
                player.setPreferredDevice(speaker)
                Log.d(TAG, "Forced audio output to built-in speaker")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error routing to speaker: ${e.message}")
        }
    }
}
