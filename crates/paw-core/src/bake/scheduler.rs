//! The bake scheduler: what the project wants made, made in the order the
//! user hears it, off the kernel thread.
//!
//! Each poll gives the keys the project wants now, each with a
//! [`Priority`]. A key is made once it has been wanted for a moment (the
//! settle), so a value dragged through many values bakes the last one
//! only. A key that is no longer wanted stops waiting, or, when it is
//! being made, is told to stop. Bakes run in two lanes ([`Lane`]), each of
//! a few at a time; a bake for what is about to play or what a window
//! shows takes the place of the oldest background bake when its lane is
//! full.
//!
//! The kernel never waits: a bake ends by a message that the next poll
//! takes in, and the keys whose state changed are in
//! [`finished`](Scheduler::finished) for the session to build again what
//! plays them.

use std::collections::{HashMap, VecDeque};
use std::hash::Hash;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc::{Receiver, Sender, channel};
use std::sync::{Arc, OnceLock};
use std::time::Duration;

use anyhow::Result;
use paw_engine::AudioData;

use super::store::Entry;
use crate::clock::{Clock, WallClock};
use crate::peaks::Summary;

/// How long a key must be wanted before it is made.
pub const SETTLE: Duration = Duration::from_millis(150);

/// Bakes made that nothing wants any more, kept anyway for undo.
const SPARE: usize = 8;

/// How soon a bake is wanted, least first: the owner's order. An export
/// waits for all of its parts whatever the order; the ear does not.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Priority {
    /// The rest of the project, so that it is ready before it plays.
    #[default]
    Background,
    /// A running render, freeze or export waits for it.
    Export,
    /// A view shows it.
    Visible,
    /// The next seconds after the playhead (or the cursor, stopped).
    Playing,
}

/// Where a bake runs.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Lane {
    /// A function on a worker thread of paw's (`bake::native`).
    Native,
    /// A helper process, read on the kernel's I/O runtime (`bake::helper`).
    Helper,
}

impl Lane {
    fn index(self) -> usize {
        self as usize
    }
}

/// What a bake made.
pub enum Made {
    /// Sound to play, mapped from its entry when it is large.
    Sound(Arc<AudioData>),
    /// A cache entry: a helper's files.
    Entry(Entry),
}

/// Makes one thing. Runs off the kernel thread; never touches the model.
pub trait Bake: Send + Sync + 'static {
    fn lane(&self) -> Lane;
    /// What it makes, for messages: "stretching drums.wav".
    fn what(&self) -> String;
    /// Start the work where its lane runs, and return at once. The work
    /// ends by [`Task::end`]; it looks at [`Task::cancelled`] as it goes.
    fn start(self: Arc<Self>, task: Task) -> Result<()>;
}

/// What a running bake and the scheduler share.
#[derive(Default)]
struct Shared {
    cancel: AtomicBool,
    woken: tokio::sync::Notify,
    /// How far it is, in millionths.
    progress: AtomicU32,
    /// Sound playable while it is made, from its start.
    partial: OnceLock<Arc<AudioData>>,
    /// The cache entry it makes or found, so that it is pinned.
    entry: OnceLock<String>,
    /// The helper's process, while it runs.
    pid: AtomicU32,
}

/// A running bake's side of the scheduler.
pub struct Task {
    shared: Arc<Shared>,
    serial: u64,
    ended: Sender<Ended>,
}

struct Ended {
    serial: u64,
    result: Result<Made>,
}

impl Task {
    /// Set when nothing wants the bake any more: stop, and end with any error.
    pub fn stop_flag(&self) -> &AtomicBool {
        &self.shared.cancel
    }

    pub fn cancelled(&self) -> bool {
        self.shared.cancel.load(Ordering::Relaxed)
    }

    /// Wait until the bake is cancelled (for a helper's task).
    pub async fn until_cancelled(&self) {
        while !self.cancelled() {
            self.shared.woken.notified().await;
        }
    }

