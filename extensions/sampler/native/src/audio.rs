//! Samples in memory: read whole from WAV and AIFF files, or made for
//! SFZ's generators, and kept in their own width (16-bit as 16-bit) to
//! halve what a library takes.
//!
//! A voice reads a sample through `Sample::frame`, so a sample whose tail
//! stays on disk (streaming: the first frames in memory, the rest read
//! ahead by a thread into each voice's ring) can be added behind it
//! without the voice changing.

use crate::error::{DecodeError, SampleError};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;

/// Frames of silence kept before and after every sample, so that the
/// interpolator's taps never fall outside it.
pub const PAD: usize = 8;

pub enum Pcm {
    I16(Box<[i16]>),
    F32(Box<[f32]>),
}

/// A sample's value as a float, whatever its width.
pub trait Value: Copy {
    fn f(self) -> f32;
}

impl Value for i16 {
    #[inline(always)]
    fn f(self) -> f32 {
        self as f32 * (1.0 / 32768.0)
    }
}

impl Value for f32 {
    #[inline(always)]
    fn f(self) -> f32 {
        self
    }
}

pub struct Sample {
    pub rate: f64,
    /// 1 or 2: a file with more keeps its first two.
    pub channels: usize,
    /// Without the padding.
    pub frames: usize,
    /// Interleaved, `PAD` frames of silence at each end.
    pub pcm: Pcm,
    /// From the file (a WAV `smpl` chunk): start and end, inclusive.
    pub loop_points: Option<(u64, u64)>,
    pub keycenter: Option<u8>,
    /// Cents, from the file.
    pub fine_tune: f32,
    /// Frames before the attack: the first frame that reaches a tenth
    /// (-20 dB) of the sample's peak. What `describe` reports as a delay.
    pub onset: u64,
}

/// The fraction of a sample's peak that counts as its attack.
const ONSET: f32 = 0.1;

/// The first frame of `data` (interleaved, padded) that reaches `ONSET` of
/// its peak, counted from the first frame after the padding.
fn onset<S: Value>(data: &[S]) -> u64 {
    let peak = data.iter().fold(0.0f32, |m, v| m.max(v.f().abs()));
    if peak == 0.0 {
        return 0;
    }
    let first = data.iter().position(|v| v.f().abs() >= peak * ONSET).unwrap_or(0);
    first as u64
}

impl Sample {
    pub fn bytes(&self) -> usize {
        match &self.pcm {
            Pcm::I16(d) => d.len() * 2,
            Pcm::F32(d) => d.len() * 4,
        }
    }

    fn from_f32(rate: f64, channels: usize, data: Vec<f32>) -> Sample {
        let frames = data.len() / channels;
        let mut padded = vec![0.0f32; (frames + 2 * PAD) * channels];
        padded[PAD * channels..(PAD + frames) * channels].copy_from_slice(&data[..frames * channels]);
        Sample {
            rate,
            channels,
            frames,
            onset: (onset(&padded) / channels as u64).saturating_sub(PAD as u64),
            pcm: Pcm::F32(padded.into_boxed_slice()),
            loop_points: None,
            keycenter: None,
            fine_tune: 0.0,
        }
    }

    fn from_i16(rate: f64, channels: usize, data: Vec<i16>) -> Sample {
        let frames = data.len() / channels;
        let mut padded = vec![0i16; (frames + 2 * PAD) * channels];
        padded[PAD * channels..(PAD + frames) * channels].copy_from_slice(&data[..frames * channels]);
        Sample {
            rate,
            channels,
            frames,
            onset: (onset(&padded) / channels as u64).saturating_sub(PAD as u64),
            pcm: Pcm::I16(padded.into_boxed_slice()),
            loop_points: None,
            keycenter: None,
            fine_tune: 0.0,
        }
    }

