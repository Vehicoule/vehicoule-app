//! Updates, telemetry, diagnostics.

use crate::error::CoreError;
use crate::logs::{self, LogLine};
use crate::telemetry::{self, PerfMetric};
use crate::updates::{self, UpdateInfo};

/// At most once a day (Dart asks after the first frame; `App` again hourly). A newer version
/// also comes as `Notice::UpdateAvailable`, the one signal the UI shows.
pub async fn check_updates() -> Result<Option<UpdateInfo>, CoreError> {
    updates::check_if_due().await
}

/// The verified APK's path.
pub async fn download_update(info: UpdateInfo) -> Result<String, CoreError> {
    updates::download_update(&info).await
}

pub fn report_perf(metric: PerfMetric, value_ms: u64) {
    telemetry::report_perf(metric, value_ms);
}

/// An uncaught Dart error: its type and stack, filtered before sending (opt-in only).
pub fn report_dart_error(kind: String, stack: String) {
    telemetry::report_dart_error(&kind, &stack);
}

/// The last 2000 log lines, oldest first, already masked.
pub fn diagnostics() -> Vec<LogLine> {
    logs::recent()
}

pub fn export_logs(dest: String) -> Result<(), CoreError> {
    telemetry::export_logs(&dest)
}
