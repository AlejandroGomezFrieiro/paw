//! Decoded audio files, their overviews and converted copies, kept between
//! syncs.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use paw_engine::{AudioData, DiskStore};

use crate::bake::{self, Store};
use crate::media::SourceHash;
use crate::peaks::{self, Summary};

/// Decoded audio files, loaded once and shared between clips.
#[derive(Default)]
pub struct AudioCache {
    files: HashMap<PathBuf, Option<Arc<AudioData>>>,
    /// Overviews, and whether each is in the bake cache too.
    summaries: HashMap<PathBuf, (Arc<Summary>, bool)>,
    /// Recent answers to [`peaks`](Self::peaks), since views ask every frame.
    peaks: HashMap<PeaksKey, Arc<Vec<[f32; 3]>>>,
    /// Files at another rate than the engine's, converted, by file and rate.
    converted: HashMap<(PathBuf, u32), Arc<AudioData>>,
    /// The bake cache, where waveform overviews are kept between runs
    /// (`peaks::Summary`), so that drawing a file need not decode it;
    /// nowhere when `None`.
    pub(crate) bakes: Option<Store>,
    /// Where the decoded sound of long files is kept and played from,
    /// instead of memory; nowhere when `None`.
    pub store: Option<DiskStore>,
    /// The bakes of stretched and shifted clips: `stretched.rs`.
    pub(crate) renders: crate::stretched::Renders,
    /// Exports, progress and tidying of those bakes.
    pub(crate) upkeep: crate::stretched::Upkeep,
}

/// File, offset and length in seconds (as bits, to hash them), and points.
type PeaksKey = (PathBuf, u64, u64, usize);

impl AudioCache {

    /// A cache that keeps waveform overviews in `store` between runs.
    #[cfg(test)]
    pub(crate) fn with_bakes(store: Store) -> Self {
        Self {
            bakes: Some(store),
            ..Self::default()
        }
    }

    /// Load a file, reporting why it could not be read.
    pub(crate) fn load(&mut self, path: &Path) -> anyhow::Result<Arc<AudioData>> {
        if let Some(Some(data)) = self.files.get(path) {
            return Ok(data.clone());
        }
        let loaded = AudioData::load_with(path, self.store.as_ref());
        self.files
            .insert(path.to_path_buf(), loaded.as_ref().ok().cloned());
        loaded
    }

    /// `n` (min, max) pairs covering `seconds` of a file from `offset`.
    /// `source` is the hash of the file's bytes, when it is known.
    pub(crate) fn peaks(
        &mut self,
        path: &Path,
        source: Option<SourceHash>,
        offset: f64,
        seconds: f64,
        n: usize,
    ) -> anyhow::Result<Arc<Vec<[f32; 3]>>> {
        let key = (path.to_path_buf(), offset.to_bits(), seconds.to_bits(), n);
        if let Some(peaks) = self.peaks.get(&key) {
            return Ok(peaks.clone());
        }
        let summary = self.summary(path, source)?;
        let rate = summary.sample_rate as f64;
        let from = offset * rate;
        let to = from + seconds * rate;
        let decoded = self.files.get(path).cloned().flatten();
        let peaks = match decoded {
            // Decoded already: exact to the sample.
            Some(data) => peaks::peaks(&data, &summary, from, to, n),
            None => match peaks::coarse(&summary, from, to, n) {
                // Zoomed out: the overview alone, without decoding the file.
                Some(peaks) => peaks,
                None => {
                    let data = self.load(path)?;
                    peaks::peaks(&data, &summary, from, to, n)
                }
            },
        };
        let peaks = Arc::new(peaks);
        // Zooming and editing leave old answers behind; a bound keeps them
        // from piling up without tracking which are still wanted.
        if self.peaks.len() >= 256 {
            self.peaks.clear();
        }
        self.peaks.insert(key, peaks.clone());
        Ok(peaks)
    }

    /// True when no file, nor anything worked out from one, is kept.
    pub(crate) fn holds_nothing(&self) -> bool {
        self.files.is_empty()
            && self.summaries.is_empty()
            && self.peaks.is_empty()
            && self.converted.is_empty()
            && self.renders.is_empty()
    }

    /// Forget every file but those in `keep`, and what was worked out from
    /// them (converted copies, overviews, peaks). Files a clip in the engine
    /// or a running render still plays stay in memory until they let go.
    pub(crate) fn retain(&mut self, keep: &HashSet<PathBuf>) {
        self.files.retain(|path, _| keep.contains(path));
        self.summaries.retain(|path, _| keep.contains(path));
        self.peaks.retain(|key, _| keep.contains(&key.0));
        self.converted.retain(|key, _| keep.contains(&key.0));
        self.renders.retain(|k| keep.contains(&k.file));
    }