    /// One cycle of a generator at key 60's pitch, looped; noise is a
    /// second of it.
    pub fn wave(wave: crate::model::Wave) -> Sample {
        use crate::model::Wave;
        const N: usize = 2048;
        let freq = 440.0 * 2f64.powf((60.0 - 69.0) / 12.0);
        let mut data = vec![0.0f32; N];
        let mut sample = match wave {
            Wave::Noise => {
                // A fixed seed: the same noise in every render.
                let mut state = 0x9E37_79B9_7F4A_7C15u64;
                let mut noise = vec![0.0f32; 48000];
                for v in noise.iter_mut() {
                    state ^= state << 13;
                    state ^= state >> 7;
                    state ^= state << 17;
                    *v = ((state >> 40) as f32 / (1u64 << 24) as f32) * 2.0 - 1.0;
                }
                let mut s = Sample::from_f32(48000.0, 1, noise);
                s.loop_points = Some((0, 47999));
                return s;
            }
            _ => {
                for (i, v) in data.iter_mut().enumerate() {
                    let t = i as f64 / N as f64;
                    *v = match wave {
                        Wave::Sine => (t * std::f64::consts::TAU).sin(),
                        Wave::Saw => 2.0 * t - 1.0,
                        Wave::Square => if t < 0.5 { 1.0 } else { -1.0 },
                        _ => 1.0 - 4.0 * (t - 0.5).abs(),
                    } as f32;
                }
                Sample::from_f32(freq * N as f64, 1, data)
            }
        };
        sample.loop_points = Some((0, N as u64 - 1));
        sample.keycenter = Some(60);
        sample
    }

    pub fn silence() -> Sample {
        let mut s = Sample::from_f32(48000.0, 1, vec![0.0; 64]);
        s.loop_points = Some((0, 63));
        s
    }
}

/// Samples by path, kept while an instrument uses them, so that loading
/// it again (a preset after the project's state) reads nothing twice.
#[derive(Default)]
pub struct Store {
    files: HashMap<PathBuf, Arc<Sample>>,
}

impl Store {
    /// Every one of `paths`, read on several threads at once: a library is
    /// thousands of files, and the disk and the decoding both go faster so.
    pub fn load_all(&mut self, paths: &[PathBuf]) -> Vec<Result<Arc<Sample>, SampleError>> {
        let missing: Vec<&PathBuf> = paths.iter().filter(|p| !self.files.contains_key(*p)).collect();
        let next = std::sync::atomic::AtomicUsize::new(0);
        let threads = std::thread::available_parallelism().map_or(4, |n| n.get()).clamp(1, 8);
        let read: Vec<(usize, Result<Sample, SampleError>)> = std::thread::scope(|scope| {
            let workers: Vec<_> = (0..threads.min(missing.len()))
                .map(|_| {
                    scope.spawn(|| {
                        let mut done = Vec::new();
                        loop {
                            let i = next.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                            let Some(path) = missing.get(i) else { break };
                            done.push((i, read_file(path)));
                        }
                        done
                    })
                })
                .collect();
            workers.into_iter().flat_map(|w| w.join().unwrap_or_default()).collect()
        });
        let mut failed: HashMap<&Path, SampleError> = HashMap::new();
        for (i, result) in read {
            match result {
                Ok(sample) => {
                    self.files.insert(missing[i].clone(), Arc::new(sample));
                }
                Err(e) => {
                    failed.insert(missing[i].as_path(), e);
                }
            }
        }
        paths
            .iter()
            .map(|p| match self.files.get(p) {
                Some(s) => Ok(s.clone()),
                None => Err(failed.get(p.as_path()).cloned().unwrap_or_else(|| SampleError::NotRead(p.clone()))),
            })
            .collect()
    }

    /// Forgets samples nothing else holds.
    pub fn trim(&mut self) {
        self.files.retain(|_, s| Arc::strong_count(s) > 1);
    }
}

pub fn read_file(path: &Path) -> Result<Sample, SampleError> {
    let bytes = std::fs::read(path).map_err(|e| SampleError::io(path, e))?;
    let decode_error = |reason| SampleError::Decode { path: path.to_path_buf(), reason };
    if bytes.starts_with(b"RIFF") && bytes.get(8..12) == Some(b"WAVE") {
        read_wav(&bytes)
    } else if bytes.starts_with(b"FORM") && matches!(bytes.get(8..12), Some(b"AIFF") | Some(b"AIFC")) {
        read_aiff(&bytes)
    } else if bytes.starts_with(b"fLaC") || bytes.starts_with(b"OggS") {
        decode(path, bytes)
    } else {
        Err(DecodeError::UnknownKind)
    }
    .map_err(decode_error)
}

