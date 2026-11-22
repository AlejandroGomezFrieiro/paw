//! The undo tree: every state the project has been in, as a tree.
//!
//! Undo goes to the parent and redo to the child last visited. An edit made
//! after undoing starts a new branch beside the old one, so nothing is lost by
//! undoing and then changing something. States are also numbered in the order
//! they were made, which is what [`History::step`] walks (Vim's `g-` and `g+`)
//! and what [`History::travel`] measures time along (`:earlier 2m`).
//!
//! The tree is generic over the snapshot it keeps, so that it can be tested
//! without a project. The session keeps a [`crate::model::Project`] in each
//! state; those share everything unchanged through `Arc`, so a state costs
//! about as much as what its edit changed.
//!
//! ## Pruning
//!
//! The tree keeps at most `limit` states, and about `byte_limit` bytes of
//! what they hold beyond what each shares with its parent (each state's
//! `weight`, from the weigher the tree is given). When a new state takes it
//! past either, the oldest state is dropped that is not protected; its
//! children hang from its parent instead, so undo from them jumps over the
//! gap. Protected are the root (the project as it was opened), the current
//! state, the state last saved, named states and states marked `keep`. If
//! every state is protected the tree grows past the limits rather than drop
//! one of them.

use std::collections::BTreeMap;
use std::time::{SystemTime, UNIX_EPOCH};

pub type StateId = u64;

/// A state that holds this many bytes beyond its parent is heavy to weigh.
const HEAVY: usize = 64 << 10;
/// A heavy state whose parent was dropped is weighed again after this many
/// such steps; until then its weight is reckoned from those dropped.
const RECKON: u32 = 32;

/// Seconds since the Unix epoch, as a state's time.
pub fn now() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0.0, |d| d.as_secs_f64())
}

#[derive(Clone, Debug)]
pub struct State<T> {
    /// Ids grow in the order states were made.
    pub id: StateId,
    pub parent: Option<StateId>,
    /// Oldest first.
    pub children: Vec<StateId>,
    /// The child redo goes to: the one last visited, or the newest.
    pub redo: Option<StateId>,
    /// When the state was made, in seconds since the Unix epoch.
    pub time: f64,
    /// The command that made it, if one did.
    pub label: Option<String>,
    /// The keys typed for it, if any were.
    pub keys: Option<String>,
    pub name: Option<String>,
    /// Never pruned.
    pub keep: bool,
    pub snapshot: T,
    /// About how many bytes the snapshot holds that its parent's does not
    /// share with it.
    pub weight: usize,
    /// How many states have been dropped between it and its parent since
    /// it was last weighed: its weight is reckoned from theirs until then.
    reckoned: u32,
}

impl<T> State<T> {
    /// A state with no children, label or name yet.
    pub fn new(id: StateId, parent: Option<StateId>, time: f64, snapshot: T) -> Self {
        Self {
            id,
            parent,
            children: Vec::new(),
            redo: None,
            time,
            label: None,
            keys: None,
            name: None,
            keep: false,
            snapshot,
            weight: 0,
            reckoned: 0,
        }
    }
}

pub struct History<T> {
    states: BTreeMap<StateId, State<T>>,
    current: StateId,
    root: StateId,
    next: StateId,
    limit: usize,
    saved: Option<StateId>,
    /// Saved while an edit was open: the next state made is the one saved.
    save_pending: bool,
    pending_label: Option<String>,
    /// The open step has an edit.
    step_edited: bool,
    pending_keys: Option<String>,
    /// How much a snapshot holds that another does not share: see
    /// [`History::weigh_with`].
    weigh: fn(&T, &T) -> usize,
    byte_limit: usize,
    /// The weights of every state together.
    bytes: usize,
    /// States have been dropped since the last reset, and whether that has
    /// been said.
    pruned: bool,
    pruned_said: bool,
}

impl<T: Clone> History<T> {
    pub fn new(snapshot: T, time: f64, limit: usize) -> Self {
        let mut history = Self {
            states: BTreeMap::new(),
            current: 0,
            root: 0,
            next: 0,
            limit: limit.max(2),
            saved: None,
            save_pending: false,
            pending_label: None,
            step_edited: false,
            pending_keys: None,
            weigh: |_, _| 0,
            byte_limit: usize::MAX,
            bytes: 0,
            pruned: false,
            pruned_said: false,
        };
        history.reset(snapshot, time);
        history
    }