    /// How far the bake is, from 0 to 1.
    pub fn progress(&self, fraction: f64) {
        let millionths = (fraction.clamp(0.0, 1.0) * 1e6) as u32;
        self.shared.progress.store(millionths, Ordering::Relaxed);
    }

    /// Sound that plays while it is made (a growing sink's): what plays the
    /// bake switches to it.
    pub fn partial(&self, data: Arc<AudioData>) {
        let _ = self.shared.partial.set(data);
    }

    /// The cache entry the bake makes or found (`EntryKey::id`).
    pub fn entry(&self, id: String) {
        let _ = self.shared.entry.set(id);
    }

    /// The helper's process id, while it runs.
    pub fn pid(&self, pid: u32) {
        self.shared.pid.store(pid, Ordering::Relaxed);
    }

    /// The bake ended: what it made, or why not.
    pub fn end(self, result: Result<Made>) {
        // A scheduler that is gone wants nothing.
        let _ = self.ended.send(Ended { serial: self.serial, result });
    }
}

/// A bake made, with its waveform overview once one was asked for.
pub struct Ready {
    made: Made,
    summary: Option<Arc<Summary>>,
}

impl Ready {
    pub fn sound(&self) -> Option<&Arc<AudioData>> {
        match &self.made {
            Made::Sound(data) => Some(data),
            Made::Entry(_) => None,
        }
    }

    pub fn entry(&self) -> Option<&Entry> {
        match &self.made {
            Made::Entry(entry) => Some(entry),
            Made::Sound(_) => None,
        }
    }

    /// The overview of a sound, made on the first call.
    pub fn summary(&mut self) -> Option<Arc<Summary>> {
        let Made::Sound(data) = &self.made else {
            return None;
        };
        Some(
            self.summary
                .get_or_insert_with(|| Arc::new(Summary::new(data)))
                .clone(),
        )
    }
}

/// The times are schedule times (`Scheduler::clock`).
enum State {
    /// Wanted since then.
    Waiting(Duration),
    /// Being made; `told` once its partial sound was noted in `finished`.
    Running {
        shared: Arc<Shared>,
        serial: u64,
        /// Wanted since then; started then.
        since: Duration,
        started: Duration,
        told: bool,
    },
    Done(Ready),
    /// It could not be made; why was told once.
    Failed,
}

struct Job {
    /// Kept while it waits or runs, to start it (again, when preempted).
    bake: Option<Arc<dyn Bake>>,
    priority: Priority,
    state: State,
}

/// Where a key's bake is.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Status {
    /// Not asked for.
    Unknown,
    /// Wanted, not started yet.
    Waiting,
    /// Being made.
    Running,
    Ready,
    Failed,
}

/// How much is being baked, for the status line and `bake.progress`.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Busy {
    pub running: usize,
    pub waiting: usize,
    /// Of the running ones together, 0 to 1.
    pub fraction: f64,
}

pub struct Scheduler<K> {
    jobs: HashMap<K, Job>,
    /// Bakes made, oldest first, for dropping the oldest unwanted ones.
    made: VecDeque<K>,
    /// The cache entries of the keys, as their bakes told them.
    entries: HashMap<K, String>,
    /// Bakes at once, per lane.
    lanes: [usize; 2],
    serial: u64,
    ended: (Sender<Ended>, Receiver<Ended>),
    /// Why bakes failed, not yet told.
    pub failures: Vec<String>,
    /// Keys started (with sound to play), made or failed since the session
    /// last looked: what plays them is to be built again.
    pub finished: Vec<K>,
    /// Bakes started, ever: for tests and `:checkhealth`.
    pub started: usize,
    /// The schedule clock that the settle waits on.
    clock: Arc<dyn Clock>,
}

impl<K> Default for Scheduler<K> {
    fn default() -> Self {
        let cores = std::thread::available_parallelism().map_or(4, |n| n.get());
        Self::new((cores / 4).clamp(1, 4), 2)
    }
}

