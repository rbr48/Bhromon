package com.bhromon.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Keeps a call's microphone, and the camera on a video call, running while the
 * app is in the background. Android stops both for a backgrounded app unless a
 * foreground service of the matching type is running.
 */
class CallOngoingService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val camera = intent?.getBooleanExtra(EXTRA_CAMERA, false) ?: false
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
            .setContentTitle("Bhromon")
            .setContentText("Call in progress")
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
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

    companion object {
        private const val CHANNEL_ID = "bhromon_ongoing_call"
        private const val NOTIFICATION_ID = 4711
        private const val EXTRA_CAMERA = "camera"

        fun start(context: Context, camera: Boolean) {
            val intent = Intent(context, CallOngoingService::class.java)
                .putExtra(EXTRA_CAMERA, camera)
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
