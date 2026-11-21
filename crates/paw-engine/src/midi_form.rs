//! What MIDI becomes on its way out of the program.
//!
//! The engine's events are those of MIDI 2.0: fine values, and controllers
//! that belong to one note. A port that takes Universal MIDI Packets is sent
//! them whole. One that speaks MIDI 1.0 is sent the MIDI 1.0 form the route
//! asks for ([`Form`]):
//!
//! - plain: each message as MIDI 1.0 has it, in seven bits; a note's own
//!   bend and controllers are left out (its pressure stays, as poly
//!   pressure).
//! - MPE: every note on a channel of its own, so that its own bend, pressure
//!   and brightness become the channel's pitch bend, channel pressure and
//!   control change 74. The zone is the lower one: channel 1 carries what
//!   is the whole instrument's, the member channels from 2 on carry a note
//!   each, and the zone is announced (MIDI Polyphonic Expression's
//!   configuration message) with a bend range of 48 semitones, a note's own
//!   bend range here.
//! - 14-bit: control changes 0 to 31 as pairs, the fine part on 32 to 63,
//!   as MIDI 1.0 allows for them.
//!
//! A [`Converter`] keeps what it has to: which notes sound where, so that it
//! can end them, and for MPE which channel each note has. It allocates
//! nothing once made.

use crate::event::{Ctl, EventKind, NoteCtl};
use crate::ump;

/// The MIDI 1.0 form a route sends in where the port takes no packets.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub enum Form {
    /// MIDI 2.0 where the port takes it, else plain MIDI 1.0.
    #[default]
    Auto,
    /// MIDI 1.0 as each message has it, even where the port takes packets.
    Plain,
    /// Control changes 0 to 31 in fourteen bits.
    Cc14,
    /// MIDI Polyphonic Expression with this many member channels (1 to 15).
    Mpe(u8),
}

/// The pitch bend range of the member channels of an MPE zone, in
/// semitones: the same as a note's own bend ([`crate::NOTE_BEND_RANGE`]),
/// so that a bend arrives as far as it was meant.
pub const MPE_BEND_RANGE: u8 = 48;

/// One message as it leaves.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Wire {
    /// A Universal MIDI Packet: two words, or one with the second 0.
    Ump([u32; 2]),
    /// A MIDI 1.0 message and how many of its bytes count.
    Midi1([u8; 3], usize),
}

const NONE: u8 = 0xff;
const CENTRE: u16 = 0x2000;

/// The note's own bend, pressure and brightness that an MPE note takes
/// with it to its channel.
const EARLY_BEND: usize = 0;
const EARLY_PRESSURE: usize = 1;
const EARLY_BRIGHTNESS: usize = 2;

pub struct Converter {
    form: Form,
    ump: bool,
    /// Notes sounding, as sent: a bit per key on each channel.
    held: [u128; 16],
    mpe: Option<Box<Mpe>>,
}

/// The channels of an MPE zone and the notes on them.
struct Mpe {
    members: u8,
    /// The zone has been announced.
    ready: bool,
    /// The member channel of each sounding note, by the channel and key the
    /// engine gave it.
    channel_of: [[u8; 128]; 16],
    /// Notes sounding on each channel, and when one last started or ended
    /// there, counted in notes.
    count: [u8; 16],
    used: [u64; 16],
    tick: u64,
    /// The pitch bend last sent on each channel.
    bend: [u16; 16],
    /// What came for a note before it started (bend, pressure, brightness;
    /// NaN for nothing), sent on its channel just before it does.
    early: [[[f32; 3]; 128]; 16],
}

impl Converter {
    /// A converter for a route in `form` to a port that takes packets
    /// (`ump`) or not.
    pub fn new(form: Form, ump: bool) -> Self {
        let mpe = match form {
            Form::Mpe(members) => Some(Box::new(Mpe {
                members: members.clamp(1, 15),
                ready: false,
                channel_of: [[NONE; 128]; 16],
                count: [0; 16],
                used: [0; 16],
                tick: 0,
                bend: [CENTRE; 16],
                early: [[[f32::NAN; 3]; 128]; 16],
            })),
            _ => None,
        };
        Self {
            form,
            ump,
            held: [0; 16],
            mpe,
        }
    }