/// FLAC and Ogg Vorbis, through symphonia.
fn decode(path: &Path, bytes: Vec<u8>) -> Result<Sample, DecodeError> {
    use symphonia::core::codecs::audio::AudioDecoderOptions;
    use symphonia::core::formats::probe::Hint;
    use symphonia::core::formats::{FormatOptions, TrackType};
    use symphonia::core::io::MediaSourceStream;
    use symphonia::core::meta::MetadataOptions;
    let codec = |e| DecodeError::Codec(Arc::new(e));
    let stream = MediaSourceStream::new(Box::new(std::io::Cursor::new(bytes)), Default::default());
    let mut hint = Hint::new();
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }
    let mut format = symphonia::default::get_probe()
        .probe(&hint, stream, FormatOptions::default(), MetadataOptions::default())
        .map_err(codec)?;
    let track = format.default_track(TrackType::Audio).ok_or(DecodeError::NoAudio)?;
    let params = track.codec_params.as_ref().and_then(|p| p.audio()).ok_or(DecodeError::NoAudio)?;
    let track_id = track.id;
    let mut decoder = symphonia::default::get_codecs()
        .make_audio_decoder(params, &AudioDecoderOptions::default())
        .map_err(codec)?;
    let mut rate = params.sample_rate.unwrap_or(0);
    let mut planes: Vec<Vec<f32>> = Vec::new();
    let (mut left, mut right): (Vec<f32>, Vec<f32>) = (Vec::new(), Vec::new());
    let mut stereo = false;
    while let Ok(Some(packet)) = format.next_packet() {
        if packet.track_id != track_id {
            continue;
        }
        let Ok(buffer) = decoder.decode(&packet) else { continue };
        if buffer.frames() == 0 || buffer.num_planes() == 0 {
            continue;
        }
        rate = buffer.spec().rate();
        buffer.copy_to_vecs_planar(&mut planes);
        left.extend_from_slice(&planes[0]);
        if let Some(r) = planes.get(1) {
            stereo = true;
            right.extend_from_slice(r);
        }
    }
    if left.is_empty() || rate == 0 {
        return Err(DecodeError::NothingDecoded);
    }
    let data = if stereo {
        left.iter().zip(&right).flat_map(|(l, r)| [*l, *r]).collect()
    } else {
        left
    };
    Ok(Sample::from_f32(rate as f64, if stereo { 2 } else { 1 }, data))
}

fn u32le(b: &[u8], at: usize) -> u32 {
    u32::from_le_bytes([b[at], b[at + 1], b[at + 2], b[at + 3]])
}

/// The body of the first RIFF chunk called `id`. `hound` reads the
/// format and the data of a WAV but not its `smpl` chunk, so the key and
/// the loop of a sample come from here.
fn riff_chunk<'a>(bytes: &'a [u8], id: &[u8; 4]) -> Option<&'a [u8]> {
    let mut at = 12;
    while at + 8 <= bytes.len() {
        let size = u32le(bytes, at + 4) as usize;
        if &bytes[at..at + 4] == id {
            return Some(&bytes[at + 8..(at + 8 + size).min(bytes.len())]);
        }
        at += 8 + size + (size & 1);
    }
    None
}

/// The first `keep` of every `channels` values, whole frames only: a file
/// cut short plays what it holds.
fn wav_values<T: hound::Sample>(reader: &mut hound::WavReader<std::io::Cursor<&[u8]>>, channels: usize, keep: usize) -> Vec<T> {
    let mut out = Vec::new();
    let mut values = reader.samples::<T>().map_while(Result::ok);
    'frames: loop {
        let start = out.len();
        for c in 0..channels {
            match values.next() {
                Some(v) if c < keep => out.push(v),
                Some(_) => {}
                None => {
                    out.truncate(start);
                    break 'frames;
                }
            }
        }
    }
    out
}