    /// Weigh states with `weigh(parent, state)`, the bytes `state` holds
    /// that `parent` does not share with it, and keep them all together
    /// under about `byte_limit`.
    pub fn weigh_with(mut self, weigh: fn(&T, &T) -> usize, byte_limit: usize) -> Self {
        self.weigh = weigh;
        self.byte_limit = byte_limit;
        self
    }

    /// The weights of every state together, in bytes.
    pub fn bytes(&self) -> usize {
        self.bytes
    }

    pub fn byte_limit(&self) -> usize {
        self.byte_limit
    }

    /// Keep at most `limit` states and about `byte_limit` bytes from now on,
    /// dropping the oldest states at once if there are more.
    pub fn set_limits(&mut self, limit: usize, byte_limit: usize) {
        self.limit = limit.max(2);
        self.byte_limit = byte_limit;
        self.prune();
    }

    /// Whether states have been dropped to keep within the limits since the
    /// tree was reset, the first time this is asked after they have been.
    pub fn newly_pruned(&mut self) -> bool {
        let new = self.pruned && !self.pruned_said;
        self.pruned_said |= new;
        new
    }

    /// A state by id; every id held by the tree, a parent link or a child
    /// list names a state in the map.
    fn state_mut(&mut self, id: StateId) -> &mut State<T> {
        self.states
            .get_mut(&id)
            .expect("every id in the tree is in the map")
    }

    /// Weigh a state again against its parent, after either changed.
    fn reweigh(&mut self, id: StateId) {
        let Some(state) = self.states.get(&id) else { return };
        let weight = match state.parent.and_then(|p| self.states.get(&p)) {
            Some(parent) => (self.weigh)(&parent.snapshot, &state.snapshot),
            None => 0,
        };
        let state = self
            .states
            .get_mut(&id)
            .expect("a state weighed a moment ago is still in the map");
        self.bytes = self.bytes - state.weight + weight;
        state.weight = weight;
        state.reckoned = 0;
    }

    /// A state's parent `dropped` was dropped, and it hangs from the
    /// parent's parent now: it holds at most what it held beyond the state
    /// dropped and what that held beyond its own parent. To weigh it again
    /// costs about as much as what it holds, which grows as states are
    /// dropped (a state shares less and less with an older parent): a heavy
    /// state is weighed again only after [`RECKON`] such steps, and its
    /// weight is the sum until then.
    fn reparent_weight(&mut self, id: StateId, dropped: (usize, u32)) {
        let Some(state) = self.states.get_mut(&id) else { return };
        let reckoned = state.weight + dropped.0;
        let steps = state.reckoned.max(dropped.1) + 1;
        if reckoned < HEAVY || steps >= RECKON {
            self.reweigh(id);
        } else {
            self.bytes = self.bytes - state.weight + reckoned;
            state.weight = reckoned;
            state.reckoned = steps;
        }
    }

    /// Forget every state and start again from `snapshot`, which counts as
    /// saved. Ids keep counting up, so an old id never names a new state.
    pub fn reset(&mut self, snapshot: T, time: f64) {
        self.states.clear();
        self.bytes = 0;
        self.pruned = false;
        self.pruned_said = false;
        let id = self.next;
        self.next += 1;
        self.states
            .insert(id, State::new(id, None, time, snapshot));
        self.current = id;
        self.root = id;
        self.saved = Some(id);
        self.save_pending = false;
        self.clear_labels();
    }

    /// Put back a tree kept elsewhere (the undo file): `states`, with `root`
    /// as its root and `current` as the current state, which counts as
    /// saved. Ids made from now on come after theirs. False, and nothing
    /// changes, when a link names a state that is not in `states`.
    pub fn restore(&mut self, states: Vec<State<T>>, root: StateId, current: StateId) -> bool {
        let map: BTreeMap<StateId, State<T>> = states.into_iter().map(|s| (s.id, s)).collect();
        let named = |id: &StateId| map.contains_key(id);
        let linked = map
            .values()
            .all(|s| s.parent.iter().chain(&s.children).chain(&s.redo).all(named));
        if !linked || !named(&root) || !named(&current) || map[&root].parent.is_some() {
            return false;
        }
        let ids: Vec<StateId> = map.keys().copied().collect();
        self.next = self.next.max(ids.last().map_or(0, |id| id + 1));
        self.states = map;
        self.bytes = 0;
        for id in ids {
            self.reweigh(id);
        }
        self.root = root;
        self.current = current;
        self.saved = Some(current);
        self.save_pending = false;
        self.pruned = false;
        self.pruned_said = false;
        self.clear_labels();
        self.prune();
        true
    }