    pub fn form(&self) -> Form {
        self.form
    }

    /// Whether the port it was made for takes packets.
    pub fn ump(&self) -> bool {
        self.ump
    }

    /// Whether what it sends is MIDI 2.0.
    pub fn sends_ump(&self) -> bool {
        self.ump && self.form == Form::Auto
    }

    /// The messages one event becomes, in order. "All notes off" ends what
    /// this converter left sounding.
    pub fn convert(&mut self, kind: EventKind, emit: &mut impl FnMut(Wire)) {
        if kind == EventKind::AllNotesOff {
            return self.release(emit);
        }
        if self.sends_ump() {
            if let Some(words) = ump::encode(0, kind) {
                self.out(Wire::Ump(words), emit);
            }
            return;
        }
        match self.form {
            Form::Mpe(_) => self.mpe(kind, emit),
            Form::Cc14 => match kind {
                EventKind::Control {
                    ctl: Ctl::Cc(index @ 0..=31),
                    value,
                    ch,
                } => {
                    let wide = ump::scale_down(ump::from_unit(value), 32, 14);
                    let ch = 0xB0 | (ch & 15);
                    self.out(Wire::Midi1([ch, index, (wide >> 7) as u8], 3), emit);
                    self.out(Wire::Midi1([ch, index + 32, (wide & 127) as u8], 3), emit);
                }
                _ => self.plain(kind, emit),
            },
            Form::Auto | Form::Plain => self.plain(kind, emit),
        }
    }

    /// End every note this converter left sounding, with an All Notes Off
    /// on each channel that had one; an MPE zone's bends go back to rest.
    pub fn release(&mut self, emit: &mut impl FnMut(Wire)) {
        let held = std::mem::replace(&mut self.held, [0; 16]);
        let ump = self.sends_ump();
        for (ch, mut keys) in held.into_iter().enumerate() {
            if keys == 0 {
                continue;
            }
            let ch = ch as u8;
            while keys != 0 {
                let key = keys.trailing_zeros() as u8;
                keys &= !(1 << key);
                if ump {
                    let off = ump::encode(0, EventKind::NoteOff { key, ch });
                    emit(Wire::Ump(off.unwrap_or_default()));
                } else {
                    emit(Wire::Midi1([0x80 | ch, key, 0], 3));
                }
            }
            if ump {
                // MIDI 2.0 has no mode messages of its own: they go as MIDI
                // 1.0 messages in a packet of one word.
                emit(Wire::Ump([0x20b0_7b00 | (ch as u32) << 16, 0]));
            } else {
                emit(Wire::Midi1([0xB0 | ch, 123, 0], 3));
            }
        }
        if let Some(mpe) = self.mpe.as_deref_mut() {
            for ch in 1..=mpe.members {
                if mpe.bend[ch as usize] != CENTRE {
                    mpe.bend[ch as usize] = CENTRE;
                    emit(Wire::Midi1([0xE0 | ch, 0, (CENTRE >> 7) as u8], 3));
                }
            }
            mpe.channel_of = [[NONE; 128]; 16];
            mpe.count = [0; 16];
            mpe.early = [[[f32::NAN; 3]; 128]; 16];
        }
    }

    /// Send a message, remembering which notes it starts and ends.
    fn out(&mut self, wire: Wire, emit: &mut impl FnMut(Wire)) {
        let (on, ch, key) = match wire {
            Wire::Ump([w0, _]) if w0 >> 28 == 4 => match (w0 >> 20) & 15 {
                9 => (Some(true), (w0 >> 16) & 15, (w0 >> 8) & 127),
                8 => (Some(false), (w0 >> 16) & 15, (w0 >> 8) & 127),
                _ => (None, 0, 0),
            },
            Wire::Midi1([status, key, vel], _) => match status & 0xF0 {
                0x90 => (Some(vel > 0), (status & 15) as u32, (key & 127) as u32),
                0x80 => (Some(false), (status & 15) as u32, (key & 127) as u32),
                _ => (None, 0, 0),
            },
            _ => (None, 0, 0),
        };
        match on {
            Some(true) => self.held[ch as usize] |= 1 << key,
            Some(false) => self.held[ch as usize] &= !(1 << key),
            None => {}
        }
        emit(wire);
    }

