package app.vehicoule

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
import io.flutter.plugin.common.MethodChannel

/**
 * Keeps downloads going with the app in the background: a foreground service, only while
 * a download runs (Dart's DownloadsService starts and stops it), with a progress
 * notification updated at the core's pace (≤ 2/s).
 */
class DownloadService : Service() {
    data class Progress(val title: String, val done: Long, val total: Long, val count: Int)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Called after startForegroundService: startForeground must come first, even when
        // a stop already came (a download done at once), or the system kills the app.
        try {
            val n = notification(this, progress ?: Progress("", 0, -1, 1))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(ID, n)
            }
        } catch (e: RuntimeException) {
            // Android 14+: ForegroundServiceStartNotAllowedException (an IllegalStateException)
            // or a SecurityException (Android 15's data sync time is used up). The download
            // goes on in the app; the notification alone shows it.
            failed(e)
            progress?.let { update(this, it) }
            stopSelf()
            return START_NOT_STICKY
        }
        running = this
        if (progress == null) finish()
        // Killed with the app: the core resumes pending downloads at the next start.
        return START_NOT_STICKY
    }

    /** Android 15's limit for data sync (6 h a day): the download goes on in the app, Dart
     *  keeps sending updates (the notification alone) until its stop. */
    override fun onTimeout(startId: Int, fgsType: Int) = finish()

    override fun onDestroy() {
        if (running === this) running = null
        super.onDestroy()
    }

    private fun finish() {
        if (running === this) running = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    companion object {
        private const val CHANNEL = "downloads"
        private const val ID = 2001

        /** The latest progress, for the service's first notification; null once stopped. */
        @Volatile private var progress: Progress? = null

        /** The service, while in the foreground (main thread only). */
        private var running: DownloadService? = null

        /** Dart's downloads channel (MainActivity), for the refusals. */
        var channel: MethodChannel? = null

        fun start(context: Context, p: Progress) {
            progress = p
            if (running != null) return update(context, p)
            val intent = Intent(context, DownloadService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: IllegalStateException) {
                // Android 12+ with the app in the background (a download resumed by the
                // network coming back): no service, the notification alone.
                failed(e)
                update(context, p)
            }
        }

        fun update(context: Context, p: Progress) {
            progress = p
            context.getSystemService(NotificationManager::class.java).notify(ID, notification(context, p))
        }

        /** Idempotent, and safe before the service is up: onStartCommand sees no progress
         *  and leaves the foreground at once. */
        fun stop(context: Context) {
            progress = null
            running?.finish()
            context.getSystemService(NotificationManager::class.java).cancel(ID)
        }

        private fun failed(e: Exception) {
            channel?.invokeMethod("failed", "${e.javaClass.simpleName}: ${e.message}")
        }

        private fun notification(context: Context, p: Progress): Notification {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.getSystemService(NotificationManager::class.java).createNotificationChannel(
                    NotificationChannel(
                        CHANNEL,
                        context.getString(R.string.downloads_channel),
                        NotificationManager.IMPORTANCE_LOW,
                    ),
                )
            }
            val open = PendingIntent.getActivity(
                context,
                0,
                context.packageManager.getLaunchIntentForPackage(context.packageName),
                PendingIntent.FLAG_IMMUTABLE,
            )
            val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }
            b
                .setSmallIcon(R.drawable.ic_stat_mochi)
                .setContentTitle(p.title.ifEmpty { context.getString(R.string.downloads_title) })
                .setContentIntent(open)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setShowWhen(false)
            if (p.count > 1) {
                b.setContentText(
                    context.resources.getQuantityString(R.plurals.downloads_running, p.count, p.count),
                )
            }
            if (p.total > 0) {
                b.setProgress(1000, (p.done * 1000 / p.total).toInt(), false)
            } else {
                b.setProgress(0, 0, true)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                b.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            }
            return b.build()
        }
    }
}