    /// Replace what state `id` holds: a state kept elsewhere, read when it
    /// is needed. False when there is no such state.
    pub fn set_snapshot(&mut self, id: StateId, snapshot: T) -> bool {
        let Some(state) = self.states.get_mut(&id) else { return false };
        state.snapshot = snapshot;
        let children = state.children.clone();
        self.reweigh(id);
        for child in children {
            self.reweigh(child);
        }
        true
    }

    // --- reading -----------------------------------------------------------

    pub fn current(&self) -> StateId {
        self.current
    }

    pub fn root(&self) -> StateId {
        self.root
    }

    pub fn saved(&self) -> Option<StateId> {
        self.saved.filter(|_| !self.save_pending)
    }

    pub fn limit(&self) -> usize {
        self.limit
    }

    pub fn len(&self) -> usize {
        self.states.len()
    }

    pub fn is_empty(&self) -> bool {
        self.states.is_empty()
    }

    pub fn get(&self, id: StateId) -> Option<&State<T>> {
        self.states.get(&id)
    }

    /// Every state, oldest first.
    pub fn states(&self) -> impl Iterator<Item = &State<T>> {
        self.states.values()
    }

    pub fn current_snapshot(&self) -> &T {
        &self.states[&self.current].snapshot
    }

    /// Replace what the current state holds, for bookkeeping that changes
    /// the snapshot without being an edit.
    pub fn set_current_snapshot(&mut self, snapshot: T) {
        self.state_mut(self.current).snapshot = snapshot;
        self.reweigh(self.current);
    }

    /// Whether the current state is the one last saved.
    pub fn at_saved(&self) -> bool {
        self.saved() == Some(self.current)
    }

    // --- labels ------------------------------------------------------------

    /// Name the command making the next state. The first one named wins,
    /// so a command that runs others is the one remembered. `None` takes
    /// back a name given while the step has changed nothing yet, for what
    /// comes next to name it (`3G` moved the cursor, then `dd` deleted: the
    /// step is the delete).
    pub fn label(&mut self, text: Option<String>) {
        match text {
            Some(text) => {
                self.pending_label.get_or_insert(text);
            }
            None if !self.step_edited => self.pending_label = None,
            None => {}
        }
    }

    /// The open step has made an edit: its name can no longer be taken back.
    pub fn edited(&mut self) {
        self.step_edited = true;
    }

    /// The keys typed for the next state. The last ones given win.
    pub fn keys(&mut self, text: String) {
        self.pending_keys = Some(text);
    }

    /// Forget the labels gathered for a step that changed nothing.
    pub fn clear_labels(&mut self) {
        self.pending_label = None;
        self.step_edited = false;
        self.pending_keys = None;
    }

    // --- changing ----------------------------------------------------------

    /// Add a state below the current one and make it current.
    pub fn push(&mut self, snapshot: T, time: f64) -> StateId {
        let id = self.next;
        self.next += 1;
        let parent = self.current;
        let mut state = State::new(id, Some(parent), time, snapshot);
        state.label = self.pending_label.take();
        state.keys = self.pending_keys.take();
        self.clear_labels();
        self.states.insert(id, state);
        let p = self.state_mut(parent);
        p.children.push(id);
        p.redo = Some(id);
        self.reweigh(id);
        self.current = id;
        if std::mem::take(&mut self.save_pending) {
            self.saved = Some(id);
        }
        self.prune();
        id
    }

    /// Drop state `id` as pruning does, unless it is protected (the root,
    /// the current and the saved state, named and kept states). False when
    /// it is not dropped.
    pub fn forget(&mut self, id: StateId) -> bool {
        match self.states.get(&id) {
            Some(state) if !self.protected(state) => {
                self.remove(id);
                true
            }
            _ => false,
        }
    }

