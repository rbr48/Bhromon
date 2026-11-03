package com.bhromon.app

import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
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
        noteAcceptLaunch(intent)
        super.onNewIntent(intent)
    }

    private fun noteAcceptLaunch(intent: Intent?) {
        if (intent?.action != ACTION_CALL_ACCEPT) return
        acceptOverLock = true
        applyOverLockScreen()
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
                else -> result.notImplemented()
            }
        }
    }

    private fun applyOverLockScreen() {
        showOverLockScreen(callScreenOverLock || acceptOverLock)
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
