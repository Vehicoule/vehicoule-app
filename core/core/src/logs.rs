//! In-memory diagnostics log: the last 2000 lines, masked before they are stored.

use std::collections::VecDeque;
use std::sync::{Mutex, PoisonError};
use std::time::{SystemTime, UNIX_EPOCH};

const CAPACITY: usize = 2000;

static LINES: Mutex<VecDeque<LogLine>> = Mutex::new(VecDeque::new());

#[derive(Debug, Clone, PartialEq)]
pub struct LogLine {
    pub at_ms: i64,
    pub level: String,
    pub source: String,
    pub message: String,
}

/// Quoted text → `"…"` (an unclosed quote masks to the end; an escaped `\"` inside quotes
/// does not close them), any word containing `://` → `<url>`, runs of more than 6 digits →
/// `<n>`.
pub fn redact(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut plain = 0; // start of the current unquoted run
    let mut quoted = false;
    let mut escaped = false;
    for (i, c) in s.char_indices() {
        if c == '"' && !(quoted && escaped) {
            if quoted {
                out.push('"');
                plain = i + 1;
            } else {
                mask_words(&s[plain..i], &mut out);
                out.push_str("\"…");
            }
            quoted = !quoted;
        }
        escaped = c == '\\' && !escaped;
    }
    if !quoted {
        mask_words(&s[plain..], &mut out);
    }
    out
}

fn mask_words(s: &str, out: &mut String) {
    for chunk in s.split_inclusive(char::is_whitespace) {
        let word = chunk.trim_end_matches(char::is_whitespace);
        if word.contains("://") {
            out.push_str("<url>");
        } else {
            mask_digits(word, out);
        }
        out.push_str(&chunk[word.len()..]);
    }
}

fn mask_digits(word: &str, out: &mut String) {
    let mut rest = word;
    while let Some(start) = rest.find(|c: char| c.is_ascii_digit()) {
        out.push_str(&rest[..start]);
        let len = rest[start..]
            .find(|c: char| !c.is_ascii_digit())
            .unwrap_or(rest.len() - start);
        let run = &rest[start..start + len];
        out.push_str(if len > 6 { "<n>" } else { run });
        rest = &rest[start + len..];
    }
    out.push_str(rest);
}

pub(crate) fn push(level: &str, source: &str, message: &str) {
    let line = LogLine {
        at_ms: SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_or(0, |d| d.as_millis() as i64),
        level: level.into(),
        source: redact(source),
        message: redact(message),
    };
    // Never panic here: the panic hook calls this.
    let mut lines = LINES.lock().unwrap_or_else(PoisonError::into_inner);
    if lines.len() == CAPACITY {
        lines.pop_front();
    }
    lines.push_back(line);
}

/// Oldest first.
pub fn recent() -> Vec<LogLine> {
    let lines = LINES.lock().unwrap_or_else(PoisonError::into_inner);
    lines.iter().cloned().collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn redact_masks_sensitive_parts() {
        assert_eq!(
            redact("play \"Halo\" from https://x.y/z?q=a id 12345678"),
            "play \"…\" from <url> id <n>"
        );
        // Short numbers stay, an unclosed quote masks to the end, whitespace is kept.
        assert_eq!(
            redact("took 123456 ms\tfor \"secret query"),
            "took 123456 ms\tfor \"…"
        );
        assert_eq!(redact("a1234567b file://x"), "a<n>b <url>");
        // Debug formatting escapes inner quotes: they stay inside the quoted run.
        assert_eq!(
            redact(r#"Err(Internal("he said \"Halo\" now"))"#),
            r#"Err(Internal("…"))"#
        );
        // An escaped quote outside any quoted run opens one (fails safe: masks to the end).
        assert_eq!(redact(r#"said \"Halo\" now"#), r#"said \"…"#);
    }

    #[test]
    fn log_buffer_keeps_2000_lines() {
        // Other tests' panics land in the same global buffer (panic hook): only look at ours.
        let last_ours = || {
            recent()
                .into_iter()
                .rev()
                .find(|l| l.source == "buffer-test")
                .unwrap()
        };
        for i in 0..2500 {
            push("info", "buffer-test", &format!("line {i}"));
        }
        // Foreign lines only add to the buffer: it is full, never over.
        assert_eq!(recent().len(), 2000);
        let last = last_ours();
        assert_eq!(
            (
                last.level.as_str(),
                last.source.as_str(),
                last.message.as_str()
            ),
            ("info", "buffer-test", "line 2499")
        );
        assert!(last.at_ms > 0);
        // Masked on the way in.
        push("warn", "buffer-test", "GET https://a.b/c");
        assert_eq!(last_ours().message, "GET <url>");
    }
}