    /// Give a state another name for its command: an adjusted command
    /// says what it does now. False when there is no such state.
    pub fn set_label(&mut self, id: StateId, label: Option<String>) -> bool {
        match self.states.get_mut(&id) {
            Some(state) => {
                state.label = label;
                true
            }
            None => false,
        }
    }

    /// Whether the current state can take a further change into itself
    /// instead of a new state being made: nothing hangs on it yet.
    pub fn can_amend(&self) -> bool {
        let state = &self.states[&self.current];
        self.can_extend()
            // A command or a key is a step of its own, however alike the
            // one before: only moves that nothing names (a fader dragged
            // in a window, a knob turned on a controller) run together.
            && state.label.is_none()
            && state.keys.is_none()
            && self.pending_label.is_none()
            && self.pending_keys.is_none()
    }

    /// Whether the current state can take a later edit into itself when that
    /// is asked for (a snippet's choice stepped through): nothing hangs on
    /// it, and it is neither saved nor named nor kept.
    pub fn can_extend(&self) -> bool {
        let state = &self.states[&self.current];
        state.children.is_empty()
            && !state.keep
            && state.name.is_none()
            && state.parent.is_some()
            && self.saved != Some(self.current)
            && !self.save_pending
    }

    /// Replace what the current state holds with a later version of the
    /// same edit: a control still being moved.
    pub fn amend(&mut self, snapshot: T, time: f64) {
        let state = self.state_mut(self.current);
        state.snapshot = snapshot;
        state.time = time;
        self.reweigh(self.current);
        self.clear_labels();
    }

    /// Remember the current state as the one saved. With an edit still open
    /// (`touched`), the state that edit becomes is the one saved.
    pub fn mark_saved(&mut self, touched: bool) {
        self.saved = Some(self.current);
        self.save_pending = touched;
    }

    pub fn set_name(&mut self, id: StateId, name: Option<String>) -> bool {
        match self.states.get_mut(&id) {
            Some(state) => {
                state.name = name.filter(|n| !n.is_empty());
                true
            }
            None => false,
        }
    }

    pub fn set_keep(&mut self, id: StateId, keep: bool) -> bool {
        match self.states.get_mut(&id) {
            Some(state) => {
                state.keep = keep;
                true
            }
            None => false,
        }
    }

    // --- moving ------------------------------------------------------------
    //
    // Each of these moves `current` and returns where it went, or None when
    // there is nowhere to go. The caller then takes up the snapshot.

    /// To the parent.
    pub fn undo(&mut self) -> Option<StateId> {
        let parent = self.states[&self.current].parent?;
        self.state_mut(parent).redo = Some(self.current);
        self.current = parent;
        Some(parent)
    }

    /// To the child last visited.
    pub fn redo(&mut self) -> Option<StateId> {
        let state = &self.states[&self.current];
        let child = state
            .redo
            .filter(|c| state.children.contains(c))
            .or_else(|| state.children.last().copied())?;
        self.current = child;
        Some(child)
    }

    /// To any state. Redo from each state on the way there then leads to it.
    pub fn goto(&mut self, id: StateId) -> Option<StateId> {
        if !self.states.contains_key(&id) {
            return None;
        }
        let mut at = id;
        while let Some(parent) = self.states[&at].parent {
            self.state_mut(parent).redo = Some(at);
            at = parent;
        }
        self.current = id;
        Some(id)
    }

    /// `n` states later in the order they were made (earlier when negative),
    /// whatever branch they are on: Vim's `g+` and `g-`. Stops at the oldest
    /// and the newest.
    pub fn step(&mut self, n: i64) -> Option<StateId> {
        let target = if n < 0 {
            self.states
                .range(..self.current)
                .rev()
                .take(n.unsigned_abs() as usize)
                .last()
                .map(|(id, _)| *id)
        } else {
            self.states
                .range(self.current + 1..)
                .take(n as usize)
                .last()
                .map(|(id, _)| *id)
        };
        self.goto(target?)
    }

