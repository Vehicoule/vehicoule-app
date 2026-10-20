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

/// Quoted text → `"…"` (an unclosed quote masks to the end), any word containing `://` →
/// `<url>`, runs of more than 6 digits → `<n>`.
pub fn redact(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for (i, part) in s.split('"').enumerate() {
        if i % 2 == 1 {
            out.push_str("\"…");
            continue;
        }
        if i > 0 {
            out.push('"');
        }
        for chunk in part.split_inclusive(char::is_whitespace) {
            let word = chunk.trim_end_matches(char::is_whitespace);
            if word.contains("://") {
                out.push_str("<url>");
            } else {
                mask_digits(word, &mut out);
            }
            out.push_str(&chunk[word.len()..]);
        }
    }
    out
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
    }

    #[test]
    fn log_buffer_keeps_2000_lines() {
        for i in 0..2500 {
            push("info", "buffer-test", &format!("line {i}"));
        }
        let lines = recent();
        assert_eq!(lines.len(), 2000);
        let last = lines.last().unwrap();
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
        assert_eq!(recent().last().unwrap().message, "GET <url>");
    }
}
