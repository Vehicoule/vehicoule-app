package app.vehicoule

import android.content.Context

/** The Rust core's JNI entry points (core/core/src/android.rs). */
object RustInit {
    init {
        System.loadLibrary("vehicoule_core")
    }

    /** rustls-platform-verifier reaches Android's trust store through [context]. */
    external fun initVerifier(context: Context)
}
