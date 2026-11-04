package com.bhromon.app

import android.app.KeyguardManager
import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Rational
import android.view.WindowManager
import com.cloudwebrtc.webrtc.audio.AudioSwitchManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterFragmentActivity() {
    companion object {
        // The action flutter_callkit_incoming starts the app with on Accept.
        private const val ACTION_CALL_ACCEPT =
            "com.hiennv.flutter_callkit_incoming.ACTION_CALL_ACCEPT"
    }

    private val CHANNEL = "com.bhromon.app/integrity"
    private val CALL_AUDIO_CHANNEL = "com.bhromon.app/call_audio"
    private val BATTERY_CHANNEL = "com.bhromon.app/battery"
    private var callAudioChannel: MethodChannel? = null
    private var proximityLock: PowerManager.WakeLock? = null
    private var pipAllowed = false
    // The call screen asked to show over the lock screen.
    private var callScreenOverLock = false
    // The app was opened by Accept on the phone's call screen, and shows over
    // the lock screen until Dart opens the call or finds none to open.
    private var acceptOverLock = false

    override fun onCreate(savedInstanceState: Bundle?) {
        // Set before the first frame, so Accept on a locked phone opens the app
        // over the lock screen instead of asking to unlock first.
        noteAcceptLaunch(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        setIntent(intent)
        noteAcceptLaunch(intent)
        super.onNewIntent(intent)
    }

    private fun noteAcceptLaunch(intent: Intent?) {
        if (intent == null) return
        val action = intent.action ?: ""
        val isCall = action.endsWith("ACTION_CALL_ACCEPT") ||
            action == ACTION_CALL_ACCEPT ||
            intent.hasExtra("EXTRA_CALLKIT_CALL_DATA") ||
            intent.hasExtra("data")
        if (isCall) {
            acceptOverLock = true
            applyOverLockScreen()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
                keyguard?.requestDismissKeyguard(this, null)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isRooted" -> result.success(checkRooted())
                "isDeveloperMode" -> result.success(checkDeveloperMode())
                else -> result.notImplemented()
            }
        }
        // Battery guidance: whether the system lets the app run unrestricted, and
        // the battery settings page for the user to change it.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BATTERY_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" -> result.success(isIgnoringBatteryOptimizations())
                "openBatterySettings" -> result.success(openBatterySettings())
                "manufacturer" -> result.success(Build.MANUFACTURER)
                else -> result.notImplemented()
            }
        }
        val callAudio = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALL_AUDIO_CHANNEL)
        callAudioChannel = callAudio
        CallOngoingService.onHangUp = {
            runOnUiThread { callAudioChannel?.invokeMethod("hangUp", null) }
        }
        callAudio.setMethodCallHandler { call, result ->
            when (call.method) {
                "release" -> {
                    // Ends the plugin's audio session: the phone goes back to its normal
                    // audio mode and the audio focus is given up.
                    AudioSwitchManager.instance?.stop()
                    // The route this app set for the call is given back too.
                    clearCallRoute()
                    result.success(null)
                }
                "startOngoing" -> {
                    // Started while the call screen is open, which Android requires
                    // for a microphone or camera foreground service.
                    try {
                        CallOngoingService.start(
                            this,
                            call.argument<Boolean>("camera") ?: false,
                            call.argument<String>("title"),
                            call.argument<String>("text"),
                            call.argument<String>("hangUp")
                        )
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("ongoing_failed", e.message, null)
                    }
                }
                "stopOngoing" -> {
                    CallOngoingService.stop(this)
                    result.success(null)
                }
                "showOverLockScreen" -> {
                    // The call screen takes over from an Accept launch, in both
                    // directions: when it closes, the app goes behind the lock.
                    callScreenOverLock = call.argument<Boolean>("enabled") ?: false
                    acceptOverLock = false
                    applyOverLockScreen()
                    result.success(null)
                }
                "releaseAcceptLaunch" -> {
                    acceptOverLock = false
                    applyOverLockScreen()
                    result.success(null)
                }
                "setPipAllowed" -> {
                    pipAllowed = call.argument<Boolean>("allowed") ?: false
                    result.success(null)
                }
                "setProximityScreenOff" -> {
                    setProximityScreenOff(call.argument<Boolean>("enabled") ?: false)
                    result.success(null)
                }
                "setSpeakerphone" -> {
                    // Answers whether the route took, so the app can fall back to the plugin.
                    result.success(setSpeakerphone(call.argument<Boolean>("enabled") ?: false))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun applyOverLockScreen() {
        showOverLockScreen(callScreenOverLock || acceptOverLock)
    }

    /** Whether the system already lets this app run in the background without limits. */
    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        return power.isIgnoringBatteryOptimizations(packageName)
    }

    /** Opens the battery settings list. Returns false when the phone has no such page. */
    private fun openBatterySettings(): Boolean {
        return try {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            true
        } catch (e: Exception) {
            false
        }
    }

    /** Lets the call screen show over the lock screen and wake the display. */
    private fun showOverLockScreen(enabled: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(enabled)
            setTurnScreenOn(enabled)
        } else {
            @Suppress("DEPRECATION")
            val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            if (enabled) window.addFlags(flags) else window.clearFlags(flags)
        }
    }

    /**
     * Puts call audio on the loudspeaker, or back on the default route: the earpiece, or a
     * headset or Bluetooth device the phone picks. Returns whether the route took.
     */
    @Suppress("DEPRECATION")
    private fun setSpeakerphone(enabled: Boolean): Boolean {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        // A call needs the communication mode before its route can change.
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val success = try {
                if (enabled) {
                    val speaker = audioManager.availableCommunicationDevices
                        .firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                        ?: return false
                    audioManager.setCommunicationDevice(speaker)
                } else {
                    audioManager.clearCommunicationDevice()
                    true
                }
            } catch (e: Exception) {
                false
            }
            try {
                audioManager.isSpeakerphoneOn = enabled
            } catch (e: Exception) {
                // Ignore OEM-specific exceptions on deprecated property
            }
            return success
        }
        audioManager.isSpeakerphoneOn = enabled
        return audioManager.isSpeakerphoneOn == enabled
    }

    /** Gives back the route that [setSpeakerphone] set, once the call is over. */
    @Suppress("DEPRECATION")
    private fun clearCallRoute() {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager.clearCommunicationDevice()
        }
        audioManager.isSpeakerphoneOn = false
    }

    /** Turns the screen off while the phone is held to the ear. */
    private fun setProximityScreenOff(enabled: Boolean) {
        if (enabled) {
            if (proximityLock != null) return
            val power = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!power.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)) return
            val lock = power.newWakeLock(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK, "bhromon:call_proximity")
            // A ceiling, in case the call screen never releases it.
            lock.acquire(4 * 60 * 60 * 1000L)
            proximityLock = lock
        } else {
            val lock = proximityLock ?: return
            if (lock.isHeld) lock.release()
            proximityLock = null
        }
    }

    /** A video call shrinks into a small window when the user leaves the app. */
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (!pipAllowed || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            enterPictureInPictureMode(
                PictureInPictureParams.Builder().setAspectRatio(Rational(9, 16)).build()
            )
        } catch (e: Exception) {
            // Not supported on this device, or not allowed right now.
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        callAudioChannel?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }

    override fun onDestroy() {
        setProximityScreenOff(false)
        CallOngoingService.onHangUp = null
        callAudioChannel = null
        super.onDestroy()
    }

    private fun checkRooted(): Boolean {
        val buildTags = Build.TAGS
        if (buildTags != null && buildTags.contains("test-keys")) {
            return true
        }

        val paths = arrayOf(
            "/system/app/Superuser.apk",
            "/sbin/su",
            "/system/bin/su",
            "/system/xbin/su",
            "/data/local/xbin/su",
            "/data/local/bin/su",
            "/system/sd/xbin/su",
            "/system/bin/failsafe/su",
            "/data/local/su",
            "/su/bin/su"
        )
        for (path in paths) {
            if (File(path).exists()) return true
        }

        return false
    }

    private fun checkDeveloperMode(): Boolean {
        return try {
            Settings.Global.getInt(
                contentResolver,
                Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, 0
            ) != 0
        } catch (e: Exception) {
            false
        }
    }
}
