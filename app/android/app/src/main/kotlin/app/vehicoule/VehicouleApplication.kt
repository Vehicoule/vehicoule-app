package app.vehicoule

import android.app.Application

class VehicouleApplication : Application() {
    override fun onCreate() {
        // Before anything (Flutter, the core) can make an HTTPS request.
        RustInit.initVerifier(this)
        super.onCreate()
    }
}
