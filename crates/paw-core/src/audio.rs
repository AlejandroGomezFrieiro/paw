//! Which audio devices to open. The choice belongs to the machine, not to a
//! project, so it is kept in the program's state directory
//! (`$XDG_STATE_HOME/paw/audio.json`) and applied before the engine starts.

use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use paw_engine::backend::{BackendChoice, BackendOptions};
use serde::{Deserialize, Serialize};

/// What was last chosen with `paw.audio.use`. `None` leaves it to the
/// system's default, or for the block size to the device.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Remembered {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub output: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub input: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub buffer: Option<u32>,
    /// The sound system (`pipewire`, `alsa`, `jack`), when one was chosen.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub backend: Option<String>,
    /// The sample rate, when one was chosen rather than the device's.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rate: Option<u32>,
}

/// Where the choice is kept.
pub fn file() -> PathBuf {
    let base = std::env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".local/state")))
        .unwrap_or_else(std::env::temp_dir);
    base.join("paw").join("audio.json")
}

/// The choice kept in `path`; nothing chosen when there is no such file or it
/// cannot be read.
pub fn load(path: &Path) -> Remembered {
    std::fs::read_to_string(path)
        .ok()
        .and_then(|text| serde_json::from_str(&text).ok())
        .unwrap_or_default()
}

pub fn save(path: &Path, remembered: &Remembered) -> Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).with_context(|| format!("creating {}", dir.display()))?;
    }
    let text = serde_json::to_string_pretty(remembered)?;
    std::fs::write(path, text + "\n").with_context(|| format!("writing {}", path.display()))
}

/// Fill in what the command line left open from what was remembered. The
/// null backend opens no devices, so it is left alone.
pub fn apply(opts: &mut BackendOptions, remembered: &Remembered) {
    if opts.backend == BackendChoice::Null {
        return;
    }
    if opts.backend == BackendChoice::Auto
        && let Some(backend) = &remembered.backend
    {
        opts.backend = backend.as_str().into();
    }
    if opts.sample_rate.is_none() {
        opts.sample_rate = remembered.rate;
    }
    if opts.output_device.is_none() {
        opts.output_device = remembered.output.clone();
    }
    if opts.input_device.is_none() {
        opts.input_device = remembered.input.clone();
    }
    if opts.buffer_size.is_none() {
        opts.buffer_size = remembered.buffer;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_choice_is_kept_and_read_back() {
        let dir = std::env::temp_dir().join(format!("paw-audio-test-{}", std::process::id()));
        let path = dir.join("paw/audio.json");
        assert_eq!(
            load(&path),
            Remembered::default(),
            "nothing is chosen at first"
        );
        let chosen = Remembered {
            output: Some("Steinberg UR22mkII Stereo Output".into()),
            input: Some("Steinberg UR22mkII 0".into()),
            buffer: Some(128),
            backend: Some("pipewire".into()),
            rate: Some(44100),
        };
        save(&path, &chosen).unwrap();
        assert_eq!(load(&path), chosen);
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn the_command_line_wins_and_the_null_backend_opens_nothing() {
        let remembered = Remembered {
            output: Some("UR22".into()),
            input: Some("UR22".into()),
            buffer: Some(128),
            ..Default::default()
        };
        let mut opts = BackendOptions {
            input_device: Some("C920".into()),
            ..Default::default()
        };
        apply(&mut opts, &remembered);
        assert_eq!(opts.output_device.as_deref(), Some("UR22"));
        assert_eq!(opts.input_device.as_deref(), Some("C920"));
        assert_eq!(opts.buffer_size, Some(128));
        let mut null = BackendOptions {
            backend: "null".into(),
            ..Default::default()
        };
        apply(&mut null, &remembered);
        assert_eq!(null.output_device, None);
        assert_eq!(null.buffer_size, None);
    }

    #[test]
    fn a_chosen_sound_system_and_rate_are_used_unless_the_command_line_says_otherwise() {
        let remembered = Remembered {
            backend: Some("alsa".into()),
            rate: Some(44100),
            ..Default::default()
        };
        let mut opts = BackendOptions::default();
        apply(&mut opts, &remembered);
        assert_eq!(opts.backend, BackendChoice::Host("alsa".into()));
        assert_eq!(opts.sample_rate, Some(44100));
        let mut given = BackendOptions {
            backend: "jack".into(),
            sample_rate: Some(96000),
            ..Default::default()
        };
        apply(&mut given, &remembered);
        assert_eq!(given.backend, BackendChoice::Host("jack".into()));
        assert_eq!(given.sample_rate, Some(96000));
    }
}
