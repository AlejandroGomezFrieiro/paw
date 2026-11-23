//! The transport: play, stop, seek, loop, count-in and recording.

use crate::events::{KernelEvent as E, Nothing, Play, Position};
use super::*;

/// Whether the song plays, and the seeks asked of the engine that it has
/// not yet made.
#[derive(Default)]
pub(super) struct Playback {
    pub playing: bool,
    /// Beats of the count-in last asked of the engine: what is still to be
    /// counted until the engine says otherwise.
    pub count_sent: u32,
    pub seeks: u32,
    pub seek_target: f64,
}

impl Session {
    pub(super) fn send_transport(&mut self) {
        let t = &self.transport;
        self.engine.handle.send(Msg::SetLoop {
            enabled: t.loop_enabled,
            start: t.loop_start,
            end: t.loop_end,
        });
        self.engine.handle.send(Msg::SetMetronome(t.metronome));
        self.engine.handle.send(Msg::SetClick {
            gain: paw_engine::db_to_gain(t.click_level),
            accent: t.click_accent,
            output: t.click_output as u16,
        });
    }

    /// Where a take punched in from a stop starts playing: the pre-roll
    /// before the punch in, but never later than the playhead (a playhead
    /// further back is left alone), and not at all when the playhead is
    /// inside the range or past it.
    pub(super) fn pre_roll_start(&self) -> Option<f64> {
        let t = &self.transport;
        if !t.recording || self.play.playing || !t.punch_enabled || t.punch_end <= t.punch_start {
            return None;
        }
        if t.pre_roll == 0 && t.pre_roll_seconds <= 0.0 {
            return None;
        }
        let at = self.position();
        if at > t.punch_start + 1e-9 {
            return None;
        }
        let map = self.doc.project.tempo_map();
        let bar = (map.bar_of(t.punch_start) - t.pre_roll as i64).max(0);
        let from = map.bar_start(bar);
        let from = map.beat((map.seconds(from) - t.pre_roll_seconds).max(0.0));
        Some(from.min(at))
    }

    pub(crate) fn play(&mut self) {
        if let Some(from) = self.pre_roll_start() {
            self.seek(from);
        }
        self.flush();
        if self.transport.recording {
            self.start_take();
        }
        self.read_ahead_from(self.position());
        // A take begun with the song stopped is counted in first.
        let count = (self.transport.recording && !self.play.playing && self.transport.count_in > 0)
            .then(|| self.count_in())
            .flatten();
        let beats = match count {
            Some((msg, beats)) => {
                self.engine.handle.send(msg);
                beats
            }
            None => {
                self.engine.handle.send(Msg::Play);
                0
            }
        };
        self.play.count_sent = beats;
        self.play.playing = true;
        let position = self.position();
        self.doc.emit(E::TransportPlay(Play { position, count_in: beats as f64 }));
    }

    /// The count-in before playing from where the playhead is: as many bars
    /// as `count_in` says, at the tempo and in the signature there, a click
    /// for every beat of the signature. The message for the engine, and how
    /// many beats it counts.
    pub(super) fn count_in(&self) -> Option<(Msg, u32)> {
        let map = self.doc.project.tempo_map();
        let at = self.position();
        let (num, den) = map.signature(at);
        let every = 60.0 / map.tempo(at) * 4.0 / den as f64 * self.engine.handle.sample_rate;
        let clicks = self.transport.count_in.min(16) * num;
        let frames = (clicks as f64 * every).round() as u64;
        (frames > 0).then_some((
            Msg::CountIn {
                frames,
                every,
                clicks,
                per_bar: num,
            },
            clicks,
        ))
    }

    /// Beats of a count-in still to be counted before the song starts; 0
    /// when none is under way.
    pub(crate) fn counting(&self) -> u32 {
        let shared = &self.engine.handle.shared;
        if !self.play.playing || shared.playing() {
            return 0;
        }
        // Until the engine has taken the count up, it is all still to come.
        match shared.counting() {
            0 => self.play.count_sent,
            left => left,
        }
    }

    /// Stop the song, and with it the take being recorded. This never waits
    /// for the engine: the take becomes clips later
    /// ([`poll_takes`](Self::poll_takes)).
    pub(crate) fn stop(&mut self) {
        if !self.play.playing {
            return;
        }
        // The song stops where it is now. The engine stops at the start of
        // its next block, which can be one block further on: a seek puts it
        // back here, and until the engine has made it, `position` reads
        // this place (as for any seek).
        let position = self.position();
        self.engine.handle.send(Msg::Stop);
        self.engine.handle.send(Msg::Seek(position));
        self.play.seeks = self.play.seeks.wrapping_add(1);
        self.play.seek_target = position;
        self.play.playing = false;
        self.doc.emit(E::TransportStop(Position { position }));
        // Stopping ends the take and, with it, record mode: the next
        // play is a play, not another take over the one just made.
        if self.rec.take.is_some() {
            self.transport.recording = false;
            self.doc.emit(E::TransportChanged(Nothing {}));
        }
        self.close_take();
    }

    pub(crate) fn seek(&mut self, beats: f64) {
        let beats = beats.max(0.0);
        // A take is continuous, so jumping ends it and starts another.
        let recording = self.rec.take.is_some();
        self.close_take();
        self.engine.handle.send(Msg::Seek(beats));
        self.play.seeks = self.play.seeks.wrapping_add(1);
        self.play.seek_target = beats;
        self.read_ahead_from(beats);
        self.doc.emit(E::TransportSeek(Position { position: beats }));
        if recording && self.play.playing {
            self.start_take();
        }
    }

    /// Turn on recording and play.
    pub(crate) fn record(&mut self) -> Result<()> {
        self.transport_set("recording", Value::Bool(true))?;
        if !self.play.playing {
            self.play();
        }
        Ok(())
    }
}