    fn plain(&mut self, kind: EventKind, emit: &mut impl FnMut(Wire)) {
        ump::midi1(kind, |bytes, len| {
            self.out(Wire::Midi1(bytes, len as usize), emit)
        });
    }

    fn mpe(&mut self, kind: EventKind, emit: &mut impl FnMut(Wire)) {
        let mut mpe = self.mpe.take().expect("an MPE converter has a zone");
        mpe.announce(emit);
        match kind {
            EventKind::NoteOn { key, vel, ch, .. } => self.mpe_note_on(&mut mpe, ch, key, vel, emit),
            EventKind::NoteOff { key, ch } => self.mpe_note_off(&mut mpe, ch, key, emit),
            EventKind::NoteControl {
                key,
                ctl,
                value,
                ch,
            } => mpe.note_control(ch, key, ctl, value, emit),
            // What is the whole instrument's goes on the manager channel.
            EventKind::Control { ctl, value, .. } => {
                self.plain(EventKind::Control { ctl, value, ch: 0 }, emit)
            }
            EventKind::Program { program, bank, .. } => {
                self.plain(EventKind::Program { program, bank, ch: 0 }, emit)
            }
            EventKind::AllNotesOff => {}
        }
        self.mpe = Some(mpe);
    }

    /// A note starts on a member channel of its own, with what came for it
    /// before it started.
    fn mpe_note_on(
        &mut self,
        mpe: &mut Mpe,
        ch: u8,
        key: u8,
        vel: f32,
        emit: &mut impl FnMut(Wire),
    ) {
        let (from, key) = ((ch & 15) as usize, key & 127);
        // A note started again ends where it was first.
        let was = mpe.channel_of[from][key as usize];
        if was != NONE {
            mpe.count[was as usize] = mpe.count[was as usize].saturating_sub(1);
            self.out(Wire::Midi1([0x80 | was, key, 0], 3), emit);
        }
        let to = mpe.allocate();
        mpe.channel_of[from][key as usize] = to;
        mpe.count[to as usize] += 1;
        let early = std::mem::replace(&mut mpe.early[from][key as usize], [f32::NAN; 3]);
        // The channel's bend is the note's own from its start, so
        // the bend another note left there is put back first.
        let bend = if early[EARLY_BEND].is_nan() {
            CENTRE
        } else {
            ump::to_bend14(early[EARLY_BEND] as f64)
        };
        if mpe.bend[to as usize] != bend {
            mpe.bend[to as usize] = bend;
            emit(bend_message(to, bend));
        }
        if !early[EARLY_PRESSURE].is_nan() {
            emit(Wire::Midi1([0xD0 | to, ump::to7(early[EARLY_PRESSURE] as f64), 0], 2));
        }
        if !early[EARLY_BRIGHTNESS].is_nan() {
            emit(Wire::Midi1([0xB0 | to, 74, ump::to7(early[EARLY_BRIGHTNESS] as f64)], 3));
        }
        self.out(Wire::Midi1([0x90 | to, key, ump::to_velocity7(vel)], 3), emit);
    }

    /// A note ends on its member channel, which is then free.
    fn mpe_note_off(&mut self, mpe: &mut Mpe, ch: u8, key: u8, emit: &mut impl FnMut(Wire)) {
        let (from, key) = ((ch & 15) as usize, key & 127);
        mpe.early[from][key as usize] = [f32::NAN; 3];
        let to = std::mem::replace(&mut mpe.channel_of[from][key as usize], NONE);
        if to != NONE {
            mpe.count[to as usize] = mpe.count[to as usize].saturating_sub(1);
            mpe.used[to as usize] = mpe.next();
            self.out(Wire::Midi1([0x80 | to, key, 0], 3), emit);
        }
    }
}

