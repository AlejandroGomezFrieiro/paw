//! Numbers read from bytes at an offset: the saved states, the preset
//! files, the messages to and from a plugin and the LV2 atoms. Each read
//! gives `None` when the bytes are too short. None allocates, as the audio
//! thread reads messages with them.

/// `N` bytes from `at`, or `None` when the bytes end before.
#[inline]
fn array<const N: usize>(bytes: &[u8], at: usize) -> Option<[u8; N]> {
    bytes.get(at..at.checked_add(N)?)?.try_into().ok()
}

/// A little-endian `u32`: the length and port prefixes of paw's own
/// formats and of a VST3 state.
#[inline]
pub(crate) fn le_u32(bytes: &[u8], at: usize) -> Option<u32> {
    array(bytes, at).map(u32::from_le_bytes)
}

/// A little-endian `i32`, as a VST3 preset file has it.
#[inline]
pub(crate) fn le_i32(bytes: &[u8], at: usize) -> Option<i32> {
    array(bytes, at).map(i32::from_le_bytes)
}

/// A little-endian `i64`, as a VST3 preset file has it.
#[inline]
pub(crate) fn le_i64(bytes: &[u8], at: usize) -> Option<i64> {
    array(bytes, at).map(i64::from_le_bytes)
}

/// A little-endian `f64`, as the wire to a sandboxed plugin has it.
#[inline]
pub(crate) fn le_f64(bytes: &[u8], at: usize) -> Option<f64> {
    array(bytes, at).map(f64::from_le_bytes)
}

/// A `u32` in the byte order of the machine: the fields of an LV2 atom,
/// which the plugin writes in its own memory.
#[inline]
pub(crate) fn ne_u32(bytes: &[u8], at: usize) -> Option<u32> {
    array(bytes, at).map(u32::from_ne_bytes)
}

/// A `u64` in the byte order of the machine: an LV2 atom of a double or a
/// long.
#[inline]
pub(crate) fn ne_u64(bytes: &[u8], at: usize) -> Option<u64> {
    array(bytes, at).map(u64::from_ne_bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_read_past_the_end_gives_none() {
        let bytes = [1, 0, 0, 0, 2];
        assert_eq!(le_u32(&bytes, 0), Some(1));
        assert_eq!(le_u32(&bytes, 1), Some(0x0200_0000));
        assert_eq!(le_u32(&bytes, 2), None);
        assert_eq!(le_u32(&bytes, usize::MAX), None, "an offset that overflows");
    }
}
