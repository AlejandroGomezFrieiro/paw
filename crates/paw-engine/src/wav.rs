//! WAV output, stereo or mono.
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::cast_precision_loss, reason = "debt: pay down")]

use std::fs::File;
use std::io::BufWriter;
use std::path::Path;

use anyhow::Result;

/// The form of each sample in the file.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WavFormat {
    /// 16-bit integer PCM.
    Int16,
    /// 24-bit integer PCM.
    Int24,
    /// 32-bit float.
    Float32,
}

impl WavFormat {
    /// The format of `bits` bits a sample: 16, 24 or 32 (float).
    pub fn from_bits(bits: u16) -> Option<Self> {
        match bits {
            16 => Some(Self::Int16),
            24 => Some(Self::Int24),
            32 => Some(Self::Float32),
            _ => None,
        }
    }

    fn bits(self) -> u16 {
        match self {
            Self::Int16 => 16,
            Self::Int24 => 24,
            Self::Float32 => 32,
        }
    }
}

pub struct Writer {
    inner: hound::WavWriter<BufWriter<File>>,
    /// Full scale for integer formats, or `None` when writing floats.
    scale: Option<f32>,
}

impl Writer {
    /// A stereo file.
    pub fn create(path: &Path, sample_rate: u32, format: WavFormat) -> Result<Self> {
        Self::with_channels(path, sample_rate, format, 2)
    }

    /// As [`create`](Self::create), with one channel or more.
    pub fn with_channels(
        path: &Path,
        sample_rate: u32,
        format: WavFormat,
        channels: u16,
    ) -> Result<Self> {
        let bits = format.bits();
        let (sample_format, scale) = match format {
            WavFormat::Float32 => (hound::SampleFormat::Float, None),
            WavFormat::Int16 | WavFormat::Int24 => {
                (hound::SampleFormat::Int, Some(((1i64 << (bits - 1)) - 1) as f32))
            }
        };
        let spec = hound::WavSpec {
            channels,
            sample_rate,
            bits_per_sample: bits,
            sample_format,
        };
        Ok(Self {
            inner: hound::WavWriter::create(path, spec)?,
            scale,
        })
    }

    /// Write one sample. In stereo, samples alternate left, right.
    pub fn write(&mut self, sample: f32) -> Result<()> {
        match self.scale {
            Some(scale) => self
                .inner
                .write_sample((sample.clamp(-1.0, 1.0) * scale) as i32)?,
            None => self.inner.write_sample(sample)?,
        }
        Ok(())
    }

    pub fn finish(self) -> Result<()> {
        Ok(self.inner.finalize()?)
    }
}
