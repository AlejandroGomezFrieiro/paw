//! Controls of MIDI input that tracks do not get.
//!
//! A script can take some keys, pads or pedals of a controller for itself:
//! step input binds a pad to "rest", for example. What such a control sends
//! must not sound on a track, and must not be recorded. The main thread
//! makes a [`MidiFilter`] of those controls and sends it to the engine,
//! which swaps it in between blocks and reads it for each message of MIDI
//! input: a short list, read in place, with no lock and no allocation.
//! Scripts still hear every message (the `midi.in` event).

use paw_types::{Ctl, EventKind};

/// What a [`Rule`] takes of a port and channel.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Control {
    /// A key: its note on, note off and the controllers of that note.
    Note(u8),
    /// A control change by number (64 is the sustain pedal).
    Cc(u8),
}

/// One control of MIDI input that tracks do not get.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Rule {
    /// The port's key ([`crate::midi::port_key`]), or 0 for every port.
    pub port: u32,
    /// The channel from 1 to 16, or 0 for every channel.
    pub channel: u8,
    pub control: Control,
}

impl Rule {
    /// Whether a message from MIDI input on `port` is this control.
    pub fn matches(&self, port: u32, kind: &EventKind) -> bool {
        if self.port != 0 && self.port != port {
            return false;
        }
        if self.channel != 0 && kind.channel().is_none_or(|ch| ch + 1 != self.channel) {
            return false;
        }
        match (self.control, *kind) {
            (
                Control::Note(note),
                EventKind::NoteOn { key, .. }
                | EventKind::NoteOff { key, .. }
                | EventKind::NoteControl { key, .. },
            ) => key == note,
            (
                Control::Cc(number),
                EventKind::Control {
                    ctl: Ctl::Cc(cc), ..
                },
            ) => cc == number,
            _ => false,
        }
    }
}

/// The controls of MIDI input that tracks do not get. Empty by default.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct MidiFilter {
    rules: Box<[Rule]>,
}

impl MidiFilter {
    /// The most rules a filter holds, so that each message is checked
    /// against a short list on the audio thread.
    pub const MAX_RULES: usize = 256;

    pub fn is_empty(&self) -> bool {
        self.rules.is_empty()
    }

    pub fn rules(&self) -> &[Rule] {
        &self.rules
    }

    /// Whether tracks do not get this message from MIDI input on `port`.
    pub fn matches(&self, port: u32, kind: &EventKind) -> bool {
        self.rules.iter().any(|rule| rule.matches(port, kind))
    }
}

/// A filter would hold more than [`MidiFilter::MAX_RULES`] rules.
#[derive(Clone, Copy, Debug, PartialEq, Eq, thiserror::Error)]
#[error("the MIDI input filter holds at most {max} controls, not {0}", max = MidiFilter::MAX_RULES)]
pub struct TooManyRules(pub usize);

impl TryFrom<Vec<Rule>> for MidiFilter {
    type Error = TooManyRules;

    fn try_from(rules: Vec<Rule>) -> Result<Self, TooManyRules> {
        if rules.len() > Self::MAX_RULES {
            return Err(TooManyRules(rules.len()));
        }
        Ok(Self {
            rules: rules.into_boxed_slice(),
        })
    }
}

#[cfg(test)]
mod tests {

    use paw_types::{Attr, NoteCtl};

    use super::*;

    fn on(key: u8, ch: u8) -> EventKind {
        EventKind::NoteOn {
            key,
            vel: 0.5,
            ch,
            attr: Attr::NONE,
        }
    }

    #[test]
    fn a_rule_takes_its_control_on_its_port_and_channel_only() {
        let pad = Rule {
            port: 7,
            channel: 10,
            control: Control::Note(36),
        };
        assert!(pad.matches(7, &on(36, 9)));
        assert!(pad.matches(7, &EventKind::NoteOff { key: 36, ch: 9 }));
        let pressure = EventKind::NoteControl {
            key: 36,
            ctl: NoteCtl::Pressure,
            value: 0.5,
            ch: 9,
        };
        assert!(pad.matches(7, &pressure));
        assert!(!pad.matches(8, &on(36, 9)), "another port");
        assert!(!pad.matches(7, &on(36, 0)), "another channel");
        assert!(!pad.matches(7, &on(37, 9)), "another key");

        let pedal = Rule {
            port: 0,
            channel: 0,
            control: Control::Cc(64),
        };
        let cc = |number, ch| EventKind::Control {
            ctl: Ctl::Cc(number),
            value: 1.0,
            ch,
        };
        assert!(pedal.matches(3, &cc(64, 0)) && pedal.matches(9, &cc(64, 15)));
        assert!(!pedal.matches(3, &cc(1, 0)));
        assert!(!pedal.matches(3, &on(64, 0)), "a key is not a controller");
    }
}