impl Mpe {
    /// Announce the zone, before the first message.
    fn announce(&mut self, emit: &mut impl FnMut(Wire)) {
        if self.ready {
            return;
        }
        self.ready = true;
        // The zone: channel 1 manages, `members` channels follow
        // (registered parameter 6 on the manager channel).
        for message in rpn(0, 6, self.members) {
            emit(message);
        }
        // Each member channel bends as far as a note's own bend reaches.
        for ch in 1..=self.members {
            for message in rpn(ch, 0, MPE_BEND_RANGE) {
                emit(message);
            }
        }
    }

    /// A note's own controller goes on its member channel; before the note
    /// starts, it is kept for when it does.
    fn note_control(
        &mut self,
        ch: u8,
        key: u8,
        ctl: NoteCtl,
        value: f64,
        emit: &mut impl FnMut(Wire),
    ) {
        let (from, key) = ((ch & 15) as usize, key & 127);
        let to = self.channel_of[from][key as usize];
        if to == NONE {
            // Before the note: kept for when it starts.
            let slot = match ctl {
                NoteCtl::Bend => Some(EARLY_BEND),
                NoteCtl::Pressure => Some(EARLY_PRESSURE),
                NoteCtl::Registered(74) => Some(EARLY_BRIGHTNESS),
                _ => None,
            };
            if let Some(slot) = slot {
                self.early[from][key as usize][slot] = value as f32;
            }
            return;
        }
        match ctl {
            NoteCtl::Bend => {
                let bend = ump::to_bend14(value);
                self.bend[to as usize] = bend;
                emit(bend_message(to, bend));
            }
            NoteCtl::Pressure => emit(Wire::Midi1([0xD0 | to, ump::to7(value), 0], 2)),
            // A registered per-note controller means what the
            // control change of its number does; the channel is
            // the note's alone.
            NoteCtl::Registered(index @ 0..=119) => {
                emit(Wire::Midi1([0xB0 | to, index, ump::to7(value)], 3))
            }
            NoteCtl::Registered(_) | NoteCtl::Assignable(_) => {}
        }
    }

    fn next(&mut self) -> u64 {
        self.tick += 1;
        self.tick
    }

    /// The member channel for a new note: a free one, the one let go of
    /// longest ago so that a note's release is not cut into; with none
    /// free, the one with the fewest notes, longest unused among them.
    fn allocate(&mut self) -> u8 {
        let now = self.next();
        let members = 1..=self.members;
        let best = members
            .clone()
            .filter(|&ch| self.count[ch as usize] == 0)
            .min_by_key(|&ch| self.used[ch as usize])
            .or_else(|| members.min_by_key(|&ch| (self.count[ch as usize], self.used[ch as usize])))
            .unwrap_or(1);
        self.used[best as usize] = now;
        best
    }
}

fn bend_message(ch: u8, bend: u16) -> Wire {
    Wire::Midi1([0xE0 | ch, (bend & 127) as u8, (bend >> 7) as u8], 3)
}

