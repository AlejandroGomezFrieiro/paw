//! How long each callback took, as a histogram the audio thread fills.

use std::sync::atomic::{AtomicU64, Ordering::Relaxed};

/// Buckets of [`BlockStats`]: four per octave of processing time, from
/// [`BLOCK_STATS_FLOOR_NS`] up, which reaches past 10 seconds.
pub const BLOCK_BUCKETS: usize = 100;
/// Times below this land in the first bucket.
pub const BLOCK_STATS_FLOOR_NS: f64 = 250.0;

/// How long each call to [`Engine::process_input`] took, as a histogram the
/// audio thread fills with relaxed atomic adds: no allocation, no locks.
pub struct BlockStats {
    pub(super) count: AtomicU64,
    pub(super) frames: AtomicU64,
    pub(super) total_ns: AtomicU64,
    pub(super) max_ns: AtomicU64,
    pub(super) buckets: [AtomicU64; BLOCK_BUCKETS],
}

/// A copy of [`BlockStats`] for the main thread to read.
#[derive(Clone, Debug, Default)]
pub struct BlockSummary {
    pub count: u64,
    pub frames: u64,
    pub total_ns: u64,
    pub max_ns: u64,
    pub buckets: Vec<u64>,
}

impl BlockStats {
    pub(super) fn new() -> Self {
        Self {
            count: AtomicU64::new(0),
            frames: AtomicU64::new(0),
            total_ns: AtomicU64::new(0),
            max_ns: AtomicU64::new(0),
            buckets: std::array::from_fn(|_| AtomicU64::new(0)),
        }
    }

    /// The bucket a time falls in.
    pub fn bucket(ns: u64) -> usize {
        let ratio = ns as f64 / BLOCK_STATS_FLOOR_NS;
        if ratio < 1.0 {
            return 0;
        }
        ((ratio.log2() * 4.0) as usize + 1).min(BLOCK_BUCKETS - 1)
    }

    /// The upper edge of a bucket, in nanoseconds.
    pub fn bucket_limit_ns(index: usize) -> f64 {
        BLOCK_STATS_FLOOR_NS * 2f64.powf(index as f64 / 4.0)
    }

    pub fn record(&self, ns: u64, frames: usize) {
        self.count.fetch_add(1, Relaxed);
        self.frames.fetch_add(frames as u64, Relaxed);
        self.total_ns.fetch_add(ns, Relaxed);
        self.max_ns.fetch_max(ns, Relaxed);
        self.buckets[Self::bucket(ns)].fetch_add(1, Relaxed);
    }

    pub fn reset(&self) {
        self.count.store(0, Relaxed);
        self.frames.store(0, Relaxed);
        self.total_ns.store(0, Relaxed);
        self.max_ns.store(0, Relaxed);
        for b in &self.buckets {
            b.store(0, Relaxed);
        }
    }

    pub fn summary(&self) -> BlockSummary {
        BlockSummary {
            count: self.count.load(Relaxed),
            frames: self.frames.load(Relaxed),
            total_ns: self.total_ns.load(Relaxed),
            max_ns: self.max_ns.load(Relaxed),
            buckets: self.buckets.iter().map(|b| b.load(Relaxed)).collect(),
        }
    }
}

impl BlockSummary {
    /// The time below which a fraction `q` of the calls finished, to within
    /// a bucket (19%), in nanoseconds. Never above the largest time seen.
    pub fn quantile_ns(&self, q: f64) -> f64 {
        let total: u64 = self.buckets.iter().sum();
        if total == 0 {
            return 0.0;
        }
        let want = (q * total as f64).ceil().max(1.0) as u64;
        let mut seen = 0;
        for (i, n) in self.buckets.iter().enumerate() {
            seen += n;
            if seen >= want {
                return BlockStats::bucket_limit_ns(i).min(self.max_ns as f64);
            }
        }
        self.max_ns as f64
    }
}
