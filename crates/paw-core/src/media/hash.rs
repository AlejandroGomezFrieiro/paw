//! Content hashes of files: BLAKE3, the name of a source (see
//! `bench/media.md` for why this hash and the numbers behind the limits).
//!
//! Three ways to make the same hash: [`file`] for a file on disk (a big
//! file is memory-mapped and hashed on all cores), [`bytes`] for bytes in
//! memory, and [`Incremental`] for bytes that pass by while something else
//! reads or writes them (an import that decodes, a recording that writes).

use std::fs::File;
use std::io::{self, Read, Write};
use std::path::Path;

pub use blake3::Hash;

/// From this size a file is memory-mapped and hashed on the rayon pool.
/// Under it, one thread reads as fast as the disk and the page cache give
/// (a 53 MB file was no faster on 8 threads: bench/media.md).
pub const PARALLEL_MIN: u64 = 64 << 20;

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
pub fn bytes(data: &[u8]) -> Hash {
    blake3::hash(data)
}

/// The hash of everything `source` gives.
pub fn reader(source: impl Read) -> io::Result<Hash> {
    let mut hasher = blake3::Hasher::new();
    hasher.update_reader(source)?;
    Ok(hasher.finalize())
}

/// A hash made as the bytes arrive, in pieces of any size. It gives the
/// hash that [`file`] gives for the same bytes.
#[derive(Clone, Default)]
pub struct Incremental {
    hasher: blake3::Hasher,
    len: u64,
}

impl Incremental {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn update(&mut self, data: &[u8]) {
        self.hasher.update(data);
        self.len += data.len() as u64;
    }

    /// The bytes given so far.
    pub fn len(&self) -> u64 {
        self.len
    }

    pub fn is_empty(&self) -> bool {
        self.len == 0
    }

    /// The hash of the bytes so far. More bytes can follow.
    pub fn finish(&self) -> Hash {
        self.hasher.finalize()
    }
}

/// Bytes written through it go on to `inner` and into the hash.
pub struct Hashing<W> {
    inner: W,
    hash: Incremental,
}

impl<W: Write> Hashing<W> {
    pub fn new(inner: W) -> Self {
        Self { inner, hash: Incremental::new() }
    }

    pub fn finish(self) -> (W, Hash) {
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