    /// To the state that was current `seconds` later (earlier when negative)
    /// than the current one was made: the newest state made by then. Going
    /// earlier than the oldest state stops there, and later than the newest
    /// stops at the newest.
    pub fn travel(&mut self, seconds: f64) -> Option<StateId> {
        let time = self.states[&self.current].time + seconds;
        let target = if seconds < 0.0 {
            self.states
                .range(..self.current)
                .rev()
                .find(|(_, s)| s.time <= time)
                .or_else(|| self.states.iter().next())
        } else {
            self.states
                .range(self.current + 1..)
                .take_while(|(_, s)| s.time <= time)
                .last()
        }
        .map(|(id, _)| *id)
        .filter(|id| *id != self.current)?;
        self.goto(target)
    }

    // --- pruning -----------------------------------------------------------

    fn protected(&self, state: &State<T>) -> bool {
        state.id == self.root
            || state.id == self.current
            || self.saved == Some(state.id)
            || state.name.is_some()
            || state.keep
    }

    fn prune(&mut self) {
        while self.states.len() > self.limit || self.bytes > self.byte_limit {
            let Some(id) = self
                .states
                .values()
                .find(|s| !self.protected(s))
                .map(|s| s.id)
            else {
                return;
            };
            self.remove(id);
            self.pruned = true;
        }
    }

