//! The errors of the readers. Each `Display` text is what the user sees in
//! the instrument's warnings and in `describe`'s `error`, so the texts
//! name the file first, as they always did.

use std::path::{Path, PathBuf};
use std::sync::Arc;
use thiserror::Error;

/// Why an instrument file was not read.
#[derive(Debug, Error)]
pub enum FormatError {
    #[error("{}: {source}", path.display())]
    Io {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("{}: not an instrument this player reads", .0.display())]
    UnknownFormat(PathBuf),
    #[error("{}: {source}", path.display())]
    Xml {
        path: PathBuf,
        #[source]
        source: roxmltree::Error,
    },
    #[error("not a Decent Sampler preset")]
    NotDecentSampler,
    #[error("no <groups>")]
    NoGroups,
    #[error("{}: includes nested too deep", .0.display())]
    IncludeTooDeep(PathBuf),
}

impl FormatError {
    pub fn io(path: &Path, source: std::io::Error) -> Self {
        FormatError::Io { path: path.to_path_buf(), source }
    }
}

/// Why a sample file was not read. Cloneable: one failure answers every
/// region that names the file.
#[derive(Debug, Clone, Error)]
pub enum SampleError {
    #[error("{}: {source}", path.display())]
    Io {
        path: PathBuf,
        #[source]
        source: Arc<std::io::Error>,
    },
    #[error("{}: {reason}", path.display())]
    Decode {
        path: PathBuf,
        #[source]
        reason: DecodeError,
    },
    #[error("{}: not read", .0.display())]
    NotRead(PathBuf),
}

impl SampleError {
    pub fn io(path: &Path, source: std::io::Error) -> Self {
        SampleError::Io { path: path.to_path_buf(), source: Arc::new(source) }
    }
}

/// What is wrong inside a sample file.
#[derive(Debug, Clone, Error)]
pub enum DecodeError {
    #[error("not a WAV, AIFF, FLAC or Ogg Vorbis file")]
    UnknownKind,
    #[error("{0}")]
    Wav(Arc<hound::Error>),
    #[error("no channels")]
    NoChannels,
    #[error("no COMM chunk")]
    NoComm,
    #[error("no SSND chunk")]
    NoSsnd,
    #[error("compressed AIFF is not read")]
    CompressedAiff,
    #[error("{0}")]
    Codec(Arc<symphonia::core::errors::Error>),
    #[error("no audio in it")]
    NoAudio,
    #[error("no audio decoded")]
    NothingDecoded,
}
