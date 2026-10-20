//! The play queue as pure logic: no I/O, no async. Persisted as JSON by `library::queue`.

use serde::{Deserialize, Serialize};

#[derive(Clone, Serialize, Deserialize, PartialEq, Debug)]
pub struct QueueState {
    pub entries: Vec<QueueEntry>,
    pub order: Vec<usize>,
    pub index: usize,
    pub position_ms: u64,
    pub shuffle: bool,
    pub repeat: Repeat,
    pub context: Option<PlayContext>,
}

#[derive(Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Debug)]
pub struct EntryId(pub uuid::Uuid);

#[derive(Clone, Serialize, Deserialize, PartialEq, Debug)]
pub struct QueueEntry {
    pub id: EntryId,
    pub item: String,
    pub from_radio: bool,
}

#[derive(Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Debug)]
pub enum Repeat {
    Off,
    All,
    One,
}

#[derive(Clone, Serialize, Deserialize, PartialEq, Debug)]
pub struct PlayContext {
    pub kind: String,
    pub id: Option<String>,
    pub title: String,
}

/// `order` is the play order (indices into `entries`, which stay in natural order) and `index`
/// a position in `order`. `index == order.len()` means nothing is current (empty queue, or the
/// current entry was removed at the end): the next inserted entry becomes current.
impl QueueState {
    pub fn play(
        items: Vec<String>,
        start: usize,
        context: Option<PlayContext>,
        shuffle: bool,
        seed: u64,
    ) -> QueueState {
        let n = items.len();
        let mut q = QueueState {
            entries: items
                .into_iter()
                .map(|i| QueueEntry::new(i, false))
                .collect(),
            order: (0..n).collect(),
            index: start.min(n.saturating_sub(1)),
            position_ms: 0,
            shuffle: false,
            repeat: Repeat::Off,
            context,
        };
        q.set_shuffle(shuffle, seed);
        q
    }

    pub fn current(&self) -> Option<&QueueEntry> {
        self.order.get(self.index).map(|&i| &self.entries[i])
    }

    /// What `advance` will play: a pure function of the state.
    pub fn next(&self) -> Option<&QueueEntry> {
        self.next_pos(true).map(|p| &self.entries[self.order[p]])
    }

    /// End of track. At the end with `Repeat::Off`, returns `None` and the last entry stays current.
    pub fn advance(&mut self) -> Option<&QueueEntry> {
        self.go(self.next_pos(true))
    }

    /// Next button: `Repeat::One` behaves like `Repeat::Off`.
    pub fn skip_next(&mut self) -> Option<&QueueEntry> {
        self.go(self.next_pos(false))
    }

    /// More than 3 s played, or first entry: restarts the current one.
    pub fn previous(&mut self) -> Option<&QueueEntry> {
        self.current()?;
        let p = if self.position_ms > 3000 || self.index == 0 {
            self.index
        } else {
            self.index - 1
        };
        self.go(Some(p))
    }

    pub fn jump_to(&mut self, entry: EntryId) -> bool {
        let p = self.position_of(entry);
        self.go(p).is_some()
    }

    /// Right after the current entry, in play order and in natural order.
    pub fn enqueue_next(&mut self, items: Vec<String>) {
        let (natural, play) = match self.order.get(self.index) {
            Some(&e) => (e + 1, self.index + 1),
            None => (self.entries.len(), self.order.len()),
        };
        self.insert(natural, play, items, false);
    }

    pub fn enqueue_last(&mut self, items: Vec<String>) {
        self.insert(self.entries.len(), self.order.len(), items, false);
    }

    pub fn append_radio(&mut self, items: Vec<String>) {
        self.insert(self.entries.len(), self.order.len(), items, true);
    }

