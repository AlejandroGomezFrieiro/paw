//! Universal MIDI Packets: the wire format of MIDI 2.0.
//!
//! [`decode`] reads the channel voice messages of both protocols (MIDI 1.0
//! in a packet of one word, MIDI 2.0 in a packet of two) into the engine's
//! events, and [`encode`] writes events as MIDI 2.0 messages. The scaling
//! between resolutions follows the MIDI 2.0 specification's translation
//! rules, so that a value's lowest, centre and highest positions stay where
//! they are whichever way it is converted.
#![expect(clippy::cast_lossless, reason = "debt: pay down")]
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![cfg_attr(test, expect(clippy::cast_precision_loss, reason = "debt: pay down"))]
#![expect(clippy::cast_sign_loss, reason = "debt: pay down")]
#![cfg_attr(test, expect(clippy::float_cmp, reason = "debt: pay down"))]

use crate::event::{Attr, Ctl, EventKind, NoteCtl};

/// Widen a value of `from` bits to `to` bits, keeping zero, the centre and
/// the top where they are (the specification's min-centre-max scaling).
pub fn scale_up(value: u32, from: u32, to: u32) -> u32 {
    let shift = to - from;
    let shifted = value << shift;
    let centre = 1u32 << (from - 1);
    if value <= centre {
        return shifted;
    }
    // Above the centre, repeat the bits below the top one down the new bits.
    let repeat_bits = from - 1;
    let mut repeat = value & ((1 << repeat_bits) - 1);
    if shift > repeat_bits {
        repeat <<= shift - repeat_bits;
    } else {
        repeat >>= repeat_bits - shift;
    }
    let mut out = shifted;
    while repeat != 0 {
        out |= repeat;
        repeat >>= repeat_bits;
    }
    out
}

/// Narrow a value of `from` bits to `to` bits.
pub fn scale_down(value: u32, from: u32, to: u32) -> u32 {
    value >> (from - to)
}

/// A 32-bit controller value as a fraction from 0 to 1.
pub fn unit(data: u32) -> f64 {
    data as f64 / u32::MAX as f64
}

/// A fraction from 0 to 1 as a 32-bit controller value.
pub fn from_unit(value: f64) -> u32 {
    (value.clamp(0.0, 1.0) * u32::MAX as f64).round() as u32
}

const CENTRE: u32 = 0x8000_0000;

/// A 32-bit value with its centre at rest, as a fraction from -1 to 1.
pub fn bipolar(data: u32) -> f64 {
    if data >= CENTRE {
        (data - CENTRE) as f64 / (u32::MAX - CENTRE) as f64
    } else {
        -((CENTRE - data) as f64) / CENTRE as f64
    }
}

/// A fraction from -1 to 1 as a 32-bit value with its centre at rest.
pub fn from_bipolar(value: f64) -> u32 {
    let value = value.clamp(-1.0, 1.0);
    if value >= 0.0 {
        CENTRE + (value * (u32::MAX - CENTRE) as f64).round() as u32
    } else {
        CENTRE - (-value * CENTRE as f64).round() as u32
    }
}

/// A seven-bit MIDI 1.0 value as a fraction, by way of 32 bits, so that it
/// is the same fraction a MIDI 2.0 device would have sent.
pub fn unit7(value: u8) -> f64 {
    unit(scale_up((value & 127) as u32, 7, 32))
}

/// A fraction as the nearest seven-bit value.
pub fn to7(value: f64) -> u8 {
    scale_down(from_unit(value), 32, 7) as u8
}

/// A fourteen-bit MIDI 1.0 pitch bend (8192 at rest) as -1 to 1.
pub fn bend14(value: u16) -> f64 {
    bipolar(scale_up((value & 0x3fff) as u32, 14, 32))
}

/// -1 to 1 as a fourteen-bit pitch bend.
pub fn to_bend14(value: f64) -> u16 {
    scale_down(from_bipolar(value), 32, 14) as u16
}

