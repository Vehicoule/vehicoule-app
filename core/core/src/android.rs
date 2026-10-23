//! Android: rustls-platform-verifier checks certificates through the JVM (the system trust
//! store). `RustInit.initVerifier`, called first thing in `VehicouleApplication.onCreate`,
//! hands it the app's context; without it the first HTTPS handshake panics.

use jni::EnvUnowned;
use jni::errors::ThrowRuntimeExAndDefault;
use jni::objects::JObject;

/// `external fun initVerifier(context: Context)` of the Kotlin `object RustInit`.
#[unsafe(no_mangle)]
pub extern "system" fn Java_app_vehicoule_RustInit_initVerifier<'l>(
    mut env: EnvUnowned<'l>,
    _this: JObject<'l>,
    context: JObject<'l>,
) {
    env.with_env(|env| rustls_platform_verifier::android::init_with_env(env, context))
        .resolve::<ThrowRuntimeExAndDefault>();
}