    /// Removing the current entry makes the following one current (position 0); removing the
    /// last one leaves nothing current, or wraps with `Repeat::All`.
    pub fn remove(&mut self, entry: EntryId) {
        let Some(p) = self.position_of(entry) else {
            return;
        };
        let e = self.order.remove(p);
        self.entries.remove(e);
        for o in &mut self.order {
            if *o > e {
                *o -= 1;
            }
        }
        if p < self.index {
            self.index -= 1;
        } else if p == self.index {
            self.position_ms = 0;
            if self.index == self.order.len() && self.repeat == Repeat::All {
                self.index = 0;
            }
        }
    }

    /// `to` is a position in play order (clamped). Unshuffled, the natural order moves too.
    pub fn move_entry(&mut self, entry: EntryId, to: usize) {
        let Some(p) = self.position_of(entry) else {
            return;
        };
        let to = to.min(self.order.len() - 1);
        if self.shuffle {
            let v = self.order.remove(p);
            self.order.insert(to, v);
        } else {
            // `order` is the identity: play position == natural position.
            let v = self.entries.remove(p);
            self.entries.insert(to, v);
        }
        if p == self.index {
            self.index = to;
        } else if p < self.index && to >= self.index {
            self.index -= 1;
        } else if p > self.index && to <= self.index {
            self.index += 1;
        }
    }

    /// On: the current entry comes first, the rest is shuffled. Off: natural order, same current.
    pub fn set_shuffle(&mut self, on: bool, seed: u64) {
        if on == self.shuffle {
            return;
        }
        let n = self.entries.len();
        let current = self.order.get(self.index).copied();
        self.order = (0..n).collect();
        self.index = match (on, current) {
            (false, c) => c.unwrap_or(n),
            (true, None) => {
                fisher_yates(&mut self.order, seed);
                n
            }
            (true, Some(c)) => {
                self.order.remove(c);
                fisher_yates(&mut self.order, seed);
                self.order.insert(0, c);
                0
            }
        };
        self.shuffle = on;
    }

    pub fn set_repeat(&mut self, r: Repeat) {
        self.repeat = r;
    }

    /// Play order after the current entry (no wrap-around for `Repeat::All`).
    pub fn upcoming(&self) -> Vec<&QueueEntry> {
        let rest = self.order.get(self.index + 1..).unwrap_or(&[]);
        rest.iter().map(|&i| &self.entries[i]).collect()
    }

    fn next_pos(&self, honor_one: bool) -> Option<usize> {
        let n = self.order.len();
        if honor_one && self.repeat == Repeat::One && self.index < n {
            Some(self.index)
        } else if self.index + 1 < n {
            Some(self.index + 1)
        } else if self.repeat == Repeat::All && n > 0 {
            Some(0)
        } else {
            None
        }
    }

    fn go(&mut self, p: Option<usize>) -> Option<&QueueEntry> {
        self.index = p?;
        self.position_ms = 0;
        self.current()
    }

    fn position_of(&self, entry: EntryId) -> Option<usize> {
        self.order.iter().position(|&i| self.entries[i].id == entry)
    }

    /// Inserts at `natural` in `entries` and at `play` in `order`; `index` never needs to move
    /// (callers insert after the current entry, or make the first new entry current).
    fn insert(&mut self, natural: usize, play: usize, items: Vec<String>, from_radio: bool) {
        let k = items.len();
        for o in &mut self.order {
            if *o >= natural {
                *o += k;
            }
        }
        let new = items.into_iter().map(|i| QueueEntry::new(i, from_radio));
        self.entries.splice(natural..natural, new);
        self.order.splice(play..play, natural..natural + k);
    }
}

impl QueueEntry {
    fn new(item: String, from_radio: bool) -> QueueEntry {
        QueueEntry {
            id: EntryId(uuid::Uuid::now_v7()),
            item,
            from_radio,
        }
    }
}

