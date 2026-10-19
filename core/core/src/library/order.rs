//! Fractional order keys for playlist ordering: base 62 (`0-9A-Za-z`, ASCII order), no integer
//! part, sorted as plain strings (`ORDER BY order_key`). A key never ends with the smallest
//! digit `'0'` — doing so would leave no room to insert anything strictly between a key and
//! that key plus `'0'`, so the invariant guarantees a midpoint always exists.

const BASE: i16 = 62;

fn digit_value(c: u8) -> i16 {
    match c {
        b'0'..=b'9' => (c - b'0') as i16,
        b'A'..=b'Z' => (c - b'A') as i16 + 10,
        b'a'..=b'z' => (c - b'a') as i16 + 36,
        _ => panic!("not a base62 order-key digit: {c}"),
    }
}

fn digit_char(v: i16) -> u8 {
    match v {
        0..=9 => b'0' + v as u8,
        10..=35 => b'A' + (v - 10) as u8,
        36..=61 => b'a' + (v - 36) as u8,
        _ => panic!("digit out of base62 range: {v}"),
    }
}

/// Whether `k` is a well-formed order key: non-empty, every byte in `0-9A-Za-z`, and the last
/// byte not `'0'`. Equivalent to the regex `[0-9A-Za-z]*[1-9A-Za-z]`. `key_between` always
/// produces keys satisfying this; callers that pick neighbours out of storage (e.g. to call
/// `key_between` again) should check it, since a corrupt or foreign value would otherwise only
/// surface as a panic.
pub fn is_valid_key(k: &str) -> bool {
    let b = k.as_bytes();
    !b.is_empty()
        && b.iter()
            .all(|&c| c.is_ascii_digit() || c.is_ascii_uppercase() || c.is_ascii_lowercase())
        && b[b.len() - 1] != b'0'
}

