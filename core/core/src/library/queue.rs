use rusqlite::{Connection, OptionalExtension};

use super::Tx;

/// Upserts the single saved queue (row `id = 1`). The JSON shape is the player's business.
pub fn save(tx: &Tx, json: &str) -> rusqlite::Result<()> {
    tx.tx.execute(
        "INSERT INTO queue_state (id, state) VALUES (1, ?1)
         ON CONFLICT (id) DO UPDATE SET state = excluded.state",
        [json],
    )?;
    Ok(())
}

pub fn load(c: &Connection) -> rusqlite::Result<Option<String>> {
    c.query_row("SELECT state FROM queue_state WHERE id = 1", [], |r| {
        r.get(0)
    })
    .optional()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::library::Db;

    #[test]
    fn queue_roundtrip() {
        let db = Db::open_in_memory().unwrap();
        assert_eq!(db.read_blocking(load).unwrap(), None);
        db.write_blocking(|tx| save(tx, r#"{"a":1}"#)).unwrap();
        db.write_blocking(|tx| save(tx, r#"{"b":2}"#)).unwrap();
        let (json, rows) = db
            .read_blocking(|c| {
                let n: i64 = c.query_row("SELECT count(*) FROM queue_state", [], |r| r.get(0))?;
                Ok((load(c)?, n))
            })
            .unwrap();
        assert_eq!(json.as_deref(), Some(r#"{"b":2}"#));
        assert_eq!(rows, 1);
    }
}
