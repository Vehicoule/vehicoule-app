//! The one error type the app sees. Every plugin-host and library error is mapped here.

use plugin_host::{CallError, Capability};

use crate::library::DbError;

#[derive(Debug, Clone, PartialEq)]
pub enum CoreError {
    Network,
    ProviderWall,
    RateLimited,
    BudgetExceeded,
    NotFound,
    Expired,
    /// A bug: corrupt store, failed migration, a plugin's internal error...
    Internal(String),
    Offline,
    /// No enabled plugin exports this capability.
    NoPlugin(Capability),
}

impl CoreError {
    #[allow(dead_code, reason = "used by the router (task 2)")]
    /// As `From<CallError>`, but `Unsupported` becomes `NoPlugin(cap)`.
    pub(crate) fn from_call(e: CallError, cap: Capability) -> CoreError {
        match e {
            CallError::Unsupported => CoreError::NoPlugin(cap),
            e => e.into(),
        }
    }
}

impl From<CallError> for CoreError {
    fn from(e: CallError) -> Self {
        match e {
            CallError::Network(_) => CoreError::Network,
            CallError::ProviderWall(_) => CoreError::ProviderWall,
            CallError::RateLimited => CoreError::RateLimited,
            CallError::NotFound => CoreError::NotFound,
            CallError::Expired => CoreError::Expired,
            CallError::Internal(s) => CoreError::Internal(s),
            CallError::BudgetExceeded(_) => CoreError::BudgetExceeded,
            // The router only calls plugins that export the capability: use `from_call`.
            CallError::Unsupported => {
                CoreError::Internal("plugin called for a capability it does not export".into())
            }
        }
    }
}

impl From<DbError> for CoreError {
    fn from(e: DbError) -> Self {
        match e {
            // An unknown or refused argument (playlist, entry, reserved key...), not a bug.
            DbError::Invalid(_) => CoreError::NotFound,
            DbError::Sqlite(_) | DbError::Migration(_) => CoreError::Internal(e.to_string()),
        }
    }
}

#[cfg(test)]
mod tests {
    use plugin_host::{Budget, CallError, Capability};

    use super::*;
    use crate::library::{Db, DbError, http_cache};

    #[test]
    fn call_errors_map_to_core_errors() {
        let cases = [
            (CallError::Network("dns".into()), CoreError::Network),
            (
                CallError::ProviderWall("login".into()),
                CoreError::ProviderWall,
            ),
            (CallError::RateLimited, CoreError::RateLimited),
            (CallError::NotFound, CoreError::NotFound),
            (CallError::Expired, CoreError::Expired),
            (
                CallError::Internal("x".into()),
                CoreError::Internal("x".into()),
            ),
        ];
        for (e, want) in cases {
            assert_eq!(CoreError::from(e), want);
        }
        for b in [Budget::Fuel, Budget::Time, Budget::Memory, Budget::Http] {
            assert_eq!(
                CoreError::from(CallError::BudgetExceeded(b)),
                CoreError::BudgetExceeded
            );
        }
        assert_eq!(
            CoreError::from_call(CallError::Unsupported, Capability::Lyrics),
            CoreError::NoPlugin(Capability::Lyrics)
        );
        assert_eq!(
            CoreError::from_call(CallError::NotFound, Capability::Lyrics),
            CoreError::NotFound
        );
        // Without the capability at hand, a call to an unexported one is a routing bug.
        assert!(matches!(
            CoreError::from(CallError::Unsupported),
            CoreError::Internal(_)
        ));
    }

    #[test]
    fn db_errors_map_to_core_errors() {
        assert_eq!(
            CoreError::from(DbError::Invalid("no playlist".into())),
            CoreError::NotFound
        );
        assert_eq!(
            CoreError::from(DbError::Sqlite("disk I/O".into())),
            CoreError::Internal("sqlite error: disk I/O".into())
        );
        assert_eq!(
            CoreError::from(DbError::Migration("0002".into())),
            CoreError::Internal("migration error: 0002".into())
        );
    }

    #[test]
    fn corrupt_stored_value_is_internal() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| {
            tx.tx.execute(
                "INSERT INTO http_cache (key, plugin_id, status, url, headers, body, stored_at, expires_at)
                 VALUES (?1, 'p', 200, 'u', 'not json', x'', 0, 0)",
                [[7u8; 32].as_slice()],
            )
        })
        .unwrap();
        let err = db
            .read_blocking(|c| http_cache::get(c, &[7; 32]))
            .unwrap_err();
        assert!(matches!(err, DbError::Sqlite(_)), "{err:?}");
        assert!(matches!(CoreError::from(err), CoreError::Internal(_)));
    }
}