    /// Drop one state that is not the root, hanging its children from its parent.
    fn remove(&mut self, id: StateId) {
        let state = self.states.remove(&id).expect("a state to remove is in the map");
        self.bytes -= state.weight;
        let parent_id = state.parent.expect("the root is never removed");
        for child in &state.children {
            self.state_mut(*child).parent = Some(parent_id);
            // What it shared with the state dropped it may not share with
            // its new parent.
            self.reparent_weight(*child, (state.weight, state.reckoned));
        }
        let parent = self.state_mut(parent_id);
        let at = parent.children.iter().position(|c| *c == id)
            .expect("a parent lists each of its children");
        parent
            .children
            .splice(at..=at, state.children.iter().copied());
        if parent.redo == Some(id) {
            parent.redo = state.redo.or_else(|| state.children.last().copied());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A tree of strings, with each state made one second after the last.
    struct T {
        h: History<String>,
        clock: f64,
    }

    impl T {
        fn new(limit: usize) -> Self {
            Self {
                h: History::new("root".into(), 1000.0, limit),
                clock: 1000.0,
            }
        }
        fn edit(&mut self, text: &str) -> StateId {
            self.clock += 1.0;
            self.h.push(text.into(), self.clock)
        }
        fn at(&self) -> &str {
            self.h.current_snapshot()
        }
    }

    #[test]
    fn undo_and_redo_walk_a_line() {
        let mut t = T::new(100);
        t.edit("a");
        t.edit("b");
        assert_eq!(t.at(), "b");
        assert!(t.h.undo().is_some());
        assert_eq!(t.at(), "a");
        assert!(t.h.undo().is_some());
        assert_eq!(t.at(), "root");
        assert!(t.h.undo().is_none(), "nothing before the root");
        assert!(t.h.redo().is_some());
        assert!(t.h.redo().is_some());
        assert_eq!(t.at(), "b");
        assert!(t.h.redo().is_none(), "nothing after the newest");
    }

    #[test]
    fn an_edit_after_undo_starts_a_branch() {
        let mut t = T::new(100);
        let a = t.edit("a");
        let b = t.edit("b");
        t.h.undo();
        let c = t.edit("c");
        assert_eq!(t.h.get(a).unwrap().children, vec![b, c]);
        assert!(t.h.redo().is_none(), "the new branch is at its end");
        // The old branch is still there.
        t.h.goto(b);
        assert_eq!(t.at(), "b");
        // Redo follows the branch last visited.
        t.h.undo();
        t.h.redo();
        assert_eq!(t.at(), "b");
        t.h.goto(c);
        t.h.undo();
        t.h.redo();
        assert_eq!(t.at(), "c");
    }

    #[test]
    fn goto_sets_the_redo_path() {
        let mut t = T::new(100);
        let a = t.edit("a");
        let b = t.edit("b");
        t.h.goto(a);
        let c = t.edit("c");
        t.h.goto(b);
        t.h.goto(t.h.root());
        t.h.redo();
        t.h.redo();
        assert_eq!(t.h.current(), b);
        assert_ne!(t.h.current(), c);
    }

    #[test]
    fn step_visits_every_state_in_time_order() {
        let mut t = T::new(100);
        let a = t.edit("a");
        let b = t.edit("b");
        t.h.undo();
        let c = t.edit("c");
        t.h.goto(t.h.root());
        let d = t.edit("d");
        let mut seen = vec![t.h.current()];
        while let Some(id) = t.h.step(-1) {
            seen.push(id);
        }
        assert_eq!(seen, vec![d, c, b, a, t.h.root()]);
        let mut seen = vec![t.h.current()];
        while let Some(id) = t.h.step(1) {
            seen.push(id);
        }
        assert_eq!(seen, vec![t.h.root(), a, b, c, d]);
        t.h.goto(t.h.root());
        assert_eq!(t.h.step(3), Some(c));
        assert_eq!(t.h.step(10), Some(d), "stops at the newest");
        assert_eq!(t.h.step(-2), Some(b));
    }

    #[test]
    fn travel_by_time() {
        let mut t = T::new(100);
        let a = t.edit("a"); // 1001
        let _b = t.edit("b"); // 1002
        t.clock += 60.0;
        let c = t.edit("c"); // 1063
        let d = t.edit("d"); // 1064
        assert_eq!(
            t.h.travel(-30.0),
            Some(_b),
            "the newest state made 30 s before"
        );
        assert_eq!(t.h.travel(-1.0), Some(a));
        assert_eq!(t.h.travel(-500.0), Some(t.h.root()), "stops at the oldest");
        assert_eq!(t.h.travel(-1.0), None, "nothing earlier");
        assert_eq!(t.h.travel(62.0), Some(_b), "the newest made by then");
        assert_eq!(t.h.travel(61.0), Some(c));
        assert_eq!(t.h.travel(1000.0), Some(d), "stops at the newest");
        assert_eq!(t.h.travel(1.0), None);
    }

    #[test]
    fn pruning_drops_the_oldest_unprotected_state() {
        let mut t = T::new(4);
        let a = t.edit("a");
        let b = t.edit("b");
        let c = t.edit("c");
        assert_eq!(t.h.len(), 4);
        let d = t.edit("d");
        assert_eq!(t.h.len(), 4);
        assert!(t.h.get(a).is_none(), "the oldest went");
        assert!(t.h.get(t.h.root()).is_some(), "but never the root");
        assert_eq!(t.h.get(b).unwrap().parent, Some(t.h.root()));
        assert_eq!(t.h.get(t.h.root()).unwrap().children, vec![b]);
        // Undo jumps over the gap.
        t.h.goto(b);
        assert_eq!(t.h.undo(), Some(t.h.root()));
        t.h.redo();
        assert_eq!(t.h.current(), b);
        // Named and kept states stay.
        t.h.set_name(b, Some("verse".into()));
        t.h.goto(d);
        t.h.set_keep(c, true);
        let e = t.edit("e");
        assert!(t.h.get(b).is_some() && t.h.get(c).is_some());
        assert!(t.h.get(d).is_none(), "the oldest unprotected one went");
        assert_eq!(t.h.get(e).unwrap().parent, Some(c));
        assert_eq!(t.h.len(), 4);
        // With nothing left to drop the limit gives.
        t.h.set_name(e, Some("chorus".into()));
        let f = t.edit("f");
        assert_eq!(t.h.len(), 5);
        assert_eq!(t.h.current(), f);
    }

    #[test]
    fn pruning_keeps_branches_attached() {
        let mut t = T::new(5);
        let a = t.edit("a");
        let b = t.edit("b");
        t.h.goto(a);
        let c = t.edit("c");
        t.h.goto(a);
        let d = t.edit("d");
        // a (oldest unprotected) goes: b, c and d hang from the root, in order.
        let e = t.edit("e");
        assert!(t.h.get(a).is_none());
        assert_eq!(t.h.get(t.h.root()).unwrap().children, vec![b, c, d]);
        assert_eq!(t.h.get(e).unwrap().parent, Some(d));
        t.h.goto(t.h.root());
        t.h.redo();
        assert_eq!(t.h.current(), d, "redo still leads where it led");
    }

    #[test]
    fn states_are_kept_within_a_number_of_bytes_and_that_is_said_once() {
        let mut t = T::new(100);
        t.h = History::new("root".into(), 1000.0, 100).weigh_with(|_, s: &String| s.len(), 10);
        t.edit("aaaa");
        t.edit("bbbb");
        assert_eq!(t.h.bytes(), 8);
        assert!(!t.h.newly_pruned());
        t.edit("cccc");
        assert_eq!(t.h.len(), 3, "the oldest step went to stay within 10 bytes");
        assert_eq!(t.h.bytes(), 8);
        assert!(t.h.newly_pruned(), "and that is said");
        t.edit("dddd");
        assert!(!t.h.newly_pruned(), "once");
        t.h.undo();
        assert_eq!(t.at(), "cccc");
        t.h.reset("new".into(), 2000.0);
        assert_eq!(t.h.bytes(), 0);
    }

    #[test]
    fn heavy_states_are_weighed_again_now_and_then_as_older_ones_go() {
        use std::sync::atomic::{AtomicUsize, Ordering::Relaxed};
        static WEIGHED: AtomicUsize = AtomicUsize::new(0);
        // Each state holds 100 kB that its parent does not share, and
        // weighing one is counted.
        let mut t = T::new(10);
        t.h = History::new("root".into(), 1000.0, 10).weigh_with(
            |_, _: &String| {
                WEIGHED.fetch_add(1, Relaxed);
                100 << 10
            },
            usize::MAX,
        );
        for _ in 0..200 {
            t.edit("a");
        }
        let weighed = WEIGHED.load(Relaxed);
        // One for each state made, and about one for each 32 dropped.
        assert!(weighed < 200 + 200 / 32 + 2, "weighed {weighed} times");
        assert_eq!(t.h.len(), 10);
        // The weight reckoned is never below what it holds, and comes back
        // to it when weighed again.
        let bytes = t.h.bytes();
        assert!(bytes >= 9 * (100 << 10), "{bytes}");
        assert!(bytes <= 9 * (100 << 10) + 32 * (100 << 10), "{bytes}");
    }

    #[test]
    fn lowering_the_limits_drops_the_oldest_states_at_once() {
        let mut t = T::new(100);
        t.h = History::new("root".into(), 1000.0, 100).weigh_with(|_, s: &String| s.len(), 1000);
        for _ in 0..10 {
            t.edit("aaaa");
        }
        t.h.set_limits(5, 1000);
        assert_eq!(t.h.len(), 5);
        assert!(t.h.newly_pruned());
        t.h.set_limits(100, 8);
        assert_eq!((t.h.len(), t.h.bytes()), (3, 8), "the root and two steps of 4 bytes");
        assert_eq!((t.h.limit(), t.h.byte_limit()), (100, 8));
        assert_eq!(t.at(), "aaaa");
    }

    #[test]
    fn saved_state_and_labels() {
        let mut t = T::new(100);
        assert!(t.h.at_saved());
        t.edit("a");
        assert!(!t.h.at_saved());
        t.h.mark_saved(false);
        assert!(t.h.at_saved());
        t.h.undo();
        assert!(!t.h.at_saved());
        t.h.redo();
        assert!(t.h.at_saved());
        // Saved in the middle of an edit: the state it becomes is the saved one.
        t.h.mark_saved(true);
        assert!(!t.h.at_saved());
        // A name taken back before anything changed gives way to the next;
        // after an edit it stays.
        t.h.label(Some("motion".into()));
        t.h.label(None);
        t.h.label(Some("clip.add".into()));
        t.h.edited();
        t.h.label(None);
        t.h.label(Some("clip.set".into()));
        t.h.keys("x".into());
        let b = t.edit("b");
        assert!(t.h.at_saved());
        let state = t.h.get(b).unwrap();
        assert_eq!(state.label.as_deref(), Some("clip.add"));

        assert_eq!(state.keys.as_deref(), Some("x"));
        t.h.clear_labels();
        let c = t.edit("c");
        assert_eq!(t.h.get(c).unwrap().label, None);
        // Reset starts over with new ids.
        t.h.reset("new".into(), 2000.0);
        assert_eq!(t.h.len(), 1);
        assert!(t.h.root() > c);
        assert!(t.h.get(c).is_none());
    }
}