    /// What a stretched or shifted clip plays, if its bake has started (as
    /// far as it is made); if not, it is asked for (see `stretched.rs`).
    pub(crate) fn stretched(
        &mut self,
        key: &crate::stretched::Key,
        warnings: &mut Vec<String>,
    ) -> Option<Arc<AudioData>> {
        if key.source.is_none() {
            // Asked again once the file has a hash: its preview plays meanwhile.
            self.upkeep.unhashed.insert(key.file.clone());
            return None;
        }
        if !self.renders.known(key) {
            let source = self.get(&key.file, key.rate, warnings);
            let (bakes, disk) = (self.bakes.clone(), self.store.clone());
            self.renders.ask(key, || Some(crate::stretched::bake(key.clone(), source?, bakes, disk)));
        }
        self.renders.sound(key)
    }

    /// What the engine plays of a file at `rate`, if it has been loaded:
    /// the file's own samples or their conversion.
    pub(crate) fn playing(&self, path: &Path, rate: u32) -> Option<&Arc<AudioData>> {
        let data = self.files.get(path)?.as_ref()?;
        if data.sample_rate == rate {
            return Some(data);
        }
        self.converted
            .get(&(path.to_path_buf(), rate))
            .or(Some(data))
    }

    /// Whether a file that has been loaded is played from the disk.
    pub(crate) fn on_disk(&self, path: &Path) -> Option<bool> {
        Some(self.files.get(path)?.as_ref()?.on_disk())
    }

    /// Forget the decoded files, so that each is loaded again when it is
    /// next asked for. Whatever plays one keeps what it has.
    pub(crate) fn forget_loaded(&mut self) {
        self.files.clear();
        self.converted.clear();
        self.renders.retain(|_| false);
    }

    /// How many files are held, decoded or known to be unreadable.
    pub(crate) fn len(&self) -> usize {
        self.files.len()
    }

    /// A file's waveform overview: kept in memory, read from the bake
    /// cache when it was made before for the same bytes, or made from the
    /// samples and kept there. `source` is the hash of the file's bytes
    /// (the media table's, `crate::media`), which names the overview
    /// wherever the file is. Until it is known (hashing runs in the
    /// background), the overview is made from the samples and kept in
    /// memory only; it goes into the cache once the hash is known.
    fn summary(&mut self, path: &Path, source: Option<SourceHash>) -> anyhow::Result<Arc<Summary>> {
        let bake = self
            .bakes
            .clone()
            .zip(source)
            .map(|(store, source)| (store, peaks::bake(source)));
        if let Some((summary, cached)) = self.summaries.get(path).cloned() {
            if !cached && let Some((store, (job, key))) = &bake {
                Self::keep(store, job, key, &summary);
                self.summaries.insert(path.to_path_buf(), (summary.clone(), true));
            }
            return Ok(summary);
        }
        let kept = bake.as_ref().and_then(|(store, (_, key))| {
            Summary::read(&store.open(key)?.file(peaks::FILE))
        });
        let summary = match kept {
            Some(summary) => summary,
            None => {
                let summary = Summary::new(&*self.load(path)?);
                if let Some((store, (job, key))) = &bake {
                    Self::keep(store, job, key, &summary);
                }
                summary
            }
        };
        let summary = Arc::new(summary);
        self.summaries
            .insert(path.to_path_buf(), (summary.clone(), bake.is_some()));
        Ok(summary)
    }

    /// Put an overview into the bake cache. A cache that cannot be written
    /// only costs time.
    fn keep(store: &Store, job: &bake::BakeJob, key: &bake::EntryKey, summary: &Summary) {
        if let Ok(bake::Write::Make(entry)) = store.writer(job, key)
            && summary.write(&entry.file(peaks::FILE)).is_ok()
        {
            let _ = entry.commit();
        }
    }

    /// A file for playing at `rate`: converted when it is at another.
    pub(super) fn get(
        &mut self,
        path: &Path,
        rate: u32,
        warnings: &mut Vec<String>,
    ) -> Option<Arc<AudioData>> {
        let data = self.get_native(path, warnings)?;
        if data.sample_rate == rate {
            return Some(data);
        }
        let key = (path.to_path_buf(), rate);
        if let Some(converted) = self.converted.get(&key) {
            return Some(converted.clone());
        }
        // A long file converted is as long: it goes where the file went.
        let kept = self.store.as_ref().and_then(|store| {
            Some((store, paw_engine::store_name(path, &rate.to_string())?))
        });
        if let Some((store, name)) = &kept
            && let Some(converted) = store.open(name)
        {
            let converted = Arc::new(converted);
            self.converted.insert(key, converted.clone());
            return Some(converted);
        }
        match crate::resample::convert_into(&data, rate, paw_engine::Sink::new(kept)) {
            Ok(converted) => {
                let converted = Arc::new(converted);
                self.converted.insert(key, converted.clone());
                Some(converted)
            }
            Err(err) => {
                warnings.push(format!("{}: {err:#}", path.display()));
                Some(data)
            }
        }
    }

    fn get_native(&mut self, path: &Path, warnings: &mut Vec<String>) -> Option<Arc<AudioData>> {
        if let Some(known) = self.files.get(path) {
            return known.clone();
        }
        // A file that is not there is reported once, with the others
        // missing, when the project is opened (session/media.rs).
        let missing = !path.exists();
        self.load(path)
            .map_err(|err| {
                if !missing {
                    warnings.push(format!("{err:#}"))
                }
            })
            .ok()
    }
}