/// A key strictly between `a` and `b` (`None` means unbounded on that side).
///
/// Precondition (caller bug if violated — not checked beyond what's listed):
/// - each of `a`, `b`, when present, is a well-formed order key per [`is_valid_key`]
///   (`[0-9A-Za-z]*[1-9A-Za-z]`); a byte outside `0-9A-Za-z` panics in the digit decoder.
/// - `a < b` when both are present — **panics** otherwise. Two neighbours comparing equal is
///   a legitimate *stored* state (e.g. two devices independently picked the same order key for
///   a concurrent insert — nothing here dedupes that), but it must never be fed to this
///   function as the gap to insert into; resolve the tie (e.g. by `id`) before calling, or
///   don't call it for that pair at all.
pub fn key_between(a: Option<&str>, b: Option<&str>) -> String {
    if let (Some(a), Some(b)) = (a, b) {
        assert!(a < b, "key_between: lower bound {a:?} >= upper bound {b:?}");
    }
    // The only case requiring this exact value (tested below); every other "fully open"
    // position reached while walking is free to pick anything in range (see `fresh_digit`).
    if a.is_none() && b.is_none() {
        return "V".to_string();
    }

    let lo_is_none = a.is_none();
    let hi_is_none = b.is_none();
    let lo = a.unwrap_or("").as_bytes();
    let hi = b.map(str::as_bytes);

    let mut out = Vec::new();
    let mut i = 0usize;
    // Once beaten (or unbounded from the start), a side no longer constrains later digits.
    let mut hi_beaten = false;
    loop {
        let lo_v: i16 = lo.get(i).map(|&c| digit_value(c)).unwrap_or(-1);
        let hi_v: i16 = if hi_beaten {
            BASE
        } else {
            match hi {
                None => BASE,
                Some(h) => h
                    .get(i)
                    .map(|&c| digit_value(c))
                    .expect("hi exhausted before lo under a < b precondition"),
            }
        };

        if lo_v == -1 && hi_v == BASE {
            // Nothing constrains this position from either side. Any digit 1..=61 is
            // correct; which one matters only for how fast repeated one-sided calls
            // (always-None lower or upper bound, e.g. prepending/appending in a loop) grow:
            // biasing away from the middle leaves maximum headroom for the *next* call to
            // step by 1 before needing another digit.
            let digit = if lo_is_none && !hi_is_none {
                61 // open-ended prepend chain: leave room to keep decrementing
            } else if hi_is_none && !lo_is_none {
                1 // open-ended append chain: leave room to keep incrementing
            } else {
                31 // reached deep inside a call bounded on both sides; no chain to optimise
            };
            out.push(digit_char(digit));
            break;
        }

        if hi_v - lo_v >= 2 {
            if lo_v == -1 {
                // Lower side exhausted, upper side real: step one below it instead of the
                // midpoint, so a chain of prepends moves one digit at a time.
                let d = hi_v - 1;
                if d == 0 {
                    // Would end the key on '0'. Place it as a non-final digit instead (0 <
                    // hi_v here) and keep going; hi no longer constrains after this.
                    out.push(digit_char(0));
                    hi_beaten = true;
                    i += 1;
                    continue;
                }
                out.push(digit_char(d));
            } else if hi_v == BASE {
                // Upper side unbounded, lower side real: step one above it (always valid —
                // room implies lo_v + 1 < BASE — and never 0 since lo_v >= 0).
                out.push(digit_char(lo_v + 1));
            } else {
                // Both sides real: ordinary midpoint (never 0, since lo_v >= 0 here).
                out.push(digit_char((lo_v + hi_v + 1) / 2));
            }
            break;
        }

        // No room (gap <= 1): copy a digit and keep walking whichever side(s) still
        // constrain us.
        if lo_v == hi_v {
            // Tied digit: both sides still constrain the next position.
            out.push(digit_char(lo_v));
        } else if lo_v >= 0 {
            // lo_v + 1 == hi_v: copying lo's digit already beats hi; lo keeps constraining.
            out.push(digit_char(lo_v));
            hi_beaten = true;
        } else {
            // lo exhausted (-1), hi_v == 0: tie with hi's digit; lo stays unconstrained.
            out.push(digit_char(0));
        }
        i += 1;
    }

    String::from_utf8(out).expect("base62 digits are ASCII")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn first_key_is_in_the_middle() {
        assert_eq!(key_between(None, None), "V");
    }

    #[test]
    fn keys_sort_between_bounds() {
        let long_lo = "V".repeat(100);
        let long_hi = "V".repeat(99) + "W";
        let cases: &[(Option<&str>, Option<&str>)] = &[
            (None, Some("V")),
            (Some("V"), None),
            (Some("V"), Some("W")),
            (Some("V"), Some("V1")),
            (Some("az"), Some("b")),
            (None, Some("0V")),
            (Some("z"), None),
            (Some("V"), Some("V01")),
            (Some(long_lo.as_str()), Some(long_hi.as_str())),
        ];
        for &(a, b) in cases {
            let k = key_between(a, b);
            assert!(is_valid_key(&k), "{k:?} is not a well-formed key");
            if let Some(a) = a {
                assert!(a < k.as_str(), "{a:?} < {k:?} failed");
            }
            if let Some(b) = b {
                assert!(k.as_str() < b, "{k:?} < {b:?} failed");
            }
        }
    }

    #[test]
    #[should_panic(expected = "lower bound")]
    fn panics_when_a_greater_than_b() {
        key_between(Some("b"), Some("a"));
    }

    #[test]
    #[should_panic(expected = "lower bound")]
    fn panics_when_a_equals_b() {
        key_between(Some("m"), Some("m"));
    }

    #[test]
    fn never_ends_with_zero() {
        let mut prepended = vec![key_between(None, None)];
        for _ in 0..500 {
            let first = prepended.first().map(String::as_str);
            prepended.insert(0, key_between(None, first));
        }
        let mut appended = vec![key_between(None, None)];
        for _ in 0..500 {
            let last = appended.last().map(String::as_str);
            appended.push(key_between(last, None));
        }
        for k in prepended.iter().chain(appended.iter()) {
            assert!(!k.ends_with('0'), "{k:?} ends with '0'");
            assert!(is_valid_key(k), "{k:?} is not a well-formed key");
        }

        // Also check every key produced by the random-insertion stress test below.
        let mut rng = Lcg(7);
        let mut keys: Vec<String> = Vec::new();
        for _ in 0..500 {
            let idx = rng.next_index(keys.len());
            let a = if idx == 0 { None } else { Some(keys[idx - 1].as_str()) };
            let b = keys.get(idx).map(String::as_str);
            keys.insert(idx, key_between(a, b));
        }
        for k in &keys {
            assert!(!k.ends_with('0'), "{k:?} ends with '0'");
        }
    }

    #[test]
    fn thousand_prepends_stay_short() {
        let mut keys: Vec<String> = Vec::new();
        for _ in 0..1000 {
            let first = keys.first().map(String::as_str);
            let k = key_between(None, first);
            if let Some(first) = first {
                assert!(k.as_str() < first, "{k:?} < {first:?} failed");
            }
            keys.insert(0, k);
        }
        assert!(keys.windows(2).all(|w| w[0] < w[1]), "not sorted");
        let max_len = keys.iter().map(String::len).max().unwrap();
        assert!(max_len <= 30, "max length {max_len} > 30");
    }

    #[test]
    fn thousand_appends_stay_short() {
        let mut keys: Vec<String> = Vec::new();
        for _ in 0..1000 {
            let last = keys.last().map(String::as_str);
            let k = key_between(last, None);
            if let Some(last) = last {
                assert!(last < k.as_str(), "{last:?} < {k:?} failed");
            }
            keys.push(k);
        }
        assert!(keys.windows(2).all(|w| w[0] < w[1]), "not sorted");
        let max_len = keys.iter().map(String::len).max().unwrap();
        assert!(max_len <= 30, "max length {max_len} > 30");
    }

    /// Tiny fixed LCG so the test is deterministic across runs/platforms.
    struct Lcg(u64);
    impl Lcg {
        fn next_index(&mut self, len: usize) -> usize {
            self.0 = self.0.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            ((self.0 >> 33) as usize) % (len + 1)
        }
    }

    #[test]
    fn random_inserts_keep_order() {
        let mut rng = Lcg(42);
        let mut keys: Vec<String> = Vec::new();
        for _ in 0..2000 {
            let idx = rng.next_index(keys.len());
            let a = if idx == 0 { None } else { Some(keys[idx - 1].as_str()) };
            let b = keys.get(idx).map(String::as_str);
            let k = key_between(a, b);
            if let Some(a) = a {
                assert!(a < k.as_str());
            }
            if let Some(b) = b {
                assert!(k.as_str() < b);
            }
            keys.insert(idx, k);
        }
        let mut sorted = keys.clone();
        sorted.sort();
        assert_eq!(keys, sorted, "insertion order diverged from sorted order");
    }
}