impl<K> Scheduler<K> {
    /// At most `native` bakes on threads and `helpers` helper processes at once.
    pub fn new(native: usize, helpers: usize) -> Self {
        Self {
            jobs: HashMap::new(),
            made: VecDeque::new(),
            entries: HashMap::new(),
            lanes: [native.max(1), helpers.max(1)],
            serial: 0,
            ended: channel(),
            failures: Vec::new(),
            finished: Vec::new(),
            started: 0,
            clock: Arc::new(WallClock::new()),
        }
    }
}

impl<K: Clone + Eq + Hash> Scheduler<K> {
    /// Wait the settle on `clock` from now on. Give it before the first
    /// [`ask`](Self::ask): the times of the bakes that wait are on the old
    /// clock.
    pub fn set_clock(&mut self, clock: Arc<dyn Clock>) {
        self.clock = clock;
    }

    /// Ask for `key`; when it is not known, it waits, to be made by the bake
    /// `make` gives (none: nothing to make it from).
    pub fn ask(&mut self, key: &K, make: impl FnOnce() -> Option<Arc<dyn Bake>>) {
        if self.jobs.contains_key(key) {
            return;
        }
        if let Some(bake) = make() {
            let job = Job {
                bake: Some(bake),
                priority: Priority::Background,
                state: State::Waiting(self.clock.now()),
            };
            self.jobs.insert(key.clone(), job);
        }
    }

    /// Whether `key` has been asked for (and not dropped since).
    pub fn known(&self, key: &K) -> bool {
        self.jobs.contains_key(key)
    }

    /// The sound of `key`: made, or as far as it is made.
    pub fn sound(&self, key: &K) -> Option<Arc<AudioData>> {
        match &self.jobs.get(key)?.state {
            State::Done(ready) => ready.sound().cloned(),
            State::Running { shared, .. } => shared.partial.get().cloned(),
            _ => None,
        }
    }

    /// What was made for `key`.
    pub fn ready(&mut self, key: &K) -> Option<&mut Ready> {
        match &mut self.jobs.get_mut(key)?.state {
            State::Done(ready) => Some(ready),
            _ => None,
        }
    }

    pub fn status(&self, key: &K) -> Status {
        match self.jobs.get(key).map(|j| &j.state) {
            None => Status::Unknown,
            Some(State::Waiting(_)) => Status::Waiting,
            Some(State::Running { .. }) => Status::Running,
            Some(State::Done(_)) => Status::Ready,
            Some(State::Failed) => Status::Failed,
        }
    }

    /// How much of `key` is made, from 0 to 1.
    pub fn progress(&self, key: &K) -> f64 {
        match self.jobs.get(key).map(|j| &j.state) {
            Some(State::Done(_)) => 1.0,
            Some(State::Running { shared, .. }) => fraction(shared),
            _ => 0.0,
        }
    }

    /// When the first bake that waits has waited `settle`, on the schedule
    /// clock: the next poll after it starts that bake.
    pub fn next_due(&self, settle: Duration) -> Option<Duration> {
        self.jobs
            .values()
            .filter_map(|job| match job.state {
                State::Waiting(since) => Some(since + settle),
                _ => None,
            })
            .min()
    }

    /// Whether anything waits or is being made.
    pub fn busy(&self) -> bool {
        self.jobs
            .values()
            .any(|j| matches!(j.state, State::Waiting(_) | State::Running { .. }))
    }

    /// How much is being baked now.
    pub fn summary(&self) -> Busy {
        let mut busy = Busy::default();
        let mut sum = 0.0;
        for job in self.jobs.values() {
            match &job.state {
                State::Waiting(_) => busy.waiting += 1,
                State::Running { shared, .. } if !shared.cancel.load(Ordering::Relaxed) => {
                    busy.running += 1;
                    sum += fraction(shared);
                }
                _ => {}
            }
        }
        busy.fraction = if busy.running == 0 { 0.0 } else { sum / busy.running as f64 };
        busy
    }