/// A seven-bit velocity as the engine's 0 to 1.
pub fn velocity7(value: u8) -> f32 {
    (scale_up((value & 127) as u32, 7, 16) as f64 / 65535.0) as f32
}

/// A velocity as seven bits. A note that sounds never rounds down to 0,
/// which MIDI 1.0 would read as a note-off.
pub fn to_velocity7(vel: f32) -> u8 {
    let wide = (vel.clamp(0.0, 1.0) as f64 * 65535.0).round() as u32;
    (scale_down(wide, 16, 7) as u8).max(1)
}

/// The group a packet is addressed to, and what it says. `None` for
/// packets that are not channel voice messages (utility, system, data,
/// stream) or that are cut short.
pub fn decode(words: &[u32]) -> Option<(u8, EventKind)> {
    let w0 = *words.first()?;
    let group = ((w0 >> 24) & 15) as u8;
    let head = Head::of(w0);
    let kind = match w0 >> 28 {
        2 => head.midi1()?,
        4 => head.midi2(*words.get(1)?)?,
        _ => return None,
    };
    Some((group, kind))
}

/// The first word of a channel voice message, cut into its fields.
#[derive(Clone, Copy)]
struct Head {
    word: u32,
    status: u32,
    ch: u8,
    /// The third and fourth bytes, seven bits each.
    b3: u8,
    b4: u8,
}

impl Head {
    fn of(word: u32) -> Self {
        Self {
            word,
            status: (word >> 20) & 15,
            ch: ((word >> 16) & 15) as u8,
            b3: ((word >> 8) & 0x7f) as u8,
            b4: (word & 0x7f) as u8,
        }
    }

    /// A MIDI 1.0 channel voice message, in one word.
    fn midi1(self) -> Option<EventKind> {
        let Self { status, ch, b3, b4, .. } = self;
        Some(match status {
            0x8 => EventKind::NoteOff { key: b3, ch },
            0x9 if b4 == 0 => EventKind::NoteOff { key: b3, ch },
            0x9 => EventKind::NoteOn {
                key: b3,
                vel: velocity7(b4),
                ch,
                attr: Attr::NONE,
            },
            0xA => EventKind::NoteControl {
                key: b3,
                ctl: NoteCtl::Pressure,
                value: unit7(b4),
                ch,
            },
            0xB => EventKind::Control {
                ctl: Ctl::Cc(b3),
                value: unit7(b4),
                ch,
            },
            0xC => EventKind::Program {
                program: b3,
                bank: None,
                ch,
            },
            0xD => EventKind::Control {
                ctl: Ctl::Pressure,
                value: unit7(b3),
                ch,
            },
            0xE => EventKind::Control {
                ctl: Ctl::Bend,
                value: bend14(b3 as u16 | (b4 as u16) << 7),
                ch,
            },
            _ => return None,
        })
    }

