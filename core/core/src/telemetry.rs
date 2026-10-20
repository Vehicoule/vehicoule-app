//! Opt-in error and performance reports (Sentry). Nothing leaves before `set_enabled(true)`,
//! and `scrub` rebuilds every event from an allowlist: never a title, artist, search, URL,
//! playlist content or account id. Logs export for bug reports.

use std::io::Write;
use std::panic::PanicHookInfo;
use std::sync::{Arc, LazyLock, Mutex, PoisonError};
use std::time::Duration;

use plugin_host::{CallError, CallReport, Capability};
use sentry::protocol::{
    Context, DeviceContext, Event, Exception, Frame, Level, Mechanism, OsContext, Stacktrace, Unit,
};
use sentry::types::Dsn;
use sentry::{ClientOptions, Hub, Scope, TransportFactory};

use crate::app::app;
use crate::error::CoreError;
use crate::logs::{self, redact};
use crate::router::cap_name;

/// Read at compile time: without it, telemetry is impossible.
const DSN: Option<&str> = option_env!("VEHICOULE_SENTRY_DSN");

/// The only tags that leave.
const TAGS: [&str; 7] = [
    "error_kind",
    "plugin",
    "plugin_version",
    "capability",
    "app_version",
    "os",
    "device_model",
];

/// Our own hub: sentry's per-thread hubs copy the main hub's client when a thread first uses
/// one, so a client bound later on `Hub::main()` would never reach running workers.
static HUB: LazyLock<Arc<Hub>> =
    LazyLock::new(|| Arc::new(Hub::new(None, Arc::new(Scope::default()))));

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[allow(clippy::enum_variant_names, reason = "names fixed by the bridge API")]
pub enum PerfMetric {
    TapToFirstSoundMs,
    ResolveMs,
    StartupMs,
}

/// Opt-in. `false` closes the client: nothing more is sent. `true` without a DSN in the
/// build does nothing.
pub(crate) fn set_enabled(on: bool) {
    let dsn = DSN.filter(|_| on).and_then(|d| d.parse().ok());
    bind(dsn.map(|dsn| options(dsn, Arc::new(sentry::transports::DefaultTransportFactory))));
}

fn options(dsn: Dsn, transport: Arc<dyn TransportFactory>) -> ClientOptions {
    // Built by hand, not through `sentry::init`: no default integrations (contexts would add
    // the hostname), no environment variables read, no breadcrumbs, no PII.
    let mut o = ClientOptions::default();
    o.dsn = Some(dsn);
    o.release = Some(app().cfg.app_version.clone().into());
    o.environment = Some(
        if cfg!(debug_assertions) {
            "development"
        } else {
            "production"
        }
        .into(),
    );
    o.max_breadcrumbs = 0;
    o.send_default_pii = false;
    o.before_send = Some(Arc::new(scrub));
    o.transport = Some(transport);
    o
}

fn bind(options: Option<ClientOptions>) {
    static LOCK: Mutex<()> = Mutex::new(());
    let _guard = LOCK.lock().unwrap_or_else(PoisonError::into_inner);
    if let Some(old) = HUB.client() {
        HUB.bind_client(None);
        old.close(Some(Duration::from_secs(2)));
    }
    if let Some(options) = options {
        HUB.configure_scope(|s| {
            s.clear();
            s.set_tag("app_version", &app().cfg.app_version);
            s.set_tag("os", os());
        });
        HUB.bind_client(Some(Arc::new(options.into())));
    }
}

fn enabled() -> bool {
    HUB.client().is_some()
}

fn os() -> String {
    format!("{:?}", app().cfg.platform).to_ascii_lowercase()
}

/// The variant's name, never its payload.
fn kind(e: &CoreError) -> &'static str {
    match e {
        CoreError::Network => "network",
        CoreError::ProviderWall => "provider-wall",
        CoreError::RateLimited => "rate-limited",
        CoreError::BudgetExceeded => "budget-exceeded",
        CoreError::NotFound => "not-found",
        CoreError::Expired => "expired",
        CoreError::Internal(_) => "internal",
        CoreError::Offline => "offline",
        CoreError::InvalidFeed => "invalid-feed",
        CoreError::NoPlugin(_) => "no-plugin",
    }
}