    /// Whether any of `keys` still waits or is being made.
    pub fn making<'a>(&self, mut keys: impl Iterator<Item = &'a K>) -> bool
    where
        K: 'a,
    {
        keys.any(|k| matches!(self.status(k), Status::Waiting | Status::Running))
    }

    /// The cache entries of `keys` that are known, for pinning.
    pub fn entries<'a>(&'a self, keys: impl Iterator<Item = &'a K> + 'a) -> impl Iterator<Item = &'a String> + 'a {
        keys.filter_map(|k| self.entries.get(k))
    }

    /// Take in the bakes that ended, drop what `wants` lacks, start what has
    /// waited `settle`, the most wanted first, and drop spare bakes.
    pub fn poll(&mut self, wants: &HashMap<K, Priority>, settle: Duration) {
        self.take_ended(wants);
        self.drop_unwanted(wants);
        self.tell_partials();
        self.start_due(settle);
        self.drop_spare(wants);
    }

    fn take_ended(&mut self, wants: &HashMap<K, Priority>) {
        while let Ok(Ended { serial, result }) = self.ended.1.try_recv() {
            let key = self.jobs.iter().find_map(|(key, job)| match &job.state {
                State::Running { serial: s, .. } if *s == serial => Some(key.clone()),
                // A bake preempted, or dropped: its end is no news.
                _ => None,
            });
            let Some(key) = key else { continue };
            let job = self.jobs.remove(&key).expect("found above");
            let State::Running { shared, .. } = job.state else { unreachable!() };
            if let Some(entry) = shared.entry.get() {
                self.entries.insert(key.clone(), entry.clone());
            }
            if shared.cancel.load(Ordering::Relaxed) {
                // Wanted again since it was told to stop: what plays it is
                // built again, which asks for it anew.
                if wants.contains_key(&key) {
                    self.finished.push(key);
                }
                continue;
            }
            let state = match result {
                Ok(made) => {
                    self.made.push_back(key.clone());
                    State::Done(Ready { made, summary: None })
                }
                Err(err) => {
                    let what = job.bake.as_ref().map_or_else(String::new, |b| b.what());
                    self.failures.push(format!("{what}: {err:#}"));
                    State::Failed
                }
            };
            self.jobs.insert(key.clone(), Job { bake: None, priority: job.priority, state });
            self.finished.push(key);
        }
    }

    /// Drop the waiting bakes nothing wants and tell the running ones to
    /// stop; the rest take their priority from `wants`.
    fn drop_unwanted(&mut self, wants: &HashMap<K, Priority>) {
        self.jobs.retain(|key, job| {
            let wanted = wants.get(key);
            if let Some(&priority) = wanted {
                job.priority = priority;
            }
            match &job.state {
                State::Waiting(_) => wanted.is_some(),
                State::Running { shared, .. } => {
                    if wanted.is_none() {
                        cancel(shared);
                    }
                    true
                }
                State::Done(_) | State::Failed => true,
            }
        });
    }

    /// Note the running bakes whose sound plays from now.
    fn tell_partials(&mut self) {
        for (key, job) in &mut self.jobs {
            if let State::Running { shared, told, .. } = &mut job.state
                && !*told
                && shared.partial.get().is_some()
            {
                *told = true;
                self.finished.push(key.clone());
            }
        }
    }

    /// Start the bakes that have waited `settle`, the most wanted and then
    /// the oldest first, as many as their lanes allow. A bake for what is
    /// about to play or what a window shows takes the place of the oldest
    /// background bake.
    fn start_due(&mut self, settle: Duration) {
        let now = self.clock.now();
        let mut due: Vec<(Priority, Duration, K)> = self
            .jobs
            .iter()
            .filter_map(|(key, job)| match job.state {
                State::Waiting(since) if now.saturating_sub(since) >= settle => {
                    Some((job.priority, since, key.clone()))
                }
                _ => None,
            })
            .collect();
        due.sort_by(|a, b| b.0.cmp(&a.0).then(a.1.cmp(&b.1)));
        for (priority, _, key) in due {
            let Some(lane) = self.jobs[&key].bake.as_ref().map(|b| b.lane()) else {
                continue;
            };
            if self.running(lane) >= self.lanes[lane.index()]
                && !(priority >= Priority::Visible && self.preempt(lane))
            {
                continue;
            }
            self.start(&key);
        }
    }

    /// Bakes running in `lane`, not told to stop.
    fn running(&self, lane: Lane) -> usize {
        self.jobs
            .values()
            .filter(|j| match &j.state {
                State::Running { shared, .. } => {
                    !shared.cancel.load(Ordering::Relaxed)
                        && j.bake.as_ref().is_some_and(|b| b.lane() == lane)
                }
                _ => false,
            })
            .count()
    }

    /// Stop the oldest background bake of `lane` and put it back to wait.
    fn preempt(&mut self, lane: Lane) -> bool {
        let oldest = self
            .jobs
            .iter()
            .filter_map(|(key, job)| match &job.state {
                State::Running { shared, started, .. }
                    if job.priority == Priority::Background
                        && !shared.cancel.load(Ordering::Relaxed)
                        && job.bake.as_ref().is_some_and(|b| b.lane() == lane) =>
                {
                    Some((*started, key.clone()))
                }
                _ => None,
            })
            .min_by_key(|(started, _)| *started);
        let Some((_, key)) = oldest else {
            return false;
        };
        let job = self.jobs.get_mut(&key).expect("found above");
        let State::Running { shared, since, .. } = &job.state else { unreachable!() };
        cancel(shared);
        // It starts again from the start when its turn comes; what plays
        // it plays its preview again meanwhile.
        job.state = State::Waiting(*since);
        self.finished.push(key);
        true
    }

    fn start(&mut self, key: &K) {
        let job = self.jobs.get_mut(key).expect("a due key");
        let bake = job.bake.clone().expect("a waiting bake has its bake");
        self.serial += 1;
        let shared = Arc::new(Shared::default());
        let task = Task { shared: shared.clone(), serial: self.serial, ended: self.ended.0.clone() };
        let what = bake.what();
        let State::Waiting(since) = job.state else { unreachable!("only a waiting bake starts") };
        match bake.start(task) {
            Ok(()) => {
                self.started += 1;
                job.state = State::Running { shared, serial: self.serial, since, started: self.clock.now(), told: false };
            }
            Err(err) => {
                self.failures.push(format!("{what}: {err:#}"));
                job.state = State::Failed;
                job.bake = None;
                self.finished.push(key.clone());
            }
        }
    }

    /// Bakes nothing wants any more, past a few kept for undo.
    fn drop_spare(&mut self, wants: &HashMap<K, Priority>) {
        let unwanted: Vec<K> = self.made.iter().filter(|k| !wants.contains_key(k)).cloned().collect();
        if unwanted.len() > SPARE {
            for key in &unwanted[..unwanted.len() - SPARE] {
                self.jobs.remove(key);
            }
            let jobs = &self.jobs;
            self.made.retain(|k| jobs.contains_key(k));
        }
    }

    /// True when nothing is made or being made.
    pub fn is_empty(&self) -> bool {
        self.jobs.is_empty() && self.made.is_empty()
    }

    /// Forget the bakes of keys that `keep` refuses; a running one is told
    /// to stop, and dropped once it has.
    pub fn retain(&mut self, keep: impl Fn(&K) -> bool) {
        self.jobs.retain(|key, job| match &job.state {
            State::Running { shared, .. } => {
                if !keep(key) {
                    cancel(shared);
                }
                true
            }
            _ => keep(key),
        });
        let jobs = &self.jobs;
        self.made.retain(|k| jobs.contains_key(k));
    }
}