    /// A MIDI 2.0 channel voice message, in two words: this and `data`.
    fn midi2(self, data: u32) -> Option<EventKind> {
        let Self {
            word: w0,
            status,
            ch,
            b3,
            b4,
        } = self;
        Some(match status {
            0x0 | 0x1 => EventKind::NoteControl {
                key: b3,
                // The index is a whole byte here, not seven bits.
                ctl: if status == 0 {
                    NoteCtl::Registered((w0 & 0xff) as u8)
                } else {
                    NoteCtl::Assignable((w0 & 0xff) as u8)
                },
                value: unit(data),
                ch,
            },
            0x2 => EventKind::Control {
                ctl: Ctl::Registered(b3, b4),
                value: unit(data),
                ch,
            },
            0x3 => EventKind::Control {
                ctl: Ctl::Assignable(b3, b4),
                value: unit(data),
                ch,
            },
            0x6 => EventKind::NoteControl {
                key: b3,
                ctl: NoteCtl::Bend,
                value: bipolar(data),
                ch,
            },
            0x8 => EventKind::NoteOff { key: b3, ch },
            // Unlike MIDI 1.0, a velocity of 0 is still a note-on. The
            // attribute's type is the first word's last byte, its data
            // the second word's lower half.
            0x9 => EventKind::NoteOn {
                key: b3,
                vel: ((data >> 16) as f64 / 65535.0) as f32,
                ch,
                attr: match (w0 & 0xff) as u8 {
                    0 => Attr::NONE,
                    kind => Attr {
                        kind,
                        data: data as u16,
                    },
                },
            },
            0xA => EventKind::NoteControl {
                key: b3,
                ctl: NoteCtl::Pressure,
                value: unit(data),
                ch,
            },
            0xB => EventKind::Control {
                ctl: Ctl::Cc(b3),
                value: unit(data),
                ch,
            },
            0xC => EventKind::Program {
                program: ((data >> 24) & 0x7f) as u8,
                bank: (w0 & 1 != 0)
                    .then_some((((data >> 8) & 0x7f) << 7 | (data & 0x7f)) as u16),
                ch,
            },
            0xD => EventKind::Control {
                ctl: Ctl::Pressure,
                value: unit(data),
                ch,
            },
            0xE => EventKind::Control {
                ctl: Ctl::Bend,
                value: bipolar(data),
                ch,
            },
            // Relative controllers and per-note management carry
            // nothing the engine keeps.
            _ => return None,
        })
    }
}

/// An event as a MIDI 2.0 channel voice message for a group. `None` for
/// "all notes off", which is no single message.
pub fn encode(group: u8, kind: EventKind) -> Option<[u32; 2]> {
    let head = |status: u32, ch: u8, b3: u32, b4: u32| {
        4 << 28
            | ((group & 15) as u32) << 24
            | status << 20
            | ((ch & 15) as u32) << 16
            | b3 << 8
            | b4
    };
    let key7 = |key: u8| (key & 127) as u32;
    Some(match kind {
        EventKind::NoteOn { key, vel, ch, attr } => [
            head(0x9, ch, key7(key), attr.kind as u32),
            ((vel.clamp(0.0, 1.0) as f64 * 65535.0).round() as u32) << 16
                | if attr.is_none() { 0 } else { attr.data as u32 },
        ],
        EventKind::NoteOff { key, ch } => [head(0x8, ch, key7(key), 0), 0],
        EventKind::Control { ctl, value, ch } => match ctl {
            Ctl::Cc(index) => [head(0xB, ch, (index & 127) as u32, 0), from_unit(value)],
            Ctl::Bend => [head(0xE, ch, 0, 0), from_bipolar(value)],
            Ctl::Pressure => [head(0xD, ch, 0, 0), from_unit(value)],
            Ctl::Registered(bank, index) => [
                head(0x2, ch, (bank & 127) as u32, (index & 127) as u32),
                from_unit(value),
            ],
            Ctl::Assignable(bank, index) => [
                head(0x3, ch, (bank & 127) as u32, (index & 127) as u32),
                from_unit(value),
            ],
        },
        EventKind::NoteControl {
            key,
            ctl,
            value,
            ch,
        } => match ctl {
            NoteCtl::Bend => [head(0x6, ch, key7(key), 0), from_bipolar(value)],
            NoteCtl::Pressure => [head(0xA, ch, key7(key), 0), from_unit(value)],
            NoteCtl::Registered(index) => {
                [head(0x0, ch, key7(key), index as u32), from_unit(value)]
            }
            NoteCtl::Assignable(index) => {
                [head(0x1, ch, key7(key), index as u32), from_unit(value)]
            }
        },
        EventKind::Program { program, bank, ch } => [
            head(0xC, ch, 0, bank.is_some() as u32),
            ((program & 127) as u32) << 24
                | bank.map_or(0, |b| ((b as u32 >> 7) & 0x7f) << 8 | (b as u32 & 0x7f)),
        ],
        EventKind::AllNotesOff => return None,
    })
}

