//! The range of times that a clip holds (TASK-173): a note at the edge of
//! the range writes and reads back, and a time past it is an error, not
//! billions of clockstamps or an overflow of ticks.

use serde_json::{Map, json};

use super::*;
use crate::model::MAX_BEATS;

fn note(start: f64, length: f64) -> Note {
    Note {
        start,
        length,
        pitch: 60,
        velocity: 100,
        meta: Map::new(),
        id: 0,
        attr: None,
    }
}

fn bend(start: f64) -> Control {
    Control {
        start,
        what: ControlKind::Bend,
        value: 0.0,
        key: None,
    }
}

/// The message of the error that writing gives.
fn refused(notes: &[Note], controls: &[Control], length: f64) -> String {
    let Err(error) = encode(notes, controls, length) else {
        panic!("a clip with a far time was written");
    };
    error.to_string()
}

#[test]
fn notes_at_the_edges_of_the_range_write_and_read_back() {
    let notes = [note(-MAX_BEATS, 1.0), note(MAX_BEATS - 1.0, 1.0)];

    let bytes = encode(&notes, &[], MAX_BEATS).expect("the edges are in range");
    let clip = decode(&bytes).expect("paw reads the clip that it wrote");

    let starts: Vec<f64> = clip.notes.iter().map(|n| n.start).collect();
    assert_eq!(starts, [-1_000_000.0, 999_999.0]);
    assert_eq!(clip.length, 1_000_000.0);
    // Two million beats of gaps take about 117 000 clockstamps.
    assert!(bytes.len() < 1 << 20, "{} bytes", bytes.len());
}

#[test]
fn a_time_past_the_range_is_refused_with_a_message() {
    let far = 1e15;

    assert_eq!(
        refused(&[note(far, 1.0)], &[], 4.0),
        "a note is at beat 1000000000000000, too far for a clip: \
         a clip holds times up to a million beats from its start"
    );
    let cases = [
        (
            refused(&[note(-far, 1.0)], &[], 4.0),
            "a note is at beat -1000000000000000,",
        ),
        (
            refused(&[note(f64::NAN, 1.0)], &[], 4.0),
            "a note is at beat NaN,",
        ),
        (
            refused(&[note(0.0, far)], &[], 4.0),
            "the end of a note is at beat 1000000000000000,",
        ),
        (
            refused(&[], &[bend(far)], 4.0),
            "a controller move is at beat 1000000000000000,",
        ),
        (
            refused(&[], &[], far),
            "the end of the clip is at beat 1000000000000000,",
        ),
    ];
    for (message, start) in cases {
        assert!(message.starts_with(start), "{message}");
    }
}

#[test]
fn a_file_with_its_origin_at_the_smallest_tick_is_refused() {
    // One tick to a beat, the origin at the smallest tick, and one note.
    let mut words = vec![utility(0x4, 0), utility(0x3, 1), utility(0x4, 0)];
    flex_text(
        &mut words,
        &format!("paw:{}", json!({ "origin": i64::MIN })),
    );
    words.push(utility(0x4, 0));
    words.extend(stream(0x20));
    words.extend([utility(0x4, 0), 0x2090_3C64, utility(0x4, 1), 0x2080_3C00]);
    words.push(utility(0x4, 0));
    words.extend(stream(0x21));
    let mut bytes = MAGIC.to_vec();
    for w in words {
        bytes.extend_from_slice(&w.to_be_bytes());
    }

    let Err(error) = decode(&bytes) else {
        panic!("a clip with a far origin was read");
    };

    let message = error.to_string();
    assert!(
        message.starts_with("a note is at beat -9223372036854776000,"),
        "{message}"
    );
}
