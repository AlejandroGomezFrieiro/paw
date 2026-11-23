//! The upkeep of a turn: the parts of the session that have work outside
//! the turn, on other threads, in other processes, in the engine or at a
//! later time.
//!
//! Each part is an [`Upkeep`]: it says which bell its workers ring
//! ([`Woken`]), takes in their results in each turn, and tells the loop
//! what it has left ([`Agenda`]): work ready now, work in flight, the next
//! due time, and a tick when it has news that rings no bell. The loop
//! sleeps on the union of the agendas, so a session with nothing in
//! flight and nothing due sleeps until a message or a ring.
//!
//! The parts hold no state of their own: the state is the session's (the
//! sync, the API and the parts share it). A part is a way to look at the
//! session, and [`UPKEEPS`] is the list, in the order of a turn.

use std::time::Duration;

use super::Session;
use crate::clock::{Agenda, ScheduleTime};
use crate::doorbell::Woken;

/// How often the loop looks while a part has news that rings no bell and
/// is seen: a plugin's open window, a take the engine lets go of.
pub(crate) const FRAME: Duration = Duration::from_millis(16);

/// How often what plays is read ahead from the disk.
pub(crate) const READ_AHEAD: Duration = Duration::from_millis(250);

/// How often the loop looks while a plugin is live and nothing asks for
/// more: it sees a plugin that asked for a call (a mark of any thread),
/// or that stopped.
pub(crate) const PLUGIN_LOOK: Duration = Duration::from_millis(250);

/// A part of the session with work outside the turn.
pub(crate) trait Upkeep {
    /// Its name in `paw.api.pending().in_flight`.
    fn name(&self) -> &'static str;
    /// The bell of its workers: the bit that tells the loop of its news.
    fn kind(&self) -> Woken;
    /// Take in what its workers did, and do what is due at the time of the
    /// turn. Gives true when a result of a worker came in: the news that
    /// the workers ring for.
    fn poll(&self, session: &mut Session) -> bool;
    /// What it has left at `now`.
    fn agenda(&self, session: &Session, now: ScheduleTime) -> Agenda;
}

/// Takes that stopped: the engine lets go of them, the writers finish
/// their files, and they become clips.
struct Takes;

impl Upkeep for Takes {
    fn name(&self) -> &'static str {
        "takes"
    }
    fn kind(&self) -> Woken {
        Woken::TAKES
    }
    fn poll(&self, session: &mut Session) -> bool {
        session.poll_takes()
    }
    fn agenda(&self, session: &Session, _: ScheduleTime) -> Agenda {
        session.takes_agenda()
    }
}

/// A render on a thread of its own.
struct Render;

impl Upkeep for Render {
    fn name(&self) -> &'static str {
        "renders"
    }
    fn kind(&self) -> Woken {
        Woken::RENDER
    }
    fn poll(&self, session: &mut Session) -> bool {
        session.render_poll()
    }
    fn agenda(&self, session: &Session, _: ScheduleTime) -> Agenda {
        session.render_agenda()
    }
}

/// What the engine plays from the disk: a file heard on its own, read on
/// a thread of its own, and the song, read ahead of the playhead.
struct Playback;

impl Upkeep for Playback {
    fn name(&self) -> &'static str {
        "preview"
    }
    fn kind(&self) -> Woken {
        Woken::PREVIEW
    }
    fn poll(&self, session: &mut Session) -> bool {
        session.poll_preview()
    }
    fn agenda(&self, session: &Session, _: ScheduleTime) -> Agenda {
        session.preview_agenda() | session.read_ahead_agenda()
    }
}

/// Plugins made apart from the loop.
struct Loads;

impl Upkeep for Loads {
    fn name(&self) -> &'static str {
        "loads"
    }
    fn kind(&self) -> Woken {
        Woken::LOADS
    }
    fn poll(&self, session: &mut Session) -> bool {
        session.poll_loads()
    }
    fn agenda(&self, session: &Session, _: ScheduleTime) -> Agenda {
        Agenda { in_flight: count(session.loads.in_flight()), ..Agenda::default() }
    }
}

