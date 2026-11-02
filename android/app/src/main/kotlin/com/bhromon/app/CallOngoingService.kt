package com.bhromon.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.os.Build
import android.os.IBinder

/**
 * Keeps a call's microphone, and the camera on a video call, running while the
 * app is in the background. Android stops both for a backgrounded app unless a
 * foreground service of the matching type is running.
 */
class CallOngoingService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    private var title = "Bhromon"
    private var text = "Call in progress"
    private var hangUpLabel = "Hang up"

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_HANG_UP) {
            // The notification's Hang up button. The app ends the call, which
            // stops this service; with no app left to ask, it stops itself.
            val listener = onHangUp
            if (listener != null) listener() else stopSelf()
            return START_NOT_STICKY
        }
        val camera = intent?.getBooleanExtra(EXTRA_CAMERA, false) ?: false
        intent?.getStringExtra(EXTRA_TITLE)?.let { title = it }
        intent?.getStringExtra(EXTRA_TEXT)?.let { text = it }
        intent?.getStringExtra(EXTRA_HANG_UP)?.let { hangUpLabel = it }
        val notification = buildNotification()
        if (!enterForeground(notification, camera) && !(camera && enterForeground(notification, false))) {
            // The system refused (for example, a permission was withdrawn). The
            // call goes on; it may only pause while the app is in the background.
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun enterForeground(notification: Notification, camera: Boolean): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                var types = ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                if (camera) {
                    types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
                }
                startForeground(NOTIFICATION_ID, notification, types)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun buildNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Ongoing calls", NotificationManager.IMPORTANCE_LOW)
            )
            Notification.Builder(this, CHANNEL_ID)
        } else {
            legacyBuilder()
        }
        builder
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
        val hangUp = PendingIntent.getService(
            this,
            1,
            Intent(this, CallOngoingService::class.java).setAction(ACTION_HANG_UP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            builder.addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(this, android.R.drawable.ic_menu_close_clear_cancel),
                    hangUpLabel,
                    hangUp
                ).build()
            )
        } else {
            addLegacyAction(builder, hangUp)
        }
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        if (launch != null) {
            builder.setContentIntent(
                PendingIntent.getActivity(
                    this,
                    0,
                    launch,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
            )
        }
        return builder.build()
    }

    @Suppress("DEPRECATION")
    private fun legacyBuilder(): Notification.Builder = Notification.Builder(this)

    @Suppress("DEPRECATION")
    private fun addLegacyAction(builder: Notification.Builder, intent: PendingIntent) {
        builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, hangUpLabel, intent)
    }

    companion object {
        private const val CHANNEL_ID = "bhromon_ongoing_call"
        private const val NOTIFICATION_ID = 4711
        private const val EXTRA_CAMERA = "camera"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_HANG_UP = "hangUp"
        private const val ACTION_HANG_UP = "com.bhromon.app.CALL_HANG_UP"

        /** Called when the notification's Hang up button is pressed. Set by MainActivity. */
        @Volatile
        var onHangUp: (() -> Unit)? = null

        fun start(context: Context, camera: Boolean, title: String?, text: String?, hangUp: String?) {
            val intent = Intent(context, CallOngoingService::class.java)
                .putExtra(EXTRA_CAMERA, camera)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_TEXT, text)
                .putExtra(EXTRA_HANG_UP, hangUp)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CallOngoingService::class.java))
        }
    }
}
