//! The official feed and its two public keys (main + rotation). The secret halves live
//! outside the repo (`~/.config/vehicoule/feed-keys/official-{1,2}.key`).

pub const OFFICIAL_FEED_URL: &str = "https://feeds.vehicoule.app/official/feed.json";

pub const OFFICIAL_KEYS: [[u8; 32]; 2] = [
    // lGbU5OmSAYloHIPI0jXNObMCQQDBwuYYLWVdtIBDgQU=
    [
        148, 102, 212, 228, 233, 146, 1, 137, 104, 28, 131, 200, 210, 53, 205, 57, 179, 2, 65, 0,
        193, 194, 230, 24, 45, 101, 93, 180, 128, 67, 129, 5,
    ],
    // zutY3uGKlQ6+r1f7rZ/Oika45PnMAbR0czsJG6IMqgw=
    [
        206, 235, 88, 222, 225, 138, 149, 14, 190, 175, 87, 251, 173, 159, 206, 138, 70, 184, 228,
        249, 204, 1, 180, 116, 115, 59, 9, 27, 162, 12, 170, 12,
    ],
];

#[cfg(test)]
mod tests {
    use super::*;

    /// The fingerprints `vehicoule-feed keygen` printed: catches a mistyped byte.
    #[test]
    fn official_keys_match_their_fingerprints() {
        assert_eq!(
            OFFICIAL_KEYS.map(|k| plugin_host::fingerprint(&k)),
            [
                "20ee b862 da0e 996b 108d 1e8b f552 88cc",
                "af72 e733 6fab a21a 6e48 52bb 41ec 1dcb"
            ]
        );
    }
}