/// The hash worker, which learns the files of the project.
struct Hashes;

impl Upkeep for Hashes {
    fn name(&self) -> &'static str {
        "hashes"
    }
    fn kind(&self) -> Woken {
        Woken::HASHES
    }
    fn poll(&self, session: &mut Session) -> bool {
        session.poll_hashes()
    }
    fn agenda(&self, session: &Session, _: ScheduleTime) -> Agenda {
        Agenda { in_flight: count(session.sources.hashing()), ..Agenda::default() }
    }
}

/// Bakes on threads and in helper processes, and the tidy of their cache.
struct Bakes;

impl Upkeep for Bakes {
    fn name(&self) -> &'static str {
        "bakes"
    }
    fn kind(&self) -> Woken {
        Woken::BAKES
    }
    fn poll(&self, session: &mut Session) -> bool {
        session.poll_bakes()
    }
    fn agenda(&self, session: &Session, _: ScheduleTime) -> Agenda {
        session.bakes_agenda()
    }
}

/// The audio device and the MIDI ports, looked at on a period.
struct Devices;

impl Upkeep for Devices {
    fn name(&self) -> &'static str {
        "devices"
    }
    fn kind(&self) -> Woken {
        Woken::DEVICES
    }
    fn poll(&self, session: &mut Session) -> bool {
        session.watch_devices();
        false
    }
    fn agenda(&self, session: &Session, _: ScheduleTime) -> Agenda {
        let next_due = session.watching().then(|| session.watch.next_due());
        Agenda { next_due, ..Agenda::default() }
    }
}

/// The files of the project that change outside paw.
struct Files;

impl Upkeep for Files {
    fn name(&self) -> &'static str {
        "files"
    }
    fn kind(&self) -> Woken {
        Woken::FILES
    }
    fn poll(&self, session: &mut Session) -> bool {
        session.poll_file_changes()
    }
    fn agenda(&self, session: &Session, _: ScheduleTime) -> Agenda {
        Agenda { next_due: session.files_watch.next_due(), ..Agenda::default() }
    }
}

/// The main-thread side of the plugins: their idle calls, their windows,
/// what they changed by themselves, the states that their lanes give
/// while the song plays.
struct Plugins;

impl Upkeep for Plugins {
    fn name(&self) -> &'static str {
        "plugins"
    }
    fn kind(&self) -> Woken {
        Woken::PLUGINS
    }
    fn poll(&self, session: &mut Session) -> bool {
        session.play_states();
        let mut scan = session.scan_devices();
        session.emit_device_scan(&mut scan);
        session.apply_device_scan(scan);
        // A plugin marks, and does not ring: its news is seen on a tick.
        false
    }
    fn agenda(&self, session: &Session, _: ScheduleTime) -> Agenda {
        session.plugins_agenda()
    }
}

/// The parts, in the order of a turn.
pub(crate) const UPKEEPS: [&dyn Upkeep; 9] =
    [&Takes, &Render, &Playback, &Loads, &Hashes, &Bakes, &Devices, &Files, &Plugins];

fn count(n: usize) -> u32 {
    u32::try_from(n).unwrap_or(u32::MAX)
}

impl Session {
    /// The upkeep of a turn, at the time of the turn
    /// ([`set_now`](Self::set_now)): the stepped engine plays its blocks
    /// first, then each part of [`UPKEEPS`] takes in what came. Gives the
    /// kinds of news that came in.
    pub(crate) fn idle(&mut self) -> Woken {
        // The stepped engine plays up to the time of the turn first: what
        // it played is then heard of below.
        self.run_stepped_audio();
        // A take whose file could not be written stops; what it has is kept.
        if self.rec.take.as_ref().is_some_and(|t| t.shared.failed()) {
            self.stop();
        }
        let mut news = Woken::empty();
        for part in UPKEEPS {
            if part.poll(self) {
                news |= part.kind();
            }
        }
        news
    }

