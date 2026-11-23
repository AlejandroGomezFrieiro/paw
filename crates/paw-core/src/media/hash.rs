//! Content hashes of files: BLAKE3, the name of a source (see
//! `bench/media.md` for why this hash and the numbers behind the limits).
//!
//! Two ways to make the same hash: [`file`] for a file on disk (a big file
//! is memory-mapped and hashed on all cores), and [`Incremental`] for bytes
//! that pass by while something else reads or writes them (an import that
//! decodes, a recording that writes). The tests have `bytes` for bytes in
//! memory.

use std::fs::File;
use std::io::{self, Write};
use std::path::Path;

pub(crate) use blake3::Hash;

/// From this size a file is memory-mapped and hashed on the rayon pool.
/// Under it, one thread reads as fast as the disk and the page cache give
/// (a 53 MB file was no faster on 8 threads: bench/media.md).
pub(crate) const PARALLEL_MIN: u64 = 64 << 20;

/// The hash of the bytes of the file at `path`.
pub fn file(path: &Path) -> io::Result<Hash> {
    file_from(path, PARALLEL_MIN)
}

/// As [`file`], with the size from which the file is hashed on all cores.
fn file_from(path: &Path, parallel_min: u64) -> io::Result<Hash> {
    let file = File::open(path)?;
    let size = file.metadata()?.len();
    let mut hasher = blake3::Hasher::new();
    if size >= parallel_min {
        hasher.update_mmap_rayon(path)?;
    } else {
        hasher.update_reader(file)?;
    }
    Ok(hasher.finalize())
}

/// The hash of `data`.
#[cfg(test)]
pub(crate) fn bytes(data: &[u8]) -> Hash {
    blake3::hash(data)
}

/// A hash made as the bytes arrive, in pieces of any size. It gives the
/// hash that [`file`] gives for the same bytes.
#[derive(Clone, Default)]
pub(crate) struct Incremental {
    hasher: blake3::Hasher,
}

impl Incremental {
    pub(crate) fn new() -> Self {
        Self::default()
    }

    pub(crate) fn update(&mut self, data: &[u8]) {
        self.hasher.update(data);
    }

    /// The hash of the bytes so far. More bytes can follow.
    pub(crate) fn finish(&self) -> Hash {
        self.hasher.finalize()
    }
}

/// Bytes written through it go on to `inner` and into the hash.
pub(crate) struct Hashing<W> {
    inner: W,
    hash: Incremental,
}

impl<W: Write> Hashing<W> {
    pub(crate) fn new(inner: W) -> Self {
        Self { inner, hash: Incremental::new() }
    }

    pub(crate) fn finish(self) -> (W, Hash) {
        let hash = self.hash.finish();
        (self.inner, hash)
    }
}

impl<W: Write> Write for Hashing<W> {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        let n = self.inner.write(buf)?;
        self.hash.update(&buf[..n]);
        Ok(n)
    }

    fn flush(&mut self) -> io::Result<()> {
        self.inner.flush()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn incremental_hash_equals_the_whole_file_hash() {
        // The pieces have odd sizes that cross BLAKE3's chunk and block edges.
        let data: Vec<u8> = (0..1_234_567usize)
            .map(|i| (i * 31 % 251) as u8)
            .collect();
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("big.bin");
        std::fs::write(&path, &data).unwrap();
        let mut hash = Incremental::new();
        for piece in data.chunks(1000 + 7) {
            hash.update(piece);
        }
        // Both ways of reading a file: one thread, and mmap on the rayon pool.
        assert_eq!(hash.finish(), file(&path).unwrap());
        assert_eq!(hash.finish(), file_from(&path, 0).unwrap());
    }
}
