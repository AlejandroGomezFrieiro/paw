//! Byte codecs the file formats of extensions need (`paw.api.base64_*`,
//! `deflate`, `inflate`, `crc32`): one implementation each, for every
//! extension that reads zip, gzip, zlib or base64.

use std::io::{Read, Write};

use anyhow::{Result, bail};
use base64::Engine as _;
use base64::engine::general_purpose::{STANDARD, STANDARD_NO_PAD, URL_SAFE, URL_SAFE_NO_PAD};
use flate2::Compression;

pub(crate) fn base64_encode(data: &[u8], url: bool, pad: bool) -> String {
    match (url, pad) {
        (false, true) => STANDARD.encode(data),
        (false, false) => STANDARD_NO_PAD.encode(data),
        (true, true) => URL_SAFE.encode(data),
        (true, false) => URL_SAFE_NO_PAD.encode(data),
    }
}

pub(crate) fn base64_decode(text: &[u8]) -> Result<Vec<u8>> {
    let mut clean: Vec<u8> = text.iter().copied().filter(|b| !b.is_ascii_whitespace()).collect();
    let url = clean.iter().any(|b| *b == b'-' || *b == b'_');
    while clean.last() == Some(&b'=') {
        clean.pop();
    }
    let engine = if url { URL_SAFE_NO_PAD } else { STANDARD_NO_PAD };
    Ok(engine.decode(&clean)?)
}

pub(crate) fn deflate(data: &[u8], format: &str) -> Result<Vec<u8>> {
    let level = Compression::default();
    let out = match format {
        "raw" => {
            let mut e = flate2::write::DeflateEncoder::new(Vec::new(), level);
            e.write_all(data)?;
            e.finish()?
        }
        "zlib" => {
            let mut e = flate2::write::ZlibEncoder::new(Vec::new(), level);
            e.write_all(data)?;
            e.finish()?
        }
        "gzip" => {
            let mut e = flate2::write::GzEncoder::new(Vec::new(), level);
            e.write_all(data)?;
            e.finish()?
        }
        other => bail!("no compressed format `{other}`: raw, zlib or gzip"),
    };
    Ok(out)
}

/// The bytes `data` holds compressed as `format` says, and how many bytes
/// of `data` the compressed stream took (with its header and checksum):
/// what follows is not part of it.
pub(crate) fn inflate(data: &[u8], format: &str) -> Result<(Vec<u8>, usize)> {
    let mut out = Vec::new();
    let mut rest = data;
    match format {
        "raw" => flate2::bufread::DeflateDecoder::new(&mut rest).read_to_end(&mut out)?,
        "zlib" => flate2::bufread::ZlibDecoder::new(&mut rest).read_to_end(&mut out)?,
        "gzip" => flate2::bufread::GzDecoder::new(&mut rest).read_to_end(&mut out)?,
        other => bail!("no compressed format `{other}`: raw, zlib or gzip"),
    };
    Ok((out, data.len() - rest.len()))
}

pub(crate) fn crc32(data: &[u8]) -> u32 {
    let mut crc = flate2::Crc::new();
    crc.update(data);
    crc.sum()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn each_format_gives_back_what_it_was_given() {
        let data = b"paw paw paw paw paw, a song of bytes".repeat(20);
        // What follows the stream is not read as part of it.
        for format in ["raw", "zlib", "gzip"] {
            let packed = deflate(&data, format).unwrap();
            assert!(packed.len() < data.len(), "{format} compresses");
            let mut followed = packed.clone();
            followed.extend_from_slice(b"tail");
            assert_eq!(inflate(&followed, format).unwrap(), (data.clone(), packed.len()), "{format}");
        }
        assert!(inflate(b"not compressed", "zlib").is_err());
    }

    #[test]
    fn base64_reads_either_alphabet_with_or_without_padding() {
        let data = [0xfbu8, 0xff, 0xbf, 0x00, 0x41];
        assert_eq!(base64_encode(&data, false, true), "+/+/AEE=");
        assert_eq!(base64_encode(&data, true, false), "-_-_AEE");
        for text in ["+/+/AEE=", "-_-_AEE", "+/+/\nAEE"] {
            assert_eq!(base64_decode(text.as_bytes()).unwrap(), data, "{text}");
        }
        assert!(base64_decode(b"*not*").is_err());
    }

    #[test]
    fn crc32_is_the_one_zip_uses() {
        assert_eq!(crc32(b"123456789"), 0xcbf4_3926);
    }
}