pub(crate) fn report_error(
    e: &CoreError,
    plugin: Option<(&str, &str)>,
    capability: Option<Capability>,
) {
    if !enabled() {
        return;
    }
    let kind = kind(e);
    let mut event = Event {
        level: Level::Error,
        exception: vec![Exception {
            ty: kind.into(),
            stacktrace: sentry::integrations::backtrace::current_stacktrace(),
            ..Default::default()
        }]
        .into(),
        ..Default::default()
    };
    let capability = capability.or(match e {
        CoreError::NoPlugin(c) => Some(*c),
        _ => None,
    });
    event.tags.insert("error_kind".into(), kind.into());
    if let Some((id, version)) = plugin {
        event.tags.insert("plugin".into(), id.into());
        event.tags.insert("plugin_version".into(), version.into());
    }
    if let Some(c) = capability {
        event.tags.insert("capability".into(), cap_name(c).into());
    }
    HUB.capture_event(event);
}

pub(crate) fn report_perf(m: PerfMetric, value_ms: u64) {
    perf(m, value_ms, None);
}

fn perf(m: PerfMetric, value_ms: u64, plugin: Option<(&str, &str)>) {
    if !enabled() {
        return;
    }
    let name = match m {
        PerfMetric::TapToFirstSoundMs => "tap_to_first_sound",
        PerfMetric::ResolveMs => "resolve",
        PerfMetric::StartupMs => "startup",
    };
    let mut metric = sentry::metrics::distribution(name, value_ms as f64)
        .unit(Unit::Millisecond)
        .attribute("os", os());
    if let Some((id, version)) = plugin {
        metric = metric
            .attribute("plugin", id.to_string())
            .attribute("plugin_version", version.to_string());
    }
    HUB.capture_metric(metric);
}

/// From the plugin-host's call reports: `ResolveMs` for each resolve, a typed error for each
/// failure (`not-found` is the router's normal path, not an error).
pub(crate) fn on_call(r: &CallReport) {
    if !enabled() {
        return;
    }
    let version = app()
        .plugins
        .loaded()
        .iter()
        .find(|p| p.id() == r.plugin)
        .map(|p| p.manifest().version.clone())
        .unwrap_or_default();
    let plugin = Some((r.plugin.as_str(), version.as_str()));
    match &r.outcome {
        Ok(()) if r.capability == Capability::Resolve => {
            perf(PerfMetric::ResolveMs, r.wall_ms, plugin);
        }
        Ok(()) | Err(CallError::NotFound | CallError::Unsupported) => {}
        Err(e) => report_error(
            &CoreError::from_call(e.clone(), r.capability),
            plugin,
            Some(r.capability),
        ),
    }
}

/// Called by the panic hook.
pub(crate) fn report_panic(info: &PanicHookInfo<'_>) {
    if enabled() {
        let event =
            sentry::integrations::panic::PanicIntegration::new().event_from_panic_info(info);
        HUB.capture_event(event);
    }
}

