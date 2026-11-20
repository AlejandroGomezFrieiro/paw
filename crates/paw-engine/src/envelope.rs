//! The levels of a sound file, decoded as it is read: the loudest sample of
//! each channel and of each frame, for what looks for peaks and onsets
//! (`paw.api.sound_envelope`).

use std::fs::File;
use std::path::Path;

use anyhow::{Context, Result, bail};
use symphonia::core::codecs::audio::AudioDecoderOptions;
use symphonia::core::errors::Error;
use symphonia::core::formats::probe::Hint;
use symphonia::core::formats::{FormatOptions, TrackType};
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;

/// The levels of a sound file, as linear gain.
#[derive(Clone, Debug, Default)]
pub struct Envelope {
    pub sample_rate: u32,
    /// The channels of the file, all of them (not made stereo).
    pub channels: usize,
    /// The loudest sample of each channel.
    pub peaks: Vec<f32>,
    /// The loudest sample of each frame, over its channels.
    pub frames: Vec<f32>,
}

impl Envelope {
    /// The first frame at `from` or later where a channel is louder than
    /// `level`.
    pub fn onset(&self, level: f32, from: usize) -> Option<usize> {
        self.frames
            .get(from..)?
            .iter()
            .position(|v| *v > level)
            .map(|i| i + from)
    }

    /// The loudest sample of each block of `per` frames in `from..to`; the
    /// last block can be shorter.
    pub fn blocks(&self, from: usize, to: usize, per: usize) -> Vec<f32> {
        let to = to.min(self.frames.len());
        if from >= to {
            return Vec::new();
        }
        self.frames[from..to]
            .chunks(per.max(1))
            .map(|c| c.iter().copied().fold(0.0, f32::max))
            .collect()
    }
}

/// Decode a WAV, AIFF, FLAC, MP3 or Ogg Vorbis file and take its levels.
pub fn envelope(path: &Path) -> Result<Envelope> {
    let name = path.display();
    let file = File::open(path).with_context(|| format!("opening {name}"))?;
    let stream = MediaSourceStream::new(Box::new(file), Default::default());
    let mut hint = Hint::new();
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }
    let mut format = symphonia::default::get_probe()
        .probe(&hint, stream, FormatOptions::default(), MetadataOptions::default())
        .map_err(|_| anyhow::anyhow!("{name} is not a sound file that can be read"))?;
    let Some(track) = format.default_track(TrackType::Audio) else {
        bail!("{name} holds no audio");
    };
    let Some(params) = track.codec_params.as_ref().and_then(|p| p.audio()) else {
        bail!("{name} holds no audio");
    };
    let track_id = track.id;
    let mut out = Envelope {
        sample_rate: params.sample_rate.unwrap_or(0),
        channels: params.channels.as_ref().map_or(0, |c| c.count()),
        ..Envelope::default()
    };
    if let Some(n) = track.num_frames {
        out.frames.reserve(n as usize);
    }
    let mut decoder = symphonia::default::get_codecs()
        .make_audio_decoder(params, &AudioDecoderOptions::default())
        .map_err(|e| anyhow::anyhow!("{name} cannot be decoded: {e}"))?;
    let mut planes: Vec<Vec<f32>> = Vec::new();
    loop {
        let packet = match format.next_packet() {
            Ok(Some(packet)) => packet,
            Ok(None) => break,
            // A file cut short (a take of a crash) is read as far as it goes.
            Err(Error::IoError(_)) => break,
            Err(err) => bail!("{name} is damaged: {err}"),
        };
        if packet.track_id != track_id {
            continue;
        }
        let buffer = match decoder.decode(&packet) {
            Ok(buffer) => buffer,
            Err(Error::DecodeError(_)) => continue,
            Err(err) => bail!("{name} cannot be decoded: {err}"),
        };
        if buffer.frames() == 0 || buffer.num_planes() == 0 {
            continue;
        }
        out.sample_rate = buffer.spec().rate();
        buffer.copy_to_vecs_planar(&mut planes);
        let n = buffer.frames();
        let used = buffer.num_planes();
        out.channels = out.channels.max(used);
        out.peaks.resize(out.channels, 0.0);
        let start = out.frames.len();
        out.frames.resize(start + n, 0.0);
        for (c, plane) in planes.iter().take(used).enumerate() {
            let mut peak = out.peaks[c];
            for (frame, v) in out.frames[start..].iter_mut().zip(plane) {
                let a = v.abs();
                *frame = frame.max(a);
                peak = peak.max(a);
            }
            out.peaks[c] = peak;
        }
    }
    if out.sample_rate == 0 {
        bail!("{name} does not say what its sample rate is");
    }
    out.peaks.resize(out.channels, 0.0);
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn levels_onset_and_blocks_of_a_file() {
        let dir = std::env::temp_dir().join(format!("paw-envelope-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("click.wav");
        // Stereo, 1000 Hz: silence, then 0.5 on the right only at frame 300.
        let mut w = crate::wav::Writer::create(&path, 1000, 16, false).unwrap();
        for f in 0..1000 {
            let r = if f == 300 { 0.5 } else { 0.0 };
            w.write(0.0).unwrap();
            w.write(r).unwrap();
        }
        w.finish().unwrap();
        let env = envelope(&path).unwrap();
        assert_eq!((env.sample_rate, env.channels, env.frames.len()), (1000, 2, 1000));
        assert_eq!(env.peaks[0], 0.0);
        assert!((env.peaks[1] - 0.5).abs() < 1e-3);
        assert_eq!(env.onset(0.1, 0), Some(300));
        assert_eq!(env.onset(0.1, 301), None);
        let blocks = env.blocks(250, 1000, 100);
        assert_eq!(blocks.len(), 8);
        assert!(blocks[0] > 0.4 && blocks[1] == 0.0);
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