fn cancel(shared: &Shared) {
    shared.cancel.store(true, Ordering::Relaxed);
    shared.woken.notify_one();
}

fn fraction(shared: &Shared) -> f64 {
    match shared.partial.get() {
        Some(made) => made.seconds() / made.whole_seconds().max(1e-9),
        None => f64::from(shared.progress.load(Ordering::Relaxed)) / 1e6,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    use std::sync::Mutex;

    use crate::clock::ManualClock;

    /// A bake that runs until the test ends: it keeps its task and never
    /// ends it, so no thread runs and nothing waits.
    #[derive(Default)]
    struct Hold(Mutex<Vec<Task>>);

    impl Bake for Hold {
        fn lane(&self) -> Lane {
            Lane::Native
        }
        fn what(&self) -> String {
            "holding".into()
        }
        fn start(self: Arc<Self>, task: Task) -> Result<()> {
            self.0.lock().unwrap().push(task);
            Ok(())
        }
    }

    fn hold() -> Option<Arc<dyn Bake>> {
        Some(Arc::new(Hold::default()))
    }

    #[test]
    fn playing_takes_the_place_of_the_oldest_background_bake() {
        let mut bakes: Scheduler<u32> = Scheduler::new(1, 1);
        bakes.ask(&1, hold);
        bakes.poll(&HashMap::from([(1, Priority::Background)]), Duration::ZERO);
        assert_eq!(bakes.status(&1), Status::Running);
        bakes.ask(&2, hold);
        let wants = HashMap::from([(1, Priority::Background), (2, Priority::Playing)]);
        bakes.poll(&wants, Duration::ZERO);
        assert_eq!(bakes.status(&2), Status::Running, "the playing one runs");
        assert_eq!(bakes.status(&1), Status::Waiting, "the background one waits again");
        // An export does not preempt: it waits its turn.
        bakes.ask(&3, hold);
        let mut wants = wants;
        wants.insert(3, Priority::Export);
        bakes.poll(&wants, Duration::ZERO);
        assert_eq!(bakes.status(&3), Status::Waiting);
    }

    #[test]
    fn a_visible_bake_starts_at_the_next_poll_before_twenty_background_bakes() {
        let mut bakes: Scheduler<u32> = Scheduler::new(2, 1);
        let mut wants = HashMap::new();
        for key in 0..19 {
            bakes.ask(&key, hold);
            wants.insert(key, Priority::Background);
        }
        bakes.poll(&wants, Duration::ZERO);
        bakes.ask(&19, hold);
        wants.insert(19, Priority::Background);
        bakes.poll(&wants, Duration::ZERO);
        assert_eq!(bakes.status(&19), Status::Waiting, "the lane is full of background bakes");
        // A window scrolls to the clip of bake 19.
        wants.insert(19, Priority::Visible);
        bakes.poll(&wants, Duration::ZERO);
        assert_eq!(bakes.status(&19), Status::Running, "the visible one runs");
        let busy = bakes.summary();
        assert_eq!((busy.running, busy.waiting), (2, 18), "one background bake gave it its place");
    }

    #[test]
    fn a_value_dragged_through_many_bakes_the_last_only() {
        let clock = Arc::new(ManualClock::default());
        let mut bakes: Scheduler<u32> = Scheduler::new(4, 1);
        bakes.set_clock(clock.clone());
        // A ratio dragged: a new key each 5 ms, each wanted alone.
        for ratio in 0..20 {
            bakes.ask(&ratio, hold);
            bakes.poll(&HashMap::from([(ratio, Priority::Playing)]), SETTLE);
            clock.advance_to(clock.now() + Duration::from_millis(5));
        }
        assert_eq!(bakes.started, 0, "no bake before the last one waited the settle");
        assert_eq!(bakes.next_due(SETTLE), Some(Duration::from_millis(95) + SETTLE), "the last one is due a settle after it was asked for");
        clock.advance_to(Duration::from_millis(95) + SETTLE);
        bakes.poll(&HashMap::from([(19, Priority::Playing)]), SETTLE);
        assert_eq!(bakes.started, 1, "one bake");
        assert_eq!(bakes.status(&19), Status::Running);
    }
}
