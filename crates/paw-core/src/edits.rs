//! The edit list of an audio clip: changes to its sound that leave its file
//! as it is.
//!
//! The cheap changes are the clip's own settings, which the engine applies
//! as it plays: where it starts in the file and how long it is (a cut), its
//! gain, its fades, its stretch and shift. The others are kept as a list,
//! in order ([`AudioEdit`]): play backwards, a gain on a part of the file,
//! samples drawn over the file's (a pencil fix). The clip then plays a
//! version of its file made with them, on a worker thread, as a stretched
//! clip does (`stretched.rs`), and kept in the disk store when it is large.
//! The version is made again from the file and the list when it is not
//! there, so deleting the store loses nothing.

use paw_engine::AudioData;
use serde::{Deserialize, Serialize};

/// One change in an audio clip's edit list. Times are seconds of the sound
/// as the edits before it left it, which is the file's time for all but
/// what comes after a `reverse`.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum AudioEdit {
    /// The whole sound backwards.
    Reverse,
    /// A gain in dB from `from` to `to` seconds.
    Gain { from: f64, to: f64, db: f64 },
    /// Samples drawn over the sound's from `at` seconds, in one channel (0
    /// or 1), or in both when `channel` is not given.
    Pencil {
        at: f64,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        channel: Option<u8>,
        values: Vec<f32>,
    },
}

/// What a list asks of the samples, checked: an error says which edit
/// cannot be made.
pub(crate) fn check(edits: &[AudioEdit]) -> anyhow::Result<()> {
    for edit in edits {
        match edit {
            AudioEdit::Reverse => {}
            AudioEdit::Gain { from, to, db } => {
                if !(from.is_finite() && to.is_finite() && db.is_finite()) || from > to || *from < 0.0 {
                    anyhow::bail!("a gain edit needs 0 <= from <= to and a gain in dB");
                }
            }
            AudioEdit::Pencil { at, channel, values } => {
                if !at.is_finite() || *at < 0.0 || channel.is_some_and(|c| c > 1) {
                    anyhow::bail!("a pencil edit needs a time at or after 0 and channel 0 or 1");
                }
                if values.iter().any(|v| !v.is_finite()) {
                    anyhow::bail!("a pencil edit's samples are numbers");
                }
            }
        }
    }
    Ok(())
}

/// The sound with the edits made, in order. The length stays the same.
pub(crate) fn apply(data: &AudioData, edits: &[AudioEdit]) -> AudioData {
    let rate = data.sample_rate as f64;
    let mut channels = [data.channels[0].to_vec(), data.channels[1].to_vec()];
    let frames = channels[0].len();
    let at = |seconds: f64| ((seconds * rate).round().max(0.0) as usize).min(frames);
    for edit in edits {
        match edit {
            AudioEdit::Reverse => {
                for channel in &mut channels {
                    channel.reverse();
                }
            }
            AudioEdit::Gain { from, to, db } => {
                let factor = paw_engine::db_to_gain(*db);
                for channel in &mut channels {
                    for s in &mut channel[at(*from)..at(*to)] {
                        *s *= factor;
                    }
                }
            }
            AudioEdit::Pencil { at: start, channel, values } => {
                let from = at(*start);
                for (c, samples) in channels.iter_mut().enumerate() {
                    if channel.is_some_and(|only| only as usize != c) {
                        continue;
                    }
                    for (s, v) in samples[from..].iter_mut().zip(values) {
                        *s = *v;
                    }
                }
            }
        }
    }
    let [left, right] = channels;
    AudioData {
        sample_rate: data.sample_rate,
        channels: [left.into(), right.into()],
    }
}

/// A short text that tells one list from another, for the name a version
/// is kept under.
pub(crate) fn text(edits: &[AudioEdit]) -> String {
    serde_json::to_string(edits).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sound(n: usize) -> AudioData {
        let left: Vec<f32> = (0..n).map(|i| i as f32 / n as f32).collect();
        let right: Vec<f32> = left.iter().map(|s| -s).collect();
        AudioData { sample_rate: 10, channels: [left.into(), right.into()] }
    }

    #[test]
    fn edits_are_made_in_order_and_keep_the_length() {
        let data = sound(10);
        let out = apply(
            &data,
            &[
                AudioEdit::Reverse,
                AudioEdit::Gain { from: 0.0, to: 0.2, db: -120.0 },
                AudioEdit::Pencil { at: 0.5, channel: Some(1), values: vec![0.25, 0.5] },
            ],
        );
        assert_eq!(out.frames(), 10);
        assert!(out.channels[0][0].abs() < 1e-5, "the gain after the reverse silences its start");
        assert_eq!(out.channels[0][2], 0.7, "reversed");
        assert_eq!(&out.channels[1][5..7], &[0.25, 0.5], "drawn in the right channel");
        assert_eq!(out.channels[0][5], 0.4, "and not in the left");
        assert_eq!(apply(&out, &[]).channels[0][..], out.channels[0][..], "no edits, the same sound");
    }

    #[test]
    fn a_list_that_cannot_be_made_says_which_edit() {
        assert!(check(&[AudioEdit::Gain { from: 2.0, to: 1.0, db: 0.0 }]).is_err());
        assert!(check(&[AudioEdit::Pencil { at: 0.0, channel: Some(2), values: vec![] }]).is_err());
        assert!(check(&[AudioEdit::Reverse]).is_ok());
    }
}
