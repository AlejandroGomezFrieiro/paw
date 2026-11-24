//! What a sound file's header says, without decoding it: for lists of files.

use std::fs::File;
use std::path::Path;

use anyhow::{Context, Result, bail};
use symphonia::core::formats::probe::Hint;
use symphonia::core::formats::{FormatOptions, TrackType};
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;

/// The format of a sound file.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Probe {
    pub sample_rate: u32,
    pub channels: u32,
    /// Its length in seconds, when the header says (an MP3 without a length
    /// in its header does not).
    pub seconds: Option<f64>,
}

/// Read the header of a WAV, AIFF, FLAC, MP3 or Ogg Vorbis file.
pub fn probe(path: &Path) -> Result<Probe> {
    let file = File::open(path).with_context(|| format!("opening {}", path.display()))?;
    let stream = MediaSourceStream::new(Box::new(file), Default::default());
    let mut hint = Hint::new();
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }
    let format = symphonia::default::get_probe()
        .probe(
            &hint,
            stream,
            FormatOptions::default(),
            MetadataOptions::default(),
        )
        .map_err(|_| anyhow::anyhow!("{} is not a sound file that can be read", path.display()))?;
    let Some(stream) = format.default_track(TrackType::Audio) else {
        bail!("{} holds no audio", path.display());
    };
    let Some(params) = stream.codec_params.as_ref().and_then(|p| p.audio()) else {
        bail!("{} holds no audio", path.display());
    };
    let sample_rate = params.sample_rate.unwrap_or(0);
    if sample_rate == 0 {
        bail!("{} does not say what its sample rate is", path.display());
    }
    Ok(Probe {
        sample_rate,
        channels: params.channels.as_ref().map_or(0, |c| c.count() as u32),
        seconds: stream.num_frames.map(|n| n as f64 / sample_rate as f64),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture(name: &str) -> std::path::PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../tests/fixtures")
            .join(name)
    }

    #[test]
    fn a_header_says_rate_channels_and_length() {
        let wav = probe(&fixture("tone-mono-8k.wav")).unwrap();
        assert_eq!((wav.sample_rate, wav.channels), (8000, 1));
        assert!(wav.seconds.unwrap() > 0.0);
        let flac = probe(&fixture("tone-stereo-11k.flac")).unwrap();
        assert_eq!((flac.sample_rate, flac.channels), (11025, 2));
    }

    #[test]
    fn a_file_that_is_not_sound_is_an_error() {
        assert!(probe(&fixture("demo-song.json")).is_err());
        assert!(probe(&fixture("no-such-file.wav")).is_err());
    }
}
