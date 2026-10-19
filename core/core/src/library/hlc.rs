/// Hybrid logical clock: 48 bits of unix ms, 16 bits of counter. Ties broken by `device_id`.
#[derive(Debug, Default)]
pub struct Hlc {
    last: u64,
}

/// Version of a synced row: `updated_at` is an HLC value.
#[derive(Debug, Clone, Copy)]
pub struct Stamp {
    pub updated_at: i64,
    pub device_id: uuid::Uuid,
}

impl Hlc {
    pub(crate) fn starting_at(last: u64) -> Hlc {
        Hlc { last }
    }

    pub fn tick(&mut self, wall_ms: u64) -> u64 {
        // A full counter carries into the ms bits: still monotonic, slightly ahead of wall time.
        self.last = (wall_ms << 16).max(self.last + 1);
        self.last
    }

    /// Merges a remote stamp so the next local stamp sorts after it.
    pub fn observe(&mut self, remote: u64, wall_ms: u64) -> u64 {
        self.last = self.last.max(remote);
        self.tick(wall_ms)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hlc_is_monotonic_when_wall_clock_goes_back() {
        let mut h = Hlc::default();
        let a = h.tick(1000);
        let b = h.tick(900);
        assert!(b > a);
        assert_eq!(a >> 16, 1000);
    }

    #[test]
    fn counter_overflow_carries_into_ms() {
        let mut h = Hlc::starting_at((1000u64 << 16) | 0xFFFF);
        assert_eq!(h.tick(1000), 1001u64 << 16);
    }

    #[test]
    fn hlc_observe_jumps_past_remote() {
        let remote = Hlc::default().tick(5000);
        let mut h = Hlc::default();
        let seen = h.observe(remote, 1000);
        assert!(seen > remote);
        assert!(h.tick(1000) > remote);
    }
}