    /// What the parts of the session have left at `now`.
    pub(crate) fn agenda(&self, now: ScheduleTime) -> Agenda {
        UPKEEPS.iter().fold(Agenda::default(), |agenda, part| agenda | part.agenda(self, now))
    }

    /// The work in flight, by the name of its part: the parts with none
    /// are left out.
    pub(crate) fn in_flight(&self, now: ScheduleTime) -> Vec<(&'static str, u32)> {
        UPKEEPS
            .iter()
            .map(|part| (part.name(), part.agenda(self, now).in_flight))
            .filter(|(_, n)| *n > 0)
            .collect()
    }

    /// What the plugins leave for the loop: those that have not told yet
    /// that they took a state on are in flight. The loop looks each frame
    /// while one asks for it (an open window) or a state lane gives states
    /// as the song plays, and now and then while any plugin is live.
    fn plugins_agenda(&self) -> Agenda {
        let controllers = || self.live.values().filter_map(|live| live.controller.as_ref());
        let pending = controllers().filter(|controller| controller.state_pending()).count();
        let lanes = self.play.playing && !self.engine.map.state_main.is_empty();
        let tick = if lanes || controllers().any(|controller| controller.wants_idle()) {
            Some(FRAME)
        } else {
            controllers().next().is_some().then_some(PLUGIN_LOOK)
        };
        Agenda { in_flight: count(pending), tick, ..Agenda::default() }
    }

    /// Whether the engine plays something that changes the state as it
    /// plays: the song plays or records, a take is let go of, or a file is
    /// heard on its own.
    pub(crate) fn plays(&self) -> bool {
        let previewing = self.preview_view().get("state").and_then(|s| s.as_str()).is_some_and(|state| state == "playing" || state == "loading");
        self.play.playing || self.transport.recording || !self.rec.closing.is_empty() || previewing
    }
}

#[cfg(test)]
mod tests {
    use paw_engine::Registry;
    use paw_engine::backend::{BackendChoice, BackendOptions};
    use paw_engine::record::TakeFile;

    use super::*;
    use crate::doorbell::Waiter;

    /// A session on the null backend whose workers ring `waiter`.
    fn session(waiter: &Waiter) -> Session {
        let backend = BackendOptions { backend: BackendChoice::Null, ..Default::default() };
        let mut session = Session::new(&backend, Registry::with_builtins()).unwrap();
        session.set_doorbell(waiter.doorbell().clone());
        session
    }

    #[test]
    fn a_new_session_is_quiet_with_no_due_time_and_no_tick() {
        let waiter = Waiter::new().unwrap();
        let session = session(&waiter);
        let agenda = session.agenda(ScheduleTime::ZERO);
        assert_eq!(agenda, Agenda::default(), "nothing ready, in flight or due");
        assert!(session.in_flight(ScheduleTime::ZERO).is_empty());
    }

    #[test]
    fn a_sound_file_that_loads_for_a_preview_rings_and_its_part_has_news() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("tone.wav");
        let mut file = TakeFile::create(&path, 48000, 1).unwrap();
        file.write(&[0.5; 480], &mut Vec::new()).unwrap();
        file.finish().unwrap();
        let waiter = Waiter::new().unwrap();
        let mut session = session(&waiter);
        session.preview_play(&path).unwrap();
        assert_eq!(session.in_flight(ScheduleTime::ZERO), [("preview", 1)], "it loads on a thread");
        waiter.wait(None).unwrap();
        assert_eq!(waiter.doorbell().take(), Woken::PREVIEW);
        assert!(Playback.poll(&mut session), "the sound that came is news");
        assert_eq!(Playback.agenda(&session, ScheduleTime::ZERO).in_flight, 0);
    }
}
