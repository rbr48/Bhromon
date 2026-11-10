package com.bhromon.app

import android.app.KeyguardManager
import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.OpenableColumns
import android.provider.Settings
import android.telecom.CallAudioState
import android.util.Log
import android.util.Rational
import android.webkit.MimeTypeMap
import android.view.WindowManager
import com.cloudwebrtc.webrtc.audio.AudioSwitchManager
import com.hiennv.flutter_callkit_incoming.CallkitConnection
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity: FlutterFragmentActivity() {
    companion object {
        // The action flutter_callkit_incoming starts the app with on Accept.
        private const val ACTION_CALL_ACCEPT =
            "com.hiennv.flutter_callkit_incoming.ACTION_CALL_ACCEPT"

        private const val SHARE_CHANNEL = "com.bhromon.app/share_intake"
        // Shared files are copied here, and a copy that was never taken is removed a day on.
        private const val SHARE_DIR = "shared_inbox"
        private const val SHARE_TTL_MS = 24L * 60 * 60 * 1000
        // The largest file any destination takes (kMaxVideoBytes in media_rules.dart).
        private const val MAX_SHARE_COPY_BYTES = 100L * 1024 * 1024
        private const val SHARE_LOG = "ShareIntake"
    }

    private val CHANNEL = "com.bhromon.app/integrity"
    private val CALL_AUDIO_CHANNEL = "com.bhromon.app/call_audio"
    private val BATTERY_CHANNEL = "com.bhromon.app/battery"
    private var callAudioChannel: MethodChannel? = null
    private var shareChannel: MethodChannel? = null
    // Read and written on the main thread only.
    private val pendingShares = mutableListOf<Map<String, Any?>>()
    private val shareExecutor = Executors.newSingleThreadExecutor()
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
        // After a rebuild the same intent is still here, so a share is read only once.
        if (savedInstanceState == null) handleShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        setIntent(intent)
        noteAcceptLaunch(intent)
        handleShareIntent(intent)
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
        val share = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
        shareChannel = share
        share.setMethodCallHandler { call, result ->
            when (call.method) {
                "takePendingShares" -> {
                    val items = pendingShares.toList()
                    pendingShares.clear()
                    result.success(items)
                }
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
                "enterPip" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val entered = enterPictureInPictureMode(
                                PictureInPictureParams.Builder().setAspectRatio(Rational(9, 16)).build()
                            )
                            result.success(entered)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "setProximityScreenOff" -> {
                    setProximityScreenOff(call.argument<Boolean>("enabled") ?: false)
                    result.success(null)
                }
                "setSpeakerphone" -> {
                    // Answers whether the route took, so the app can fall back to the plugin.
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    // A call the phone's call system holds is routed by that system, so
                    // the request goes to it first. The audio manager is still set, for
                    // phones that route the call from it.
                    val telecom = setTelecomRoute(call.argument<String>("callId"), enabled)
                    val direct = setSpeakerphone(enabled)
                    result.success(telecom || direct)
                }
                "routeSnapshot" -> {
                    // What the phone and the WebRTC plugin say the call is routed to, read
                    // after a call connects to check the loudspeaker route.
                    result.success(routeSnapshot())
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
     * Asks the phone's call system (Telecom) to route the call [callId] to the loudspeaker,
     * or back to the earpiece or a wired headset. Telecom owns the route of a call it holds
     * and starts a voice call on the earpiece, so a request made only through the audio
     * manager does not move it. False when Telecom does not hold the call.
     */
    @Suppress("DEPRECATION")
    private fun setTelecomRoute(callId: String?, speaker: Boolean): Boolean {
        if (callId.isNullOrEmpty() || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            val connection = CallkitConnection.find(callId) ?: return false
            connection.setAudioRoute(
                if (speaker) CallAudioState.ROUTE_SPEAKER else CallAudioState.ROUTE_WIRED_OR_EARPIECE
            )
            true
        } catch (e: Exception) {
            Log.w("MainActivity", "Telecom audio route failed", e)
            false
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

    /**
     * The call's audio route as the phone and the WebRTC plugin report it. It holds
     * types and volumes only, never device names.
     */
    private fun routeSnapshot(): Map<String, Any?> {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val communication = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager.communicationDevice?.let { routeName(it.type) }
        } else {
            null
        }
        val outputs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).map { routeName(it.type) }.distinct()
        } else {
            emptyList<String>()
        }
        return mapOf(
            "mode" to audioManager.mode,
            "speakerphoneOn" to audioManager.isSpeakerphoneOn,
            "communicationDevice" to communication,
            "pluginDevice" to pluginDeviceName(),
            "voiceCallVolume" to audioManager.getStreamVolume(AudioManager.STREAM_VOICE_CALL),
            "voiceCallMax" to audioManager.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL),
            "outputs" to outputs,
        )
    }

    /**
     * The class name of the output the WebRTC plugin's audio switch selected. It is read by
     * reflection because the device type comes from a library this module does not compile
     * against. Null when it cannot be read; the route check then uses the phone's route alone.
     */
    private fun pluginDeviceName(): String? {
        val manager = AudioSwitchManager.instance ?: return null
        return try {
            manager.javaClass.getMethod("selectedAudioDevice").invoke(manager)?.javaClass?.simpleName
        } catch (e: Exception) {
            null
        }
    }

    /** The output kind of an audio device type, named the way the app reads it. */
    private fun routeName(type: Int): String = when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "speaker"
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "earpiece"
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO, AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "bluetooth"
        AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "wired"
        else -> "other"
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
        shareChannel = null
        shareExecutor.shutdown()
        super.onDestroy()
    }

    /// Takes the files another app shared into Bhromon. Each one is copied into the app's
    /// cache first, because the other app's read permission ends with this activity. The
    /// copies run off the main thread, and Dart is told once they are ready.
    private fun handleShareIntent(incoming: Intent?) {
        if (incoming == null) return
        val action = incoming.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return
        val uris = shareUris(incoming)
        val text = incoming.getStringExtra(Intent.EXTRA_TEXT)
        if (uris.isEmpty() && text == null) return
        shareExecutor.execute {
            cleanOldShares()
            val copied = uris.map { copyShared(it) }
            runOnUiThread {
                pendingShares.addAll(copied)
                if (text != null) pendingShares.add(mapOf("text" to text))
                if (pendingShares.isNotEmpty()) {
                    shareChannel?.invokeMethod("sharesReady", null)
                }
            }
        }
    }

    /// The files of a share: the stream in EXTRA_STREAM, or the clip data when the sender
    /// put the files there instead.
    private fun shareUris(incoming: Intent): List<Uri> {
        val uris = mutableListOf<Uri>()
        if (incoming.action == Intent.ACTION_SEND) {
            streamExtra(incoming)?.let { uris.add(it) }
        } else {
            uris.addAll(streamExtras(incoming))
        }
        if (uris.isEmpty()) {
            val clip = incoming.clipData
            if (clip != null) {
                for (i in 0 until clip.itemCount) {
                    clip.getItemAt(i).uri?.let { uris.add(it) }
                }
            }
        }
        return uris.distinct()
    }

    @Suppress("DEPRECATION")
    private fun streamExtra(incoming: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            incoming.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            incoming.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        }

    @Suppress("DEPRECATION")
    private fun streamExtras(incoming: Intent): List<Uri> {
        val list: ArrayList<Uri>? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                incoming.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                incoming.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            }
        return list?.filterNotNull() ?: emptyList()
    }

    /// Copies one shared file into the cache. A file that cannot be read, or is larger than
    /// the biggest size a destination takes, keeps no path, so Dart refuses it with the
    /// reason. The name and size are sent either way.
    private fun copyShared(uri: Uri): Map<String, Any?> {
        var name = "file"
        var size = -1L
        try {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameIndex >= 0 && !cursor.isNull(nameIndex)) {
                        name = cursor.getString(nameIndex)
                    }
                    val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                        size = cursor.getLong(sizeIndex)
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(SHARE_LOG, "could not read the name of a shared file", e)
        }
        val mime = contentResolver.getType(uri)
        if (!name.contains('.')) {
            val ext = mime?.let { MimeTypeMap.getSingleton().getExtensionFromMimeType(it) }
            if (ext != null) name = "$name.$ext"
        }
        val refused: Map<String, Any?> =
            mapOf("name" to name, "sizeBytes" to size, "path" to null, "mimeType" to mime)
        if (size > MAX_SHARE_COPY_BYTES) return refused
        val dir = File(cacheDir, SHARE_DIR)
        if (!dir.exists() && !dir.mkdirs()) return refused
        val safeName = name.replace(Regex("[^A-Za-z0-9._-]"), "_").takeLast(120)
        val dest = File(dir, "${UUID.randomUUID()}_$safeName")
        val copied = try {
            copyStream(uri, dest)
        } catch (e: Exception) {
            Log.w(SHARE_LOG, "could not copy a shared file", e)
            -1L
        }
        if (copied < 0) {
            dest.delete()
            return refused
        }
        if (copied > MAX_SHARE_COPY_BYTES) {
            dest.delete()
            return mapOf("name" to name, "sizeBytes" to copied, "path" to null, "mimeType" to mime)
        }
        return mapOf(
            "name" to name,
            "sizeBytes" to copied,
            "path" to dest.absolutePath,
            "mimeType" to mime,
        )
    }

    /// Streams [uri] into [dest], and stops once the largest size has been passed, so a
    /// huge file never fills the cache. Returns the bytes read, or -1 with no stream.
    private fun copyStream(uri: Uri, dest: File): Long {
        val source = contentResolver.openInputStream(uri) ?: return -1L
        var total = 0L
        source.use { input ->
            dest.outputStream().use { output ->
                val buffer = ByteArray(64 * 1024)
                while (total <= MAX_SHARE_COPY_BYTES) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    output.write(buffer, 0, read)
                    total += read
                }
            }
        }
        return total
    }

    /// Removes shared copies older than a day. A share is taken within moments, so this
    /// clears only the files that were never taken, for example after the app was closed.
    private fun cleanOldShares() {
        val cutoff = System.currentTimeMillis() - SHARE_TTL_MS
        File(cacheDir, SHARE_DIR).listFiles()?.forEach { file ->
            if (file.lastModified() < cutoff) file.delete()
        }
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
