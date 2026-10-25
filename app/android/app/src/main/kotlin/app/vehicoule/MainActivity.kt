package app.vehicoule

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * audio_service's activity (the UI and the media session share one engine), plus the
 * app's channels: notifications (permission, native labels), downloads (the foreground
 * service) and update (the installer).
 */
class MainActivity : AudioServiceActivity() {
    private var permission: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android 12+: once Flutter draws, the splash fades out (spec UI §6.10, 200 ms).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            splashScreen.setOnExitAnimationListener { view ->
                view.animate().alpha(0f).setDuration(200).withEndAction { view.remove() }.start()
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val context = applicationContext

        MethodChannel(messenger, "app.vehicoule/notifications").setMethodCallHandler { call, result ->
            when (call.method) {
                "request" -> requestNotifications(result)
                "labels" -> result.success(
                    mapOf(
                        "like" to getString(R.string.notif_like),
                        "unlike" to getString(R.string.notif_unlike),
                        "stop" to getString(R.string.notif_stop),
                        "channel" to getString(R.string.playback_channel),
                    ),
                )
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "app.vehicoule/downloads").setMethodCallHandler { call, result ->
            when (call.method) {
                "start", "update" -> {
                    val progress = DownloadService.Progress(
                        title = call.argument<String>("title") ?: "",
                        done = call.argument<Number>("done")?.toLong() ?: 0,
                        total = call.argument<Number>("total")?.toLong() ?: -1,
                        count = call.argument<Int>("count") ?: 1,
                    )
                    if (call.method == "start") DownloadService.start(context, progress)
                    else DownloadService.update(context, progress)
                    result.success(null)
                }
                "stop" -> {
                    DownloadService.stop(context)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "app.vehicoule/update").setMethodCallHandler { call, result ->
            when (call.method) {
                "install" -> {
                    Installer.install(context, call.argument<String>("path")!!)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Android 13+ asks; before, notifications need no permission. */
    private fun requestNotifications(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        permission?.success(false)
        permission = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATIONS)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != NOTIFICATIONS) return
        permission?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        permission = null
    }

    private companion object {
        const val NOTIFICATIONS = 1
    }
}