/// `before_send`: a new event with only the error type, allowed tags (plugin id and version,
/// capability, app version, OS, device model), OS and device model contexts, and stack
/// frames. Exception messages go through `logs::redact`; request, user, breadcrumbs, extra,
/// frame variables and source lines are dropped.
pub(crate) fn scrub(event: Event<'static>) -> Option<Event<'static>> {
    let r = |s: Option<String>| s.map(|s| redact(&s));
    let frames = |s: Stacktrace| Stacktrace {
        frames: s
            .frames
            .into_iter()
            .map(|f| Frame {
                function: r(f.function),
                symbol: r(f.symbol),
                module: r(f.module),
                package: r(f.package),
                filename: r(f.filename),
                abs_path: r(f.abs_path),
                lineno: f.lineno,
                colno: f.colno,
                in_app: f.in_app,
                image_addr: f.image_addr,
                instruction_addr: f.instruction_addr,
                symbol_addr: f.symbol_addr,
                addr_mode: f.addr_mode,
                ..Default::default()
            })
            .collect(),
        frames_omitted: s.frames_omitted,
        ..Default::default()
    };
    let exception: Vec<Exception> = event
        .exception
        .values
        .into_iter()
        .map(|x| Exception {
            ty: redact(&x.ty),
            value: r(x.value),
            stacktrace: x.stacktrace.map(frames),
            mechanism: x.mechanism.map(|m| Mechanism {
                ty: m.ty,
                handled: m.handled,
                ..Default::default()
            }),
            ..Default::default()
        })
        .collect();
    let contexts = event
        .contexts
        .into_iter()
        .filter_map(|(k, c)| {
            match c {
                Context::Os(os) => Some(
                    OsContext {
                        name: os.name,
                        version: os.version,
                        ..Default::default()
                    }
                    .into(),
                ),
                Context::Device(d) => Some(
                    DeviceContext {
                        model: d.model,
                        ..Default::default()
                    }
                    .into(),
                ),
                _ => None,
            }
            .map(|c| (k, c))
        })
        .collect();
    let tags = event
        .tags
        .into_iter()
        .filter(|(k, _)| TAGS.contains(&k.as_str()))
        .map(|(k, v)| (k, redact(&v)))
        .collect();
    Some(Event {
        event_id: event.event_id,
        level: event.level,
        platform: event.platform,
        timestamp: event.timestamp,
        release: event.release,
        dist: event.dist,
        environment: event.environment,
        sdk: event.sdk,
        message: r(event.message),
        exception: exception.into(),
        stacktrace: event.stacktrace.map(frames),
        contexts,
        tags,
        ..Default::default()
    })
}

/// `logs::recent()` as text, one line each, oldest first (already masked).
pub(crate) fn export_logs(dest: &str) -> Result<(), CoreError> {
    let io = |e: std::io::Error| CoreError::Internal(e.to_string());
    let mut out = std::io::BufWriter::new(std::fs::File::create(dest).map_err(io)?);
    for l in logs::recent() {
        writeln!(out, "{} {} {}: {}", l.at_ms, l.level, l.source, l.message).map_err(io)?;
    }
    out.flush().map_err(io)
}

#[cfg(test)]
mod tests {
    use sentry::protocol::{Breadcrumb, Request, User};
    use sentry::test::TestTransport;

    use super::*;

    const LEAK: &str = "play \"Halo\" https://x/y?q=beyonce";

    /// Telemetry is one global client: its tests take turns.
    fn serial() -> std::sync::MutexGuard<'static, ()> {
        static SERIAL: Mutex<()> = Mutex::new(());
        SERIAL.lock().unwrap_or_else(PoisonError::into_inner)
    }

    fn enable_for_test(t: &Arc<TestTransport>) {
        crate::app::test_app(); // config, and the panic hook
        let dsn = "https://public@sentry.test/1".parse().unwrap();
        bind(Some(options(dsn, Arc::new(t.clone()))));
    }

    fn sent_text(t: &TestTransport) -> String {
        let mut out = Vec::new();
        for e in t.fetch_and_clear_envelopes() {
            e.to_writer(&mut out).unwrap();
        }
        String::from_utf8_lossy(&out).into_owned()
    }

    #[test]
    fn telemetry_scrubs_titles_urls_queries() {
        let mut event = Event {
            message: Some(LEAK.into()),
            transaction: Some(LEAK.into()),
            exception: vec![Exception {
                ty: "panic".into(),
                value: Some(LEAK.into()),
                stacktrace: Some(Stacktrace {
                    frames: vec![Frame {
                        function: Some("vehicoule_core::player::play".into()),
                        context_line: Some(LEAK.into()),
                        vars: [("title".to_string(), "Halo".into())].into(),
                        ..Default::default()
                    }],
                    ..Default::default()
                }),
                ..Default::default()
            }]
            .into(),
            user: Some(User {
                email: Some("beyonce@x.y".into()),
                ..Default::default()
            }),
            request: Some(Request {
                url: "https://x/y?q=beyonce".parse().ok(),
                ..Default::default()
            }),
            breadcrumbs: vec![Breadcrumb {
                message: Some(LEAK.into()),
                ..Default::default()
            }]
            .into(),
            ..Default::default()
        };
        event.tags.insert("query".into(), "beyonce".into());
        event.tags.insert("error_kind".into(), "internal".into());
        event.extra.insert("title".into(), "Halo".into());
        let json = serde_json::to_string(&scrub(event).unwrap()).unwrap();
        for leak in ["Halo", "beyonce", "x/y", "\"query\"", "\"title\""] {
            assert!(!json.contains(leak), "{leak} in {json}");
        }
        assert!(json.contains("vehicoule_core::player::play"), "{json}");
        assert!(json.contains(r#""error_kind":"internal""#), "{json}");
        assert!(json.contains(r#"play \"…\" <url>"#), "{json}");

        // A real panic, through the hook, the client and `before_send`; scope data set by
        // anyone else on the hub never leaves either.
        let _g = serial();
        let t = TestTransport::new();
        enable_for_test(&t);
        HUB.configure_scope(|s| {
            s.set_tag("query", "beyonce");
            s.set_user(Some(User {
                username: Some("beyonce".into()),
                ..Default::default()
            }));
        });
        HUB.add_breadcrumb(Breadcrumb {
            message: Some(LEAK.into()),
            ..Default::default()
        });
        let _ = std::panic::catch_unwind(|| panic!("play \"Halo\" https://x/y?q=beyonce"));
        set_enabled(false);
        let sent = sent_text(&t);
        assert!(sent.contains(r#"play \"…\" <url>"#), "{sent}");
        for leak in ["Halo", "beyonce", "x/y", "\"query\""] {
            assert!(!sent.contains(leak), "{leak} in {sent}");
        }
    }

    #[test]
    fn typed_error_sends_variant_name_only() {
        let _g = serial();
        let t = TestTransport::new();
        enable_for_test(&t);
        report_error(
            &CoreError::Internal("track Halo failed".into()),
            Some(("fake", "1.2.3")),
            Some(Capability::Resolve),
        );
        set_enabled(false);
        let events = t.fetch_and_clear_events();
        let ev = events
            .iter()
            .find(|e| e.tags.get("plugin").map(String::as_str) == Some("fake"))
            .expect("the error is sent");
        let tag = |k: &str| ev.tags.get(k).map(String::as_str);
        assert_eq!(tag("error_kind"), Some("internal"));
        assert_eq!(tag("plugin_version"), Some("1.2.3"));
        assert_eq!(tag("capability"), Some("resolve"));
        assert_eq!(tag("app_version"), Some("0.1.0"));
        assert_eq!(tag("os"), Some("macos"));
        assert_eq!(ev.exception.values[0].ty, "internal");
        assert_eq!(ev.exception.values[0].value, None);
        let json = serde_json::to_string(&events).unwrap();
        assert!(!json.contains("Halo"), "{json}");
    }

    #[test]
    fn call_reports_feed_resolve_ms_and_typed_errors() {
        let _g = serial();
        let t = TestTransport::new();
        enable_for_test(&t);
        let call = |capability, outcome| CallReport {
            plugin: "probe-telemetry".into(),
            capability,
            fuel_used: 1,
            http_calls: 1,
            wall_ms: 321,
            outcome,
        };
        on_call(&call(Capability::Resolve, Ok(())));
        on_call(&call(Capability::Search, Err(CallError::NotFound)));
        on_call(&call(
            Capability::Lyrics,
            Err(CallError::ProviderWall("login for \"Halo\"".into())),
        ));
        set_enabled(false); // flushes the metrics batch
        let sent = sent_text(&t);
        assert!(sent.contains("\"resolve\""), "{sent}");
        assert!(sent.contains("321"), "{sent}");
        assert!(sent.contains(r#""error_kind":"provider-wall""#), "{sent}");
        assert!(!sent.contains("not-found"), "{sent}");
        assert!(!sent.contains("Halo"), "{sent}");
    }

    #[test]
    fn disabled_telemetry_sends_nothing() {
        let _g = serial();
        let t = TestTransport::new();
        enable_for_test(&t);
        set_enabled(false);
        assert!(!enabled());
        t.fetch_and_clear_envelopes();
        // No DSN in test builds: opting in is a no-op.
        if DSN.is_none() {
            set_enabled(true);
            assert!(!enabled());
        }
        report_error(&CoreError::Network, None, None);
        report_perf(PerfMetric::StartupMs, 12);
        on_call(&CallReport {
            plugin: "probe-telemetry".into(),
            capability: Capability::Resolve,
            fuel_used: 1,
            http_calls: 1,
            wall_ms: 5,
            outcome: Err(CallError::Internal("x".into())),
        });
        let _ = std::panic::catch_unwind(|| panic!("while disabled"));
        assert_eq!(t.fetch_and_clear_envelopes().len(), 0);
    }

    #[test]
    fn logs_are_exported_masked() {
        logs::push("info", "export-test", "GET https://a.b/c for \"Halo\"");
        let dest = std::env::temp_dir().join(format!("vehicoule-logs-{}.txt", std::process::id()));
        export_logs(dest.to_str().unwrap()).unwrap();
        let text = std::fs::read_to_string(&dest).unwrap();
        let _ = std::fs::remove_file(&dest);
        assert!(
            text.contains("info export-test: GET <url> for \"…\""),
            "{text}"
        );
        assert!(!text.contains("Halo"));
        assert_eq!(
            export_logs("/nonexistent-dir/x.txt").map_err(|e| matches!(e, CoreError::Internal(_))),
            Err(true)
        );
    }
}