/// Fisher-Yates driven by an LCG (Knuth's MMIX constants): same seed, same order.
fn fisher_yates(v: &mut [usize], seed: u64) {
    let mut s = seed;
    for i in (1..v.len()).rev() {
        s = s
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        v.swap(i, ((s >> 33) % (i as u64 + 1)) as usize);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn items(n: usize) -> Vec<String> {
        (0..n).map(|i| format!("t{i}")).collect()
    }

    fn item(e: Option<&QueueEntry>) -> Option<&str> {
        e.map(|e| e.item.as_str())
    }

    fn upcoming(q: &QueueState) -> Vec<&str> {
        q.upcoming().into_iter().map(|e| e.item.as_str()).collect()
    }

    fn id_of(q: &QueueState, it: &str) -> EntryId {
        q.entries.iter().find(|e| e.item == it).unwrap().id
    }

    fn natural(q: &QueueState) -> bool {
        q.order.iter().copied().eq(0..q.entries.len())
    }

    #[test]
    fn play_starts_at_index() {
        let ctx = PlayContext {
            kind: "album".into(),
            id: Some("a1".into()),
            title: "A".into(),
        };
        let q = QueueState::play(items(5), 2, Some(ctx.clone()), false, 0);
        assert_eq!(item(q.current()), Some("t2"));
        assert_eq!(q.index, 2);
        assert_eq!(q.position_ms, 0);
        assert_eq!(q.context, Some(ctx));
        assert!(natural(&q));
        assert_eq!(upcoming(&q), ["t3", "t4"]);
    }

    #[test]
    fn next_respects_repeat_modes() {
        let mut q = QueueState::play(items(3), 2, None, false, 0);
        assert_eq!(q.next(), None);
        assert_eq!(q.advance(), None);
        assert_eq!(
            item(q.current()),
            Some("t2"),
            "the last entry stays current at the end"
        );
        q.set_repeat(Repeat::All);
        assert_eq!(item(q.next()), Some("t0"));
        assert_eq!(item(q.advance()), Some("t0"));
        q.set_repeat(Repeat::One);
        assert_eq!(item(q.next()), Some("t0"));
        q.position_ms = 9000;
        assert_eq!(item(q.advance()), Some("t0"));
        assert_eq!(q.position_ms, 0);
    }

    #[test]
    fn skip_next_ignores_repeat_one() {
        let mut q = QueueState::play(items(3), 0, None, false, 0);
        q.set_repeat(Repeat::One);
        assert_eq!(item(q.skip_next()), Some("t1"));
        assert_eq!(item(q.skip_next()), Some("t2"));
        assert_eq!(q.skip_next(), None, "One acts as Off for skipping");
        assert_eq!(item(q.current()), Some("t2"));
    }

    #[test]
    fn previous_restarts_after_3s() {
        let mut q = QueueState::play(items(3), 1, None, false, 0);
        q.position_ms = 4000;
        assert_eq!(item(q.previous()), Some("t1"));
        assert_eq!(q.position_ms, 0);
        q.position_ms = 2000;
        assert_eq!(item(q.previous()), Some("t0"));
        assert_eq!(item(q.previous()), Some("t0"), "first entry: restart");
    }

    #[test]
    fn shuffle_keeps_current_and_is_a_permutation() {
        let q = QueueState::play(items(20), 5, None, true, 42);
        assert_eq!(item(q.current()), Some("t5"));
        assert_eq!(q.index, 0);
        let mut sorted = q.order.clone();
        sorted.sort();
        assert_eq!(sorted, (0..20).collect::<Vec<_>>());
        assert!(!natural(&q));
        // Same seed, same order; another seed, another order.
        assert_eq!(
            q.order,
            QueueState::play(items(20), 5, None, true, 42).order
        );
        assert_ne!(q.order, QueueState::play(items(20), 5, None, true, 7).order);

        let mut q = QueueState::play(items(20), 0, None, false, 0);
        q.advance();
        q.set_shuffle(true, 9);
        assert_eq!(item(q.current()), Some("t1"));
        assert_eq!(q.index, 0);
        assert!(q.shuffle);
    }

    #[test]
    fn unshuffle_returns_to_natural_order_at_current() {
        let mut q = QueueState::play(items(10), 3, None, true, 42);
        q.advance();
        q.advance();
        let cur = q.current().unwrap().clone();
        q.set_shuffle(false, 0);
        assert!(natural(&q));
        assert!(!q.shuffle);
        assert_eq!(q.current(), Some(&cur));
        assert_eq!(q.entries[q.index], cur);
    }

    #[test]
    fn enqueue_next_goes_right_after_current_even_shuffled() {
        let mut q = QueueState::play(items(10), 4, None, true, 42);
        q.advance();
        let cur = q.current().unwrap().id;
        q.enqueue_next(vec!["x".into(), "y".into()]);
        assert_eq!(q.current().unwrap().id, cur);
        assert_eq!(item(q.next()), Some("x"));
        assert_eq!(&upcoming(&q)[..2], ["x", "y"]);
        assert_eq!(q.order.len(), 12);
        // Natural order: right after the current entry too.
        q.set_shuffle(false, 0);
        assert_eq!(q.current().unwrap().id, cur);
        assert_eq!(&upcoming(&q)[..2], ["x", "y"]);

        let mut q = QueueState::play(items(3), 0, None, false, 0);
        q.enqueue_next(vec!["x".into()]);
        assert!(natural(&q));
        assert_eq!(upcoming(&q), ["x", "t1", "t2"]);
    }

    #[test]
    fn remove_current_moves_to_next() {
        let mut q = QueueState::play(items(4), 1, None, false, 0);
        q.position_ms = 5000;
        q.remove(q.current().unwrap().id);
        assert_eq!(item(q.current()), Some("t2"));
        assert_eq!(q.position_ms, 0);
        assert!(natural(&q));
        assert_eq!(q.entries.len(), 3);
    }

    #[test]
    fn duplicates_are_distinct_entries() {
        let mut q = QueueState::play(vec!["a".into(), "a".into()], 0, None, false, 0);
        assert_ne!(q.entries[0].id, q.entries[1].id);
        q.enqueue_last(vec!["a".into()]);
        q.remove(q.entries[1].id);
        assert_eq!(q.entries.len(), 2);
        assert_eq!(q.current().unwrap().id, q.entries[0].id);
    }

    #[test]
    fn state_roundtrips_through_json() {
        let ctx = PlayContext {
            kind: "playlist".into(),
            id: None,
            title: "P".into(),
        };
        let mut q = QueueState::play(items(6), 2, Some(ctx), true, 3);
        q.set_repeat(Repeat::All);
        q.append_radio(vec!["r".into()]);
        q.position_ms = 1234;
        let json = serde_json::to_string(&q).unwrap();
        assert_eq!(serde_json::from_str::<QueueState>(&json).unwrap(), q);
    }

    // Edge cases beyond the brief.

    #[test]
    fn empty_queue_is_inert() {
        let mut q = QueueState::play(vec![], 3, None, true, 1);
        assert_eq!((q.current(), q.next()), (None, None));
        assert_eq!(q.advance(), None);
        assert_eq!(q.skip_next(), None);
        assert_eq!(q.previous(), None);
        assert!(q.upcoming().is_empty());
        q.set_repeat(Repeat::All);
        assert_eq!(q.next(), None);
        q.set_shuffle(false, 0);
        assert!(!q.jump_to(EntryId(uuid::Uuid::nil())));
        q.enqueue_next(vec!["x".into()]);
        assert_eq!(
            item(q.current()),
            Some("x"),
            "nothing current: the new entry is"
        );
    }

    #[test]
    fn remove_before_current_shifts_index() {
        let mut q = QueueState::play(items(5), 3, None, true, 11);
        let cur = q.current().unwrap().id;
        q.advance();
        let played = q.order[0];
        let played_id = q.entries[played].id;
        let next = q.next().map(|e| e.id);
        q.remove(played_id);
        assert_eq!(q.order.len(), 4);
        assert!(q.order.iter().all(|&i| i < 4));
        assert_eq!(q.index, 0);
        assert_ne!(q.current().unwrap().id, cur);
        assert_eq!(q.current().unwrap().id, q.entries[q.order[0]].id);
        assert_ne!(next, None);
        assert_eq!(q.next().map(|e| e.id), next);
    }

    #[test]
    fn remove_last_current_ends_or_wraps() {
        let mut q = QueueState::play(items(3), 2, None, false, 0);
        q.remove(id_of(&q, "t2"));
        assert_eq!((q.current(), q.next()), (None, None));
        q.enqueue_last(vec!["z".into()]);
        assert_eq!(item(q.current()), Some("z"));

        let mut q = QueueState::play(items(3), 2, None, false, 0);
        q.set_repeat(Repeat::All);
        q.remove(id_of(&q, "t2"));
        assert_eq!(item(q.current()), Some("t0"));

        let mut q = QueueState::play(items(1), 0, None, false, 0);
        q.remove(id_of(&q, "t0"));
        assert!(q.entries.is_empty() && q.order.is_empty());
        assert_eq!(q.current(), None);
    }

    #[test]
    fn move_entry_across_current() {
        // Natural order: entries move too, so unshuffling keeps the edit.
        let mut q = QueueState::play(items(5), 2, None, false, 0);
        q.move_entry(id_of(&q, "t0"), 4);
        assert!(natural(&q));
        assert_eq!(item(q.current()), Some("t2"));
        assert_eq!(q.index, 1);
        assert_eq!(upcoming(&q), ["t3", "t4", "t0"]);
        q.move_entry(id_of(&q, "t4"), 0);
        assert_eq!(item(q.current()), Some("t2"));
        assert_eq!(q.index, 2);
        assert_eq!(upcoming(&q), ["t3", "t0"]);
        q.move_entry(id_of(&q, "t2"), 99);
        assert_eq!(item(q.current()), Some("t2"));
        assert_eq!(q.index, 4);
        assert_eq!(q.next(), None);

        // Shuffled: only the play order changes.
        let mut q = QueueState::play(items(5), 0, None, true, 5);
        let entries = q.entries.clone();
        let last = q.entries[q.order[4]].id;
        q.move_entry(last, 1);
        assert_eq!(q.entries, entries);
        assert_eq!(q.next().unwrap().id, last);
        assert_eq!(item(q.current()), Some("t0"));
    }

    #[test]
    fn jump_to_any_entry() {
        let mut q = QueueState::play(items(5), 0, None, true, 8);
        let preloaded = q.next().unwrap().id;
        q.position_ms = 19_000;
        assert!(q.jump_to(preloaded));
        assert_eq!(q.current().unwrap().id, preloaded);
        assert_eq!((q.index, q.position_ms), (1, 0));
        let earlier = q.entries[q.order[0]].id;
        assert!(q.jump_to(earlier));
        assert_eq!(q.index, 0);
        assert!(!q.jump_to(EntryId(uuid::Uuid::nil())));
        assert_eq!(q.index, 0);
    }

    #[test]
    fn append_radio_flags_entries() {
        let mut q = QueueState::play(items(2), 0, None, true, 4);
        q.enqueue_last(vec!["u".into()]);
        q.append_radio(vec!["r1".into(), "r2".into()]);
        let flags: Vec<_> = q
            .upcoming()
            .iter()
            .map(|e| (e.item.as_str(), e.from_radio))
            .collect();
        assert_eq!(flags[1..], [("u", false), ("r1", true), ("r2", true)]);
        assert!(!q.current().unwrap().from_radio);
    }

    #[test]
    fn next_always_agrees_with_advance() {
        for repeat in [Repeat::Off, Repeat::All, Repeat::One] {
            for shuffle in [false, true] {
                let mut q = QueueState::play(items(4), 1, None, shuffle, 13);
                q.set_repeat(repeat);
                for _ in 0..10 {
                    let expected = q.next().map(|e| e.id);
                    let got = q.advance().map(|e| e.id);
                    assert_eq!(got, expected, "{repeat:?} shuffle={shuffle}");
                }
            }
        }
    }
}
