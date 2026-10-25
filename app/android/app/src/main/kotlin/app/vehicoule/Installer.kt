package app.vehicoule

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import java.io.File

/**
 * Hands the update the core downloaded and verified to the system installer, which asks
 * the user (and, the first time, for the "install unknown apps" permission).
 */
object Installer {
    fun install(context: Context, path: String) {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", File(path))
        context.startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }
}