/// A registered parameter set on a channel, then put back to none so that a
/// stray data entry changes nothing.
fn rpn(ch: u8, index: u8, value: u8) -> [Wire; 6] {
    let cc = |number: u8, value: u8| Wire::Midi1([0xB0 | ch, number, value], 3);
    [
        cc(101, 0),
        cc(100, index),
        cc(6, value),
        cc(38, 0),
        cc(101, 127),
        cc(100, 127),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(conv: &mut Converter, events: &[EventKind]) -> Vec<Wire> {
        let mut out = Vec::new();
        for &kind in events {
            conv.convert(kind, &mut |w| out.push(w));
        }
        out
    }

    fn bytes(wires: &[Wire]) -> Vec<Vec<u8>> {
        wires
            .iter()
            .filter_map(|w| match w {
                Wire::Midi1(b, len) => Some(b[..*len].to_vec()),
                Wire::Ump(_) => None,
            })
            .collect()
    }

    fn on(key: u8, ch: u8) -> EventKind {
        EventKind::NoteOn {
            key,
            vel: 0.8,
            ch,
            attr: crate::event::Attr::NONE,
        }
    }

    fn off(key: u8, ch: u8) -> EventKind {
        EventKind::NoteOff { key, ch }
    }

    fn bend(key: u8, value: f64) -> EventKind {
        EventKind::NoteControl {
            key,
            ctl: NoteCtl::Bend,
            value,
            ch: 0,
        }
    }

    /// The channel (from 0) of each note-on, in order.
    fn note_channels(wires: &[Wire]) -> Vec<u8> {
        bytes(wires)
            .iter()
            .filter(|b| b[0] & 0xF0 == 0x90)
            .map(|b| b[0] & 15)
            .collect()
    }

    #[test]
    fn a_port_that_takes_packets_is_sent_midi_2_whole() {
        let events = [
            on(60, 2),
            bend(60, 0.123456),
            EventKind::Control {
                ctl: Ctl::Cc(74),
                value: 0.3,
                ch: 2,
            },
        ];
        let mut conv = Converter::new(Form::Auto, true);
        let got = run(&mut conv, &events);
        let want: Vec<Wire> = events
            .iter()
            .map(|&e| Wire::Ump(ump::encode(0, e).unwrap()))
            .collect();
        assert_eq!(got, want);
        // Ended with a note-off packet and All Notes Off in a one-word packet.
        let mut end = Vec::new();
        conv.release(&mut |w| end.push(w));
        assert_eq!(
            end,
            [
                Wire::Ump(ump::encode(0, off(60, 2)).unwrap()),
                Wire::Ump([0x20b2_7b00, 0])
            ]
        );
        // The same route to a port of MIDI 1.0 sends MIDI 1.0, and the note's
        // own bend has nowhere to go.
        let mut conv = Converter::new(Form::Auto, false);
        assert_eq!(
            bytes(&run(&mut conv, &events)),
            [vec![0x92, 60, ump::to_velocity7(0.8)], vec![0xB2, 74, ump::to7(0.3)]]
        );
        // Plain asks for MIDI 1.0 even where packets would go.
        let mut conv = Converter::new(Form::Plain, true);
        assert!(!conv.sends_ump());
        assert_eq!(bytes(&run(&mut conv, &events)).len(), 2);
    }

    #[test]
    fn control_changes_below_32_go_in_fourteen_bits() {
        let mut conv = Converter::new(Form::Cc14, false);
        let got = run(
            &mut conv,
            &[
                EventKind::Control {
                    ctl: Ctl::Cc(1),
                    value: 0.5,
                    ch: 3,
                },
                EventKind::Control {
                    ctl: Ctl::Cc(7),
                    value: ump::unit(ump::scale_up(0x1234, 14, 32)),
                    ch: 0,
                },
                // Past 31 there is no pair: seven bits, as before.
                EventKind::Control {
                    ctl: Ctl::Cc(74),
                    value: 1.0,
                    ch: 0,
                },
            ],
        );
        assert_eq!(
            bytes(&got),
            [
                vec![0xB3, 1, 0x40],
                vec![0xB3, 33, 0],
                vec![0xB0, 7, (0x1234u16 >> 7) as u8],
                vec![0xB0, 39, (0x1234u16 & 127) as u8],
                vec![0xB0, 74, 127],
            ]
        );
    }

    #[test]
    fn mpe_announces_its_zone_and_bend_range_first() {
        let mut conv = Converter::new(Form::Mpe(3), false);
        let got = bytes(&run(&mut conv, &[on(60, 0)]));
        // The configuration message: registered parameter 6 on channel 1.
        assert_eq!(got[..4], [vec![0xB0, 101, 0], vec![0xB0, 100, 6], vec![0xB0, 6, 3], vec![0xB0, 38, 0]]);
        // A bend range of 48 semitones on each member channel.
        for ch in 1..=3u8 {
            let at = 6 * ch as usize;
            assert_eq!(got[at..at + 3], [vec![0xB0 | ch, 101, 0], vec![0xB0 | ch, 100, 0], vec![0xB0 | ch, 6, 48]]);
        }
        assert_eq!(got.last().unwrap()[..2], [0x91, 60]);
        // Only once.
        assert_eq!(bytes(&run(&mut conv, &[on(62, 0)])), [vec![0x92, 62, ump::to_velocity7(0.8)]]);
    }

    #[test]
    fn mpe_gives_each_note_a_channel_and_its_own_bend_there() {
        let mut conv = Converter::new(Form::Mpe(15), false);
        let got = run(&mut conv, &[on(60, 0), on(64, 0), on(67, 0)]);
        assert_eq!(note_channels(&got), [1, 2, 3], "a chord across channels 2, 3 and 4");
        // One semitone up on E: the pitch bend of its channel, a 48th of
        // the way up.
        let got = bytes(&run(&mut conv, &[bend(64, 1.0 / 48.0)]));
        let wheel = ump::to_bend14(1.0 / 48.0);
        assert!((170..=171).contains(&(wheel - 8192)), "{wheel}");
        assert_eq!(got, [vec![0xE2, (wheel & 127) as u8, (wheel >> 7) as u8]]);
        // Pressure and brightness of one note go to its channel too.
        let got = bytes(&run(
            &mut conv,
            &[
                EventKind::NoteControl {
                    key: 67,
                    ctl: NoteCtl::Pressure,
                    value: 1.0,
                    ch: 0,
                },
                EventKind::NoteControl {
                    key: 67,
                    ctl: NoteCtl::Registered(74),
                    value: 0.0,
                    ch: 0,
                },
            ],
        ));
        assert_eq!(got, [vec![0xD3, 127], vec![0xB3, 74, 0]]);
        // What is the whole instrument's goes on the manager channel,
        // whatever channel it came on.
        let got = bytes(&run(
            &mut conv,
            &[EventKind::Control {
                ctl: Ctl::Cc(64),
                value: 1.0,
                ch: 5,
            }],
        ));
        assert_eq!(got, [vec![0xB0, 64, 127]]);
        // A note ends on its channel.
        assert_eq!(bytes(&run(&mut conv, &[off(64, 0)])), [vec![0x82, 64, 0]]);
    }

    #[test]
    fn mpe_reuses_the_channel_let_go_of_longest_ago() {
        let mut conv = Converter::new(Form::Mpe(3), false);
        run(&mut conv, &[on(60, 0), on(62, 0), on(64, 0)]);
        // 62 and then 60 end: a new note takes 62's channel, which has rung
        // out longest, not 60's, whose release may still sound.
        run(&mut conv, &[off(62, 0), off(60, 0)]);
        assert_eq!(note_channels(&run(&mut conv, &[on(65, 0)])), [2]);
        assert_eq!(note_channels(&run(&mut conv, &[on(67, 0)])), [1]);
        // Every channel busy: the next shares the one whose note is oldest.
        assert_eq!(note_channels(&run(&mut conv, &[on(69, 0)])), [3]);
        // The bend a note left on its channel is put back before the next
        // note there; a bend that came before its note goes first.
        run(&mut conv, &[bend(65, 0.5), off(65, 0)]);
        let got = bytes(&run(&mut conv, &[bend(71, -0.25), on(71, 0)]));
        let wheel = ump::to_bend14(-0.25);
        assert_eq!(
            got,
            [
                vec![0xE2, (wheel & 127) as u8, (wheel >> 7) as u8],
                vec![0x92, 71, ump::to_velocity7(0.8)]
            ]
        );
        let got = bytes(&run(&mut conv, &[off(71, 0), on(72, 0)]));
        assert_eq!(got[1][0], 0xE2, "back to rest before the next note on the channel");
        assert_eq!(got[1][1..], [0, 0x40]);
    }

    #[test]
    fn all_notes_off_ends_every_note_where_it_was_sent() {
        let mut conv = Converter::new(Form::Mpe(4), false);
        run(&mut conv, &[on(60, 0), on(64, 0), bend(64, 0.5)]);
        let got = bytes(&run(&mut conv, &[EventKind::AllNotesOff]));
        assert_eq!(
            got,
            [
                vec![0x81, 60, 0],
                vec![0xB1, 123, 0],
                vec![0x82, 64, 0],
                vec![0xB2, 123, 0],
                vec![0xE2, 0, 0x40]
            ]
        );
        assert!(run(&mut conv, &[EventKind::AllNotesOff]).is_empty(), "nothing left");
        // A note that never started ends nothing.
        assert!(run(&mut conv, &[off(50, 0)]).is_empty());
    }
}