fn read_wav(bytes: &[u8]) -> Result<Sample, DecodeError> {
    use hound::SampleFormat::{Float, Int};
    let wav = |e| DecodeError::Wav(Arc::new(e));
    let mut reader = hound::WavReader::new(std::io::Cursor::new(bytes)).map_err(wav)?;
    let spec = reader.spec();
    let (channels, rate) = (spec.channels as usize, spec.sample_rate as f64);
    if channels == 0 {
        return Err(DecodeError::NoChannels);
    }
    let keep = channels.min(2);
    let mut sample = match (spec.sample_format, spec.bits_per_sample) {
        (Int, 16) => Sample::from_i16(rate, keep, wav_values::<i16>(&mut reader, channels, keep)),
        (Int, 8) => {
            let data = wav_values::<i8>(&mut reader, channels, keep);
            Sample::from_i16(rate, keep, data.into_iter().map(|v| (v as i16) << 8).collect())
        }
        (Int, 24) => {
            let data = wav_values::<i32>(&mut reader, channels, keep);
            Sample::from_f32(rate, keep, data.into_iter().map(|v| v as f32 / 8388608.0).collect())
        }
        (Int, 32) => {
            let data = wav_values::<i32>(&mut reader, channels, keep);
            Sample::from_f32(rate, keep, data.into_iter().map(|v| v as f32 / 2147483648.0).collect())
        }
        (Float, 32) => Sample::from_f32(rate, keep, wav_values::<f32>(&mut reader, channels, keep)),
        _ => return Err(wav(hound::Error::Unsupported)),
    };
    if let Some(smpl) = riff_chunk(bytes, b"smpl")
        && smpl.len() >= 36
    {
        let unity = u32le(smpl, 12);
        let fraction = u32le(smpl, 16);
        if unity < 128 {
            sample.keycenter = Some(unity as u8);
        }
        sample.fine_tune = fraction as f32 / 4294967296.0 * 100.0;
        if u32le(smpl, 28) > 0 && smpl.len() >= 36 + 24 {
            let (start, end) = (u32le(smpl, 36 + 8) as u64, u32le(smpl, 36 + 12) as u64);
            if end > start && (end as usize) < sample.frames {
                sample.loop_points = Some((start, end));
            }
        }
    }
    Ok(sample)
}

fn read_aiff(bytes: &[u8]) -> Result<Sample, DecodeError> {
    let be16 = |at: usize| u16::from_be_bytes([bytes[at], bytes[at + 1]]);
    let be32 = |at: usize| u32::from_be_bytes([bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3]]);
    let compressed = &bytes[8..12] == b"AIFC";
    let mut at = 12;
    let mut common = None;
    let mut data = None;
    while at + 8 <= bytes.len() {
        let size = be32(at + 4) as usize;
        let body = at + 8;
        match &bytes[at..at + 4] {
            b"COMM" if size >= 18 => {
                let channels = be16(body) as usize;
                let bits = be16(body + 6) as usize;
                // An 80-bit extended float.
                let exp = (be16(body + 8) & 0x7FFF) as i32 - 16383 - 63;
                let mantissa = u64::from_be_bytes(bytes[body + 10..body + 18].try_into().unwrap());
                let rate = mantissa as f64 * 2f64.powi(exp);
                let kind = if compressed && size >= 22 { &bytes[body + 18..body + 22] } else { b"NONE" };
                common = Some((channels, bits, rate, kind.to_vec()));
            }
            b"SSND" if size >= 8 => {
                let offset = be32(body) as usize;
                data = Some(&bytes[(body + 8 + offset).min(bytes.len())..(body + size).min(bytes.len())]);
            }
            _ => {}
        }
        at = body + size + (size & 1);
    }
    let (channels, bits, rate, kind) = common.ok_or(DecodeError::NoComm)?;
    let data = data.ok_or(DecodeError::NoSsnd)?;
    let little = kind == b"sowt";
    if (kind != b"NONE" && !little) || channels == 0 {
        return Err(DecodeError::CompressedAiff);
    }
    let keep = channels.min(2);
    let width = bits.div_ceil(8);
    let frames = data.len() / (width * channels);
    let mut out = Vec::with_capacity(frames * keep);
    for f in 0..frames {
        for c in 0..keep {
            let p = (f * channels + c) * width;
            let mut s = [0u8; 4];
            for i in 0..width.min(4) {
                s[i] = if little { data[p + width - 1 - i] } else { data[p + i] };
            }
            let v = i32::from_be_bytes(s);
            out.push(v as f32 / 2147483648.0);
        }
    }
    Ok(Sample::from_f32(rate, keep, out))
}


