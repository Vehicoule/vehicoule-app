//! Capability routing: plugins in the user's order (else the default one), first useful answer wins.

use std::future::Future;

use plugin_host::{CallError, Capability, Plugin};

use crate::app::app;
use crate::error::CoreError;
use crate::library::plugins::capability_order;
use crate::logs;

/// Catalogue (and artwork, a subset of it): Deezer, then iTunes, then YouTube Music; every
/// other plugin after these, by id.
const DEFAULT_ORDER: [&str; 3] = ["deezer", "itunes", "ytmusic"];

/// The name stored in `capability_order` and shown in logs and previews.
pub(crate) fn cap_name(cap: Capability) -> &'static str {
    match cap {
        Capability::Search => "search",
        Capability::Suggest => "suggest",
        Capability::Entity => "entity",
        Capability::Resolve => "resolve",
        Capability::Lyrics => "lyrics",
        Capability::Radio => "radio",
    }
}

/// Sort key: the user's position, then the default position, then the id.
fn rank(user: &[String], id: &str) -> (usize, usize, String) {
    let user_pos = user.iter().position(|u| u == id).unwrap_or(user.len());
    let default_pos = DEFAULT_ORDER.iter().position(|d| *d == id);
    (
        user_pos,
        default_pos.unwrap_or(DEFAULT_ORDER.len()),
        id.into(),
    )
}

/// Loaded plugins exporting `cap`, in the user's order, else the default one.
pub(crate) async fn ordered(cap: Capability) -> Vec<Plugin> {
    sorted(cap_name(cap), |p| p.capabilities().contains(&cap)).await
}

/// Artwork sources: every loaded plugin, in the user's `artwork` order, else the default one
/// (deezer, itunes...).
pub(crate) async fn ordered_artwork() -> Vec<Plugin> {
    sorted("artwork", |_| true).await
}

async fn sorted(name: &'static str, keep: impl Fn(&Plugin) -> bool) -> Vec<Plugin> {
    let user = app()
        .db
        .read(move |c| capability_order(c, name))
        .await
        .unwrap_or_else(|e| {
            logs::push("error", "router", &e.to_string());
            Vec::new()
        });
    let mut plugins: Vec<Plugin> = app().plugins.loaded().into_iter().filter(keep).collect();
    plugins.sort_by_key(|p| rank(&user, p.id()));
    plugins
}

/// The next plugin may still answer: not-found, rate-limited, provider-wall, budget-exceeded,
/// capability missing. Network, expired and internal stop the routing.
pub(crate) fn falls_through(e: &CallError) -> bool {
    matches!(
        e,
        CallError::NotFound
            | CallError::RateLimited
            | CallError::ProviderWall(_)
            | CallError::BudgetExceeded(_)
            | CallError::Unsupported
    )
}

/// Calls `f` on each plugin of `ordered(cap)` until one answers or one fails hard.
pub(crate) async fn first_ok<T, F, Fut>(cap: Capability, f: F) -> Result<(Plugin, T), CoreError>
where
    F: FnMut(Plugin) -> Fut,
    Fut: Future<Output = Result<T, CallError>>,
{
    try_in_order(ordered(cap).await, cap, f).await
}

/// `first_ok` over any list. All soft failures: the last one (a plugin's `NotFound` wins
/// over a later `Unsupported`); an empty list: `NoPlugin(cap)`.
async fn try_in_order<P: Clone, T, F, Fut>(
    items: Vec<P>,
    cap: Capability,
    mut f: F,
) -> Result<(P, T), CoreError>
where
    F: FnMut(P) -> Fut,
    Fut: Future<Output = Result<T, CallError>>,
{
    let mut last = CallError::Unsupported;
    for item in items {
        match f(item.clone()).await {
            Ok(t) => return Ok((item, t)),
            Err(e) if !falls_through(&e) => return Err(CoreError::from_call(e, cap)),
            Err(CallError::Unsupported) => {}
            Err(e) => last = e,
        }
    }
    Err(CoreError::from_call(last, cap))
}

#[cfg(test)]
mod tests {
    use plugin_host::{Budget, CallError, Capability};

    use super::*;
    use crate::error::CoreError;

    #[test]
    fn default_order_puts_deezer_first() {
        let mut ids = vec!["ytmusic", "itunes", "deezer", "zz"];
        ids.sort_by_key(|id| rank(&[], id));
        assert_eq!(ids, ["deezer", "itunes", "ytmusic", "zz"]);
        // The user's order comes first, the default order after it.
        let user = ["zz".to_string(), "ytmusic".to_string()];
        ids.sort_by_key(|id| rank(&user, id));
        assert_eq!(ids, ["zz", "ytmusic", "deezer", "itunes"]);
    }

    #[test]
    fn routing_falls_through_on_the_four_soft_errors() {
        for e in [
            CallError::NotFound,
            CallError::RateLimited,
            CallError::ProviderWall("login".into()),
            CallError::BudgetExceeded(Budget::Fuel),
            CallError::Unsupported,
        ] {
            assert!(falls_through(&e), "{e:?}");
        }
        for e in [
            CallError::Network("dns".into()),
            CallError::Expired,
            CallError::Internal("bug".into()),
        ] {
            assert!(!falls_through(&e), "{e:?}");
        }
    }

    #[tokio::test]
    async fn first_ok_tries_next_plugin() {
        let cap = Capability::Search;
        let tried = std::sync::Mutex::new(Vec::new());
        let call = |answers: [Result<u8, CallError>; 2]| {
            let tried = &tried;
            try_in_order(vec![0usize, 1], cap, move |i| {
                tried.lock().unwrap().push(i);
                let r = answers[i].clone();
                async move { r }
            })
        };
        let r = call([Err(CallError::NotFound), Ok(2)]).await;
        assert_eq!(r, Ok((1, 2)));
        assert_eq!(std::mem::take(&mut *tried.lock().unwrap()), [0, 1]);

        let r = call([Err(CallError::Network("down".into())), Ok(2)]).await;
        assert_eq!(r, Err(CoreError::Network));
        assert_eq!(*tried.lock().unwrap(), [0]);

        // Nobody answers: the last soft error, or `NoPlugin` when nothing exports it.
        let none = try_in_order(Vec::<usize>::new(), cap, |_| async { Ok::<u8, _>(0) });
        assert_eq!(none.await, Err(CoreError::NoPlugin(cap)));
        let r = try_in_order(vec![0, 1], cap, |i| async move {
            Err::<u8, _>([CallError::NotFound, CallError::Unsupported][i].clone())
        });
        assert_eq!(r.await, Err(CoreError::NotFound));
    }
}