/// An event as MIDI 1.0 messages of up to three bytes, for what only
/// speaks that: `emit` gets each message and how many of its bytes count.
/// A registered or assignable controller becomes the four control changes
/// of an RPN or NRPN; a note's own pitch bend and per-note controllers have
/// no MIDI 1.0 form and are left out.
pub fn midi1(kind: EventKind, mut emit: impl FnMut([u8; 3], u32)) {
    match kind {
        // MIDI 1.0 has no place for the attribute.
        EventKind::NoteOn { key, vel, ch, .. } => {
            emit([0x90 | (ch & 15), key & 127, to_velocity7(vel)], 3)
        }
        EventKind::NoteOff { key, ch } => emit([0x80 | (ch & 15), key & 127, 0], 3),
        EventKind::Control { ctl, value, ch } => {
            let ch = ch & 15;
            match ctl {
                Ctl::Cc(index) => emit([0xB0 | ch, index & 127, to7(value)], 3),
                Ctl::Bend => {
                    let bend = to_bend14(value);
                    emit([0xE0 | ch, (bend & 127) as u8, (bend >> 7) as u8], 3)
                }
                Ctl::Pressure => emit([0xD0 | ch, to7(value), 0], 2),
                Ctl::Registered(bank, index) | Ctl::Assignable(bank, index) => {
                    let (msb, lsb) = match ctl {
                        Ctl::Registered(..) => (101, 100),
                        _ => (99, 98),
                    };
                    let wide = scale_down(from_unit(value), 32, 14);
                    emit([0xB0 | ch, msb, bank & 127], 3);
                    emit([0xB0 | ch, lsb, index & 127], 3);
                    emit([0xB0 | ch, 6, (wide >> 7) as u8], 3);
                    emit([0xB0 | ch, 38, (wide & 127) as u8], 3);
                }
            }
        }
        EventKind::NoteControl {
            key,
            ctl: NoteCtl::Pressure,
            value,
            ch,
        } => emit([0xA0 | (ch & 15), key & 127, to7(value)], 3),
        EventKind::Program { program, bank, ch } => {
            let ch = ch & 15;
            if let Some(bank) = bank {
                emit([0xB0 | ch, 0, ((bank >> 7) & 127) as u8], 3);
                emit([0xB0 | ch, 32, (bank & 127) as u8], 3);
            }
            emit([0xC0 | ch, program & 127, 0], 2);
        }
        // MIDI 1.0 has no form for the other note controls, and "all notes
        // off" goes out as the note-offs of the held notes.
        EventKind::NoteControl { .. } | EventKind::AllNotesOff => {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scaling_keeps_the_ends_and_the_centre() {
        // The examples of the specification's translation rules.
        assert_eq!(scale_up(0, 7, 32), 0);
        assert_eq!(scale_up(64, 7, 32), 0x8000_0000);
        assert_eq!(scale_up(127, 7, 32), 0xffff_ffff);
        assert_eq!(scale_up(0x2000, 14, 32), 0x8000_0000);
        assert_eq!(scale_up(0x3fff, 14, 32), 0xffff_ffff);
        assert_eq!(scale_up(127, 7, 16), 0xffff);
        assert_eq!(scale_up(64, 7, 16), 0x8000);
        assert_eq!(scale_up(1, 7, 16), 0x0200);
        // Every seven-bit value survives the trip up and back.
        for v in 0..128u32 {
            assert_eq!(scale_down(scale_up(v, 7, 32), 32, 7), v);
            assert_eq!(to7(unit7(v as u8)), v as u8);
        }
        for v in [0u16, 1, 8191, 8192, 8193, 16383] {
            assert_eq!(to_bend14(bend14(v)), v);
        }
        assert_eq!(bend14(8192), 0.0);
        assert_eq!(bend14(16383), 1.0);
        assert_eq!(bend14(0), -1.0);
        assert_eq!(unit7(127), 1.0);
        assert_eq!(to_velocity7(velocity7(100)), 100);
        assert_eq!(to_velocity7(0.0001), 1);
    }

    #[test]
    #[expect(clippy::too_many_lines, reason = "one test of a long scenario, read from top to bottom")]
    fn midi_2_messages_round_trip_at_full_resolution() {
        let events = [
            EventKind::NoteOn {
                key: 60,
                vel: 0.5,
                ch: 3,
                attr: Attr::NONE,
            },
            EventKind::NoteOn {
                key: 62,
                vel: 0.25,
                ch: 3,
                attr: Attr {
                    kind: 0x11,
                    data: 0xA000,
                },
            },
            EventKind::NoteOff { key: 60, ch: 3 },
            EventKind::Control {
                ctl: Ctl::Cc(74),
                value: 0.123456789,
                ch: 0,
            },
            EventKind::Control {
                ctl: Ctl::Bend,
                value: -0.25,
                ch: 15,
            },
            EventKind::Control {
                ctl: Ctl::Pressure,
                value: 1.0,
                ch: 1,
            },
            EventKind::Control {
                ctl: Ctl::Registered(0, 6),
                value: 0.75,
                ch: 2,
            },
            EventKind::Control {
                ctl: Ctl::Assignable(5, 99),
                value: 0.01,
                ch: 2,
            },
            EventKind::NoteControl {
                key: 61,
                ctl: NoteCtl::Bend,
                value: 0.5,
                ch: 0,
            },
            EventKind::NoteControl {
                key: 61,
                ctl: NoteCtl::Pressure,
                value: 0.3,
                ch: 0,
            },
            EventKind::NoteControl {
                key: 61,
                ctl: NoteCtl::Registered(74),
                value: 0.9,
                ch: 0,
            },
            EventKind::NoteControl {
                key: 61,
                ctl: NoteCtl::Assignable(200),
                value: 0.2,
                ch: 0,
            },
            EventKind::Program {
                program: 12,
                bank: Some(0x0102),
                ch: 9,
            },
            EventKind::Program {
                program: 12,
                bank: None,
                ch: 9,
            },
        ];
        for event in events {
            let words = encode(5, event).unwrap();
            assert_eq!(words[0] >> 28, 4, "a MIDI 2.0 channel voice message");
            let (group, back) = decode(&words).unwrap();
            assert_eq!(group, 5);
            match (event, back) {
                (
                    EventKind::Control {
                        ctl: a,
                        value: x,
                        ch: c,
                    },
                    EventKind::Control {
                        ctl: b,
                        value: y,
                        ch: d,
                    },
                ) => {
                    assert_eq!((a, c), (b, d));
                    // To within a step of 32 bits: far finer than seven.
                    assert!((x - y).abs() < 1e-9, "{x} came back as {y}");
                }
                (
                    EventKind::NoteControl {
                        key: k,
                        ctl: a,
                        value: x,
                        ch: c,
                    },
                    EventKind::NoteControl {
                        key: l,
                        ctl: b,
                        value: y,
                        ch: d,
                    },
                ) => {
                    assert_eq!((k, a, c), (l, b, d));
                    assert!((x - y).abs() < 1e-9);
                }
                (
                    EventKind::NoteOn {
                        key: k,
                        vel: x,
                        ch: c,
                        attr: a,
                    },
                    EventKind::NoteOn {
                        key: l,
                        vel: y,
                        ch: d,
                        attr: b,
                    },
                ) => {
                    assert_eq!((k, c, a), (l, d, b));
                    assert!((x - y).abs() < 1e-4);
                }
                (a, b) => assert_eq!(a, b),
            }
        }
        assert_eq!(encode(0, EventKind::AllNotesOff), None);
    }

    #[test]
    fn known_packets_decode() {
        // Note on, group 0, channel 0, middle C, velocity 0xC000.
        assert_eq!(
            decode(&[0x4090_3c00, 0xc000_0000]),
            Some((
                0,
                EventKind::NoteOn {
                    key: 60,
                    vel: (0xc000 as f64 / 65535.0) as f32,
                    ch: 0,
                    attr: Attr::NONE,
                }
            ))
        );
        // The same with an articulation of M2-123: type 0x11 (staccatos
        // and shorts), data 0xA000 (subclass A, pizzicato).
        assert_eq!(
            decode(&[0x4090_3c11, 0xc000_a000]),
            Some((
                0,
                EventKind::NoteOn {
                    key: 60,
                    vel: (0xc000 as f64 / 65535.0) as f32,
                    ch: 0,
                    attr: Attr {
                        kind: 0x11,
                        data: 0xa000
                    },
                }
            ))
        );
        assert_eq!(
            encode(
                0,
                EventKind::NoteOn {
                    key: 60,
                    vel: 1.0,
                    ch: 0,
                    attr: Attr {
                        kind: 0x11,
                        data: 0xa000
                    },
                }
            ),
            Some([0x4090_3c11, 0xffff_a000])
        );
        // The same note from a MIDI 1.0 device: one word, velocity 96.
        let Some((
            _,
            EventKind::NoteOn {
                key: 60,
                vel,
                ch: 0,
                ..
            },
        )) = decode(&[0x2090_3c60])
        else {
            panic!("not a note on");
        };
        assert!((vel - 0xc104 as f32 / 65535.0).abs() < 1e-6);
        // A MIDI 1.0 note on with no velocity is a note off; in MIDI 2.0 it is not.
        assert_eq!(
            decode(&[0x2090_3c00]),
            Some((0, EventKind::NoteOff { key: 60, ch: 0 }))
        );
        assert!(matches!(
            decode(&[0x4090_3c00, 0]),
            Some((_, EventKind::NoteOn { .. }))
        ));
        // Per-note pitch bend at rest, on group 2, channel 1, note 64.
        assert_eq!(
            decode(&[0x4261_4000, 0x8000_0000]),
            Some((
                2,
                EventKind::NoteControl {
                    key: 64,
                    ctl: NoteCtl::Bend,
                    value: 0.0,
                    ch: 1
                }
            ))
        );
        // Pitch wheel centred, from a MIDI 1.0 device.
        assert_eq!(
            decode(&[0x20e0_0040]),
            Some((
                0,
                EventKind::Control {
                    ctl: Ctl::Bend,
                    value: 0.0,
                    ch: 0
                }
            ))
        );
        // What is not a channel voice message, and a packet cut short.
        assert_eq!(decode(&[0x1000_0000]), None);
        assert_eq!(decode(&[0x4090_3c00]), None);
        assert_eq!(decode(&[]), None);
    }

    #[test]
    fn events_become_midi_1_messages() {
        let all = |kind| {
            let mut out = Vec::new();
            midi1(kind, |bytes, len| out.push(bytes[..len as usize].to_vec()));
            out
        };
        assert_eq!(
            all(EventKind::Control {
                ctl: Ctl::Bend,
                value: 0.0,
                ch: 2
            }),
            vec![vec![0xE2, 0x00, 0x40]]
        );
        assert_eq!(
            all(EventKind::Control {
                ctl: Ctl::Pressure,
                value: 1.0,
                ch: 0
            }),
            vec![vec![0xD0, 127]]
        );
        assert_eq!(
            all(EventKind::Control {
                ctl: Ctl::Registered(0, 0),
                value: 0.5,
                ch: 0
            }),
            vec![
                vec![0xB0, 101, 0],
                vec![0xB0, 100, 0],
                vec![0xB0, 6, 64],
                vec![0xB0, 38, 0]
            ]
        );
        assert_eq!(
            all(EventKind::Program {
                program: 5,
                bank: Some(0x0081),
                ch: 1
            }),
            vec![vec![0xB1, 0, 1], vec![0xB1, 32, 1], vec![0xC1, 5]]
        );
        assert_eq!(
            all(EventKind::NoteControl {
                key: 60,
                ctl: NoteCtl::Pressure,
                value: 1.0,
                ch: 0
            }),
            vec![vec![0xA0, 60, 127]]
        );
        assert!(
            all(EventKind::NoteControl {
                key: 60,
                ctl: NoteCtl::Bend,
                value: 1.0,
                ch: 0
            })
            .is_empty()
        );
    }
}
