//! Property tests of the `.midi2` clip file: a clip written and read again.

use proptest::collection::{btree_map, vec};
use proptest::prelude::*;
use serde_json::{Map, Value, json};

use super::{Clip, TPQ, decode, encode};
use crate::model::{Control, ControlKind, Note, NoteAttr};
use crate::props::config;

/// The ticks of a beat, as the files hold them.
const BEAT: i64 = TPQ as i64;

/// A note's `meta`: a lyric or a tag, in any script.
fn meta() -> impl Strategy<Value = Map<String, Value>> {
    btree_map("[a-z]{1,6}", "\\PC{0,8}", 0..3)
        .prop_map(|map| map.into_iter().map(|(key, text)| (key, Value::String(text))).collect())
}

/// No attribute, or one of any type and data.
fn attr() -> impl Strategy<Value = Option<NoteAttr>> {
    prop::option::of((1u8..=255, any::<u16>()).prop_map(|(kind, data)| NoteAttr { kind, data }))
}

/// A note that starts and ends on a tick, as `(start, end, note)` in ticks:
/// a file holds it exactly.
fn note_on_ticks() -> impl Strategy<Value = (i64, i64, Note)> {
    (-2 * BEAT..64 * BEAT, 1..8 * BEAT, 0u8..=127, 1u8..=127, meta(), attr()).prop_map(
        |(start, length, pitch, velocity, meta, attr)| {
            let note = Note {
                start: start as f64 / BEAT as f64,
                length: length as f64 / BEAT as f64,
                pitch,
                velocity: crate::model::Velocity(velocity),
                meta,
                id: 0,
                attr,
            };
            (start, start + length, note)
        },
    )
}

/// Any note of a clip: times between ticks, a length of 0, any velocity
/// and id.
fn note() -> impl Strategy<Value = Note> {
    let id = prop_oneof![0u64..4, any::<u64>()];
    (-8.0..64.0f64, 0.0..8.0f64, 0u8..=127, any::<u8>(), meta(), id, attr()).prop_map(
        |(start, length, pitch, velocity, meta, id, attr)| Note { start, length, pitch, velocity: crate::model::Velocity(velocity), meta, id, attr },
    )
}

/// Any controller move that can be played (`Control::problem` is `None`).
fn control() -> impl Strategy<Value = Control> {
    let what = prop_oneof![
        (0u8..=127).prop_map(|number| ControlKind::Cc { number }),
        Just(ControlKind::Bend),
        Just(ControlKind::Pressure),
        (0u8..=127, 0u8..=127).prop_map(|(bank, index)| ControlKind::Registered { bank, index }),
        (0u8..=127, 0u8..=127).prop_map(|(bank, index)| ControlKind::Assignable { bank, index }),
        (0u8..=127, prop::option::of(0u16..=0x3fff)).prop_map(|(program, bank)| ControlKind::Program { program, bank }),
    ];
    (-8.0..64.0f64, what, 0.0..=1.0f64, -1.0..=1.0f64, prop::option::of(0u8..=127)).prop_map(
        |(start, what, unit, bipolar, key)| {
            let value = if what == ControlKind::Bend { bipolar } else { unit };
            // A program change belongs to a channel, not to a note.
            let key = key.filter(|_| !matches!(what, ControlKind::Program { .. }));
            Control { start, what, value, key }
        },
    )
}

proptest! {
    #![proptest_config(config())]

    /// Notes on ticks come back as they were written: their times, keys,
    /// velocities, attributes, `meta` and ids, in their order.
    #[test]
    fn a_clip_on_ticks_comes_back_the_same(
        mut notes in vec(note_on_ticks(), 0..48),
        past_the_end in 0..4 * BEAT,
    ) {
        // A clip keeps its notes in the order they start, with the ids 1,
        // 2, 3 that the session gives them.
        notes.sort_by_key(|(start, ..)| *start);
        let end = notes.iter().map(|(_, end, _)| *end).max().unwrap_or(0).max(0) + past_the_end;
        let notes: Vec<Note> = notes
            .into_iter()
            .enumerate()
            .map(|(i, (.., note))| Note { id: i as u64 + 1, ..note })
            .collect();
        let length = end as f64 / BEAT as f64;

        let clip = decode(&encode(&notes, &[], length).expect("paw writes the clip")).expect("paw reads the clip that it wrote");

        prop_assert_eq!(clip, Clip { notes, controls: Vec::new(), length, skipped: Vec::new() });
    }

    /// A clip file that is read and written again gives the same bytes:
    /// a save of a project does not change its clips (and `git diff` shows
    /// nothing).
    #[test]
    fn a_clip_file_read_and_written_again_is_the_same_bytes(
        mut notes in vec(note(), 0..32),
        controls in vec(control(), 0..16),
        length in 0.0..72.0f64,
    ) {
        notes.sort_by(|a, b| a.start.total_cmp(&b.start));
        let bytes = encode(&notes, &controls, length).expect("paw writes the clip");

        let clip = decode(&bytes).expect("paw reads the clip that it wrote");

        prop_assert_eq!(encode(&clip.notes, &clip.controls, clip.length).expect("paw writes the clip again"), bytes);
    }
}

/// The reader once took each byte of a `paw:` text as one character, so a
/// lyric in UTF-8 that is not ASCII came back as other characters.
#[test]
fn a_lyric_that_is_not_ascii_comes_back() {
    let mut meta = Map::new();
    meta.insert("lyric".into(), json!("さくら ñ"));
    let note = Note { start: 0.0, length: 1.0, pitch: 60, velocity: crate::model::Velocity(100), meta, id: 1, attr: None };

    let clip = decode(&encode([&note], &[], 1.0).expect("paw writes the clip")).expect("paw reads the clip that it wrote");

    assert_eq!(clip.notes[0].meta["lyric"], "さくら ñ");
}