/// Writes a 16-bit WAV (for the fixtures the tests make, and for `render`),
/// with a `smpl` chunk when a key or a loop is given.
pub fn write_wav(path: &Path, rate: u32, channels: u16, data: &[f32], keycenter: Option<u8>, loop_: Option<(u32, u32)>) -> hound::Result<()> {
    let spec = hound::WavSpec { channels, sample_rate: rate, bits_per_sample: 16, sample_format: hound::SampleFormat::Int };
    let mut out = std::io::Cursor::new(Vec::new());
    let mut writer = hound::WavWriter::new(&mut out, spec)?;
    for v in data {
        writer.write_sample((v.clamp(-1.0, 1.0) * 32767.0).round() as i16)?;
    }
    writer.finalize()?;
    let mut bytes = out.into_inner();
    if keycenter.is_some() || loop_.is_some() {
        let loops = loop_.iter().count() as u32;
        bytes.extend_from_slice(b"smpl");
        bytes.extend_from_slice(&(36 + 24 * loops).to_le_bytes());
        for v in [0, 0, 1_000_000_000 / rate, keycenter.unwrap_or(60) as u32, 0, 0, 0, loops, 0] {
            bytes.extend_from_slice(&v.to_le_bytes());
        }
        if let Some((start, end)) = loop_ {
            for v in [0, 0, start, end, 0, 0] {
                bytes.extend_from_slice(&v.to_le_bytes());
            }
        }
        // The RIFF size counts what follows its own eight bytes.
        let riff = (bytes.len() - 8) as u32;
        bytes[4..8].copy_from_slice(&riff.to_le_bytes());
    }
    std::fs::write(path, bytes)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn other_wav_widths_and_channels_read() {
        let dir = std::env::temp_dir().join(format!("paw-sampler-wav-width-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("b.wav");
        // 24-bit, three channels: the first two are kept.
        let spec = hound::WavSpec { channels: 3, sample_rate: 22050, bits_per_sample: 24, sample_format: hound::SampleFormat::Int };
        let mut w = hound::WavWriter::create(&path, spec).unwrap();
        for _ in 0..10 {
            for v in [4194304, -4194304, 7] {
                w.write_sample(v).unwrap();
            }
        }
        w.finalize().unwrap();
        let s = read_file(&path).unwrap();
        assert_eq!((s.frames, s.channels, s.rate), (10, 2, 22050.0));
        let Pcm::F32(d) = &s.pcm else { panic!("24-bit reads as float") };
        assert_eq!((d[PAD * 2], d[PAD * 2 + 1]), (0.5, -0.5));
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn wav_round_trip_with_loop_and_key() {
        let dir = std::env::temp_dir().join(format!("paw-sampler-wav-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("a.wav");
        let data: Vec<f32> = (0..1000).map(|i| (i as f32 / 10.0).sin() * 0.5).collect();
        write_wav(&path, 44100, 1, &data, Some(57), Some((100, 899))).unwrap();
        let s = read_file(&path).unwrap();
        assert_eq!((s.frames, s.channels, s.rate), (1000, 1, 44100.0));
        assert_eq!(s.keycenter, Some(57));
        assert_eq!(s.loop_points, Some((100, 899)));
        let Pcm::I16(d) = &s.pcm else { panic!("16-bit kept as 16-bit") };
        assert!((d[PAD + 5].f() - data[5]).abs() < 1e-4);
        assert_eq!(d[0].f(), 0.0);
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
