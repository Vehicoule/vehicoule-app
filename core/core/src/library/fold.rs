use unicode_normalization::UnicodeNormalization;
use unicode_normalization::char::is_combining_mark;

/// Search normal form: lowercase, Latin accents removed, non-alphanumerics → one space.
/// Marks on non-Latin bases (kana voicing, Hangul jamo) are kept and recomposed.
pub fn fold(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut latin_base = false;
    for c in s.to_lowercase().nfd() {
        if is_combining_mark(c) {
            if !latin_base {
                out.push(c);
            }
        } else if c.is_alphanumeric() {
            latin_base = is_latin(c);
            out.push(c);
        } else {
            latin_base = false;
            if !out.is_empty() && !out.ends_with(' ') {
                out.push(' ');
            }
        }
    }
    let out = out.trim_end();
    out.nfc().collect()
}

fn is_latin(c: char) -> bool {
    matches!(c, 'a'..='z' | '\u{00C0}'..='\u{024F}' | '\u{1E00}'..='\u{1EFF}')
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fold_normalizes() {
        assert_eq!(fold("Édith  Piaf"), "edith piaf");
        assert_eq!(fold("AC/DC"), "ac dc");
        assert_eq!(fold("夜に駆ける"), "夜に駆ける");
        // Non-Latin marks are kept and recomposed (が, Hangul syllables).
        assert_eq!(fold("ガガ"), "ガガ");
        assert_eq!(fold("방탄소년단"), "방탄소년단");
        assert_eq!(fold("  T.N.T. — Ça  "), "t n t ca");
        assert_eq!(fold("İstanbul Ærøskøbing"), "istanbul ærøskøbing");
    }
}
