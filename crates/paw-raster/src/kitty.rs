//! Images in a terminal by the kitty graphics protocol: what is sent to
//! show pixels, move them and take them away, written into a buffer for
//! the caller to send inside its synchronized update. No terminal is
//! needed to use it, so what it writes can be checked byte for byte.
//!
//! Images are kept in the terminal by a hash of their pixels: pixels sent
//! once are placed again for nothing, wherever and as often as they are
//! wanted. Placements are direct (not Unicode placeholders, which WezTerm
//! does not draw), at the image's natural size, with a source rectangle
//! for the part that shows. Every command after the startup probe asks for
//! no answer (`q=2`): answers would arrive among the keys.
#![expect(clippy::cast_lossless, reason = "debt: pay down")]
#![cfg_attr(test, expect(clippy::cast_possible_truncation, reason = "debt: pay down"))]

use std::collections::HashMap;
use std::io::Write;

use base64::Engine;
use base64::engine::general_purpose::STANDARD as B64;
use rustix::shm;

/// How pixels reach the terminal: a shared memory object or a temporary
/// file it reads (and removes) when it runs on this machine, or inline,
/// compressed, when it is across a connection.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Transfer {
    Shm,
    File,
    Zlib,
}

/// How many bytes of pixels to keep in the terminal before the least
/// recently shown images are deleted.
pub const BUDGET: usize = 64 << 20;

struct Image {
    id: u32,
    bytes: usize,
    used: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Place {
    pub image: u32,
    /// The part of the image shown, in its pixels: x, y, width, height.
    pub src: [u32; 4],
    /// The cell its top left corner is in, from 0.
    pub at: (u16, u16),
    /// How far into that cell, in pixels.
    pub offset: (u16, u16),
    pub z: i32,
}

struct Placed {
    place: Place,
    pid: u32,
    frame: u64,
}

/// What the terminal holds: images and where they are placed.
pub struct Images {
    pub transfer: Transfer,
    /// How many bytes of pixels to keep in the terminal ([`BUDGET`]).
    pub budget: usize,
    images: HashMap<u64, Image>,
    held: usize,
    next_id: u32,
    placed: HashMap<String, Placed>,
    next_pid: u32,
    frame: u64,
    /// Names for shared memory objects and files: this process's own.
    serial: u64,
    /// Shared memory objects and files sent, with when: the terminal
    /// removes them as it reads them, and what it has not read in two
    /// seconds (or by the end) is removed here.
    sent: Vec<(Sent, std::time::Instant)>,
}

enum Sent {
    Shm(String),
    File(std::path::PathBuf),
}

impl Sent {
    fn remove(&self) {
        match self {
            Sent::Shm(name) => {
                let _ = shm::unlink(name.as_str());
            }
            Sent::File(path) => {
                let _ = std::fs::remove_file(path);
            }
        }
    }
}

/// The hash images are kept by: of the size and every pixel.
pub fn hash(rgba: &[u8], width: u32, height: u32) -> u64 {
    // FNV-1a over 8 bytes at a time: fast, and plenty to tell images apart.
    let mut h: u64 = 0xcbf2_9ce4_8422_2325 ^ ((width as u64) << 32 | height as u64);
    let mut chunks = rgba.chunks_exact(8);
    for chunk in &mut chunks {
        h ^= u64::from_le_bytes(chunk.try_into().expect("the slice has the length of the array"));
        h = h.wrapping_mul(0x0000_0100_0000_01b3);
    }
    for b in chunks.remainder() {
        h ^= *b as u64;
        h = h.wrapping_mul(0x0000_0100_0000_01b3);
    }
    h
}

/// The command that deletes every image and placement of this program.
pub const DELETE_ALL: &[u8] = b"\x1b_Ga=d,d=A,q=2\x1b\\";

impl Images {
    pub fn new(transfer: Transfer) -> Self {
        Self {
            transfer,
            budget: BUDGET,
            images: HashMap::new(),
            held: 0,
            next_id: 1,
            placed: HashMap::new(),
            next_pid: 1,
            frame: 0,
            serial: 0,
            sent: Vec::new(),
        }
    }

    /// Start a frame: what is not placed again before [`Images::end`] is taken away.
    pub fn begin(&mut self) {
        self.frame += 1;
    }

    /// The id of an image of these pixels (straight RGBA), sending them
    /// when the terminal does not have them yet.
    pub fn image(&mut self, out: &mut Vec<u8>, rgba: &[u8], width: u32, height: u32) -> u32 {
        let key = hash(rgba, width, height);
        if let Some(image) = self.images.get_mut(&key) {
            image.used = self.frame;
            return image.id;
        }
        let id = self.next_id;
        self.next_id = self.next_id.wrapping_add(1).max(1);
        self.transmit(out, id, rgba, width, height);
        self.images.insert(key, Image { id, bytes: rgba.len(), used: self.frame });
        self.held += rgba.len();
        id
    }

    fn transmit(&mut self, out: &mut Vec<u8>, id: u32, rgba: &[u8], width: u32, height: u32) {
        self.serial += 1;
        let name = format!("paw-tty-graphics-protocol-{}-{}", std::process::id(), self.serial);
        let now = std::time::Instant::now();
        let sent = match self.transfer {
            Transfer::Shm => write_shm(&format!("/{name}"), rgba).map(|_| {
                self.sent.push((Sent::Shm(format!("/{name}")), now));
                ('s', format!("/{name}"))
            }),
            Transfer::File => {
                let path = std::env::temp_dir().join(&name);
                std::fs::write(&path, rgba).map(|_| {
                    self.sent.push((Sent::File(path.clone()), now));
                    ('t', path.display().to_string())
                })
            }
            Transfer::Zlib => Err(std::io::Error::other("inline")),
        };
        match sent {
            Ok((medium, path)) => {
                let _ = write!(
                    out,
                    "\x1b_Ga=t,f=32,t={medium},i={id},s={width},v={height},S={},q=2;{}\x1b\\",
                    rgba.len(),
                    B64.encode(path)
                );
            }
            // When the file cannot be written, the pixels go inline.
            Err(_) => inline(out, id, rgba, width, height),
        }
    }

    /// The id of an image the terminal holds, by [`hash`] of its pixels.
    pub fn known(&mut self, key: u64) -> Option<u32> {
        let image = self.images.get_mut(&key)?;
        image.used = self.frame;
        Some(image.id)
    }

    /// Show part of an image somewhere, under a name the caller keeps for
    /// it: placing a name again moves it, or changes what it shows.
    /// `again` places it anew even when nothing changed, for a terminal
    /// that has lost it (WezTerm drops an image from cells written over).
    pub fn place(&mut self, out: &mut Vec<u8>, name: &str, place: Place, again: bool) {
        let frame = self.frame;
        if let Some(placed) = self.placed.get_mut(name) {
            placed.frame = frame;
            if placed.place == place && !again {
                return;
            }
            // Placing the same placement of the same image again moves it;
            // another image's placement is a different one.
            if placed.place.image != place.image || again {
                delete_placement(out, placed.place.image, placed.pid);
            }
            placed.place = place;
            write_place(out, place, placed.pid);
            return;
        }
        let pid = self.next_pid;
        self.next_pid = self.next_pid.wrapping_add(1).max(1);
        write_place(out, place, pid);
        self.placed.insert(name.to_string(), Placed { place, pid, frame });
    }

    /// End a frame: take away what was not placed in it, and delete images
    /// beyond the budget that nothing shows.
    pub fn end(&mut self, out: &mut Vec<u8>) {
        let frame = self.frame;
        self.sent.retain(|(sent, when)| {
            let old = when.elapsed() > std::time::Duration::from_secs(2);
            if old {
                sent.remove();
            }
            !old
        });
        self.placed.retain(|_, placed| {
            let keep = placed.frame == frame;
            if !keep {
                delete_placement(out, placed.place.image, placed.pid);
            }
            keep
        });
        if self.held <= self.budget {
            return;
        }
        let shown: std::collections::HashSet<u32> = self.placed.values().map(|p| p.place.image).collect();
        let mut old: Vec<(u64, u64)> = self
            .images
            .iter()
            .filter(|(_, image)| !shown.contains(&image.id))
            .map(|(key, image)| (image.used, *key))
            .collect();
        old.sort_unstable();
        for (_, key) in old {
            if self.held <= self.budget {
                break;
            }
            if let Some(image) = self.images.remove(&key) {
                self.held -= image.bytes;
                let _ = write!(out, "\x1b_Ga=d,d=I,i={},q=2\x1b\\", image.id);
            }
        }
    }

    /// Delete everything: on a change of size, and when leaving.
    pub fn clear(&mut self, out: &mut Vec<u8>) {
        if !self.images.is_empty() || !self.placed.is_empty() {
            out.extend_from_slice(DELETE_ALL);
        }
        self.images.clear();
        self.placed.clear();
        self.held = 0;
        for (sent, _) in self.sent.drain(..) {
            sent.remove();
        }
    }

    /// Whether anything is placed under this name now.
    pub fn is_placed(&self, name: &str) -> bool {
        self.placed.contains_key(name)
    }
}

fn write_place(out: &mut Vec<u8>, place: Place, pid: u32) {
    let [x, y, w, h] = place.src;
    let (col, row) = place.at;
    // The cursor says where; `C=1` leaves it where it was put.
    let _ = write!(out, "\x1b[{};{}H\x1b_Ga=p,i={},p={pid},x={x},y={y},w={w},h={h}", row + 1, col + 1, place.image);
    if place.offset != (0, 0) {
        let _ = write!(out, ",X={},Y={}", place.offset.0, place.offset.1);
    }
    let _ = write!(out, ",z={},C=1,q=2\x1b\\", place.z);
}

fn delete_placement(out: &mut Vec<u8>, image: u32, pid: u32) {
    let _ = write!(out, "\x1b_Ga=d,d=i,i={image},p={pid},q=2\x1b\\");
}

/// Pixels sent in the command itself, compressed, in chunks of the size
/// the protocol allows.
pub fn inline(out: &mut Vec<u8>, id: u32, rgba: &[u8], width: u32, height: u32) {
    let mut z = flate2::write::ZlibEncoder::new(Vec::new(), flate2::Compression::fast());
    let _ = z.write_all(rgba);
    let packed = z.finish().unwrap_or_default();
    let encoded = B64.encode(packed);
    let chunks: Vec<&[u8]> = encoded.as_bytes().chunks(4096).collect();
    for (i, chunk) in chunks.iter().enumerate() {
        let more = u8::from(i + 1 < chunks.len());
        if i == 0 {
            let _ = write!(out, "\x1b_Ga=t,f=32,o=z,i={id},s={width},v={height},q=2,m={more};");
        } else {
            let _ = write!(out, "\x1b_Gm={more},q=2;");
        }
        out.extend_from_slice(chunk);
        out.extend_from_slice(b"\x1b\\");
    }
}

/// A POSIX shared memory object holding `bytes`, for the terminal to read
/// and unlink.
pub fn write_shm(name: &str, bytes: &[u8]) -> std::io::Result<()> {
    let flags = shm::OFlags::CREATE | shm::OFlags::RDWR | shm::OFlags::EXCL;
    let fd = shm::open(name, flags, shm::Mode::from_raw_mode(0o600))?;
    // Written through the descriptor rather than a memory map: the same
    // bytes and size, with no unsafe code.
    let mut file = std::fs::File::from(fd);
    let written = file.set_len(bytes.len() as u64).and_then(|()| file.write_all(bytes));
    if written.is_err() {
        let _ = shm::unlink(name);
    }
    written
}

/// The commands of the startup probe, which do want answers: whether the
/// terminal draws images at all (`i=31`), and whether it can read this
/// process's shared memory (`i=32`) and temporary files (`i=33`). Each
/// answers `ESC _ G i=<id> ; OK ESC \` or an error.
pub fn probe(out: &mut Vec<u8>) {
    let pixel = [255u8, 0, 0, 255];
    let _ = write!(out, "\x1b_Gi=31,s=1,v=1,a=q,t=d,f=32;{}\x1b\\", B64.encode(pixel));
    let name = format!("/paw-tty-graphics-protocol-{}-probe", std::process::id());
    if write_shm(&name, &pixel).is_ok() {
        let _ = write!(out, "\x1b_Gi=32,s=1,v=1,a=q,t=s,f=32;{}\x1b\\", B64.encode(&name));
    }
    let path = std::env::temp_dir().join(format!("paw-tty-graphics-protocol-{}-probe", std::process::id()));
    if std::fs::write(&path, pixel).is_ok() {
        let _ = write!(out, "\x1b_Gi=33,s=1,v=1,a=q,t=t,f=32;{}\x1b\\", B64.encode(path.display().to_string()));
    }
}

/// Remove what the probe left behind, when the terminal did not.
pub fn probe_done() {
    let name = format!("/paw-tty-graphics-protocol-{}-probe", std::process::id());
    let _ = shm::unlink(name);
    let path = std::env::temp_dir().join(format!("paw-tty-graphics-protocol-{}-probe", std::process::id()));
    let _ = std::fs::remove_file(path);
}

/// The answers to [`probe`] among what the terminal sent: whether images
/// work, and the best way to send them.
pub fn probe_answers(reply: &[u8]) -> Option<Transfer> {
    let text = String::from_utf8_lossy(reply);
    let ok = |id: u32| text.contains(&format!("\x1b_Gi={id};OK"));
    if !ok(31) {
        return None;
    }
    Some(if ok(32) {
        Transfer::Shm
    } else if ok(33) {
        Transfer::File
    } else {
        Transfer::Zlib
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn text(out: &[u8]) -> String {
        String::from_utf8_lossy(out).into_owned()
    }

    #[test]
    fn pixels_sent_once_are_placed_again_for_nothing() {
        let mut images = Images::new(Transfer::Zlib);
        let mut out = Vec::new();
        images.begin();
        let red = [255u8, 0, 0, 255].repeat(4);
        let id = images.image(&mut out, &red, 2, 2);
        let sent = text(&out);
        assert!(sent.starts_with("\x1b_Ga=t,f=32,o=z,i=1,s=2,v=2,q=2,m=0;"), "{sent:?}");
        assert!(sent.ends_with("\x1b\\"));
        out.clear();
        assert_eq!(images.image(&mut out, &red, 2, 2), id);
        assert!(out.is_empty(), "the same pixels are not sent again");
        let blue = [0u8, 0, 255, 255].repeat(4);
        assert_eq!(images.image(&mut out, &blue, 2, 2), 2);
    }

    #[test]
    fn a_placement_is_written_once_moved_in_place_and_taken_away_when_not_wanted() {
        let mut images = Images::new(Transfer::Zlib);
        let mut out = Vec::new();
        images.begin();
        let place = Place { image: 7, src: [0, 0, 20, 40], at: (3, 1), offset: (0, 0), z: 0 };
        images.place(&mut out, "notation/0", place, false);
        assert_eq!(text(&out), "\x1b[2;4H\x1b_Ga=p,i=7,p=1,x=0,y=0,w=20,h=40,z=0,C=1,q=2\x1b\\");
        images.end(&mut out);
        out.clear();

        // The same again: nothing to say.
        images.begin();
        images.place(&mut out, "notation/0", place, false);
        assert!(out.is_empty());
        // Moved: the same placement placed again.
        let moved = Place { at: (5, 1), offset: (3, 4), ..place };
        images.place(&mut out, "notation/0", moved, false);
        assert_eq!(text(&out), "\x1b[2;6H\x1b_Ga=p,i=7,p=1,x=0,y=0,w=20,h=40,X=3,Y=4,z=0,C=1,q=2\x1b\\");
        out.clear();
        // Another image under the name: the old placement goes first.
        images.place(&mut out, "notation/0", Place { image: 8, ..moved }, false);
        assert_eq!(
            text(&out),
            "\x1b_Ga=d,d=i,i=7,p=1,q=2\x1b\\\x1b[2;6H\x1b_Ga=p,i=8,p=1,x=0,y=0,w=20,h=40,X=3,Y=4,z=0,C=1,q=2\x1b\\"
        );
        out.clear();
        // Written over in a terminal that drops it: placed anew.
        images.place(&mut out, "notation/0", Place { image: 8, ..moved }, true);
        assert!(text(&out).starts_with("\x1b_Ga=d,d=i,i=8,p=1,q=2\x1b\\\x1b[2;6H"));
        images.end(&mut out);
        out.clear();

        // A frame without it takes it away.
        images.begin();
        images.end(&mut out);
        assert_eq!(text(&out), "\x1b_Ga=d,d=i,i=8,p=1,q=2\x1b\\");
        assert!(!images.is_placed("notation/0"));
    }

    #[test]
    fn images_beyond_the_budget_are_deleted_oldest_first_unless_shown() {
        let mut images = Images::new(Transfer::Zlib);
        let mut out = Vec::new();
        images.budget = 100;
        let big = 64;
        let a = vec![1u8; big];
        let b = vec![2u8; big];
        images.begin();
        let first = images.image(&mut out, &a, 1, (big / 4) as u32);
        images.end(&mut out);
        images.begin();
        let second = images.image(&mut out, &b, 1, (big / 4) as u32);
        images.place(&mut out, "s", Place { image: second, src: [0, 0, 1, 1], at: (0, 0), offset: (0, 0), z: 0 }, false);
        out.clear();
        images.end(&mut out);
        assert_eq!(text(&out), format!("\x1b_Ga=d,d=I,i={first},q=2\x1b\\"));
    }

    #[test]
    fn a_temporary_file_is_named_for_the_protocol_and_sent_by_its_path() {
        let mut images = Images::new(Transfer::File);
        let mut out = Vec::new();
        images.begin();
        images.image(&mut out, &[9u8; 16], 2, 2);
        let sent = text(&out);
        assert!(sent.starts_with("\x1b_Ga=t,f=32,t=t,i=1,s=2,v=2,S=16,q=2;"), "{sent}");
        let encoded = sent.split(';').nth(1).unwrap().trim_end_matches("\x1b\\");
        let path = String::from_utf8(B64.decode(encoded).unwrap()).unwrap();
        assert!(path.contains("tty-graphics-protocol"), "kitty reads only files so named");
        assert_eq!(std::fs::read(&path).unwrap(), vec![9u8; 16]);
        // A terminal that never read it: removed when everything goes.
        images.clear(&mut out);
        assert!(!std::path::Path::new(&path).exists());
    }

    #[test]
    fn inline_pixels_come_in_chunks_that_decompress_to_them() {
        let mut seed = 7u32;
        let pixels: Vec<u8> = (0..40_000)
            .map(|_| {
                seed = seed.wrapping_mul(1_103_515_245).wrapping_add(12345);
                (seed >> 16) as u8
            })
            .collect();
        let mut out = Vec::new();
        inline(&mut out, 5, &pixels, 100, 100);
        let sent = text(&out);
        let commands: Vec<&str> = sent.split("\x1b\\").filter(|s| !s.is_empty()).collect();
        assert!(commands.len() > 1, "more than one chunk");
        assert!(commands[0].starts_with("\x1b_Ga=t,f=32,o=z,i=5,s=100,v=100,q=2,m=1;"));
        assert!(commands.last().unwrap().starts_with("\x1b_Gm=0,q=2;"));
        let joined: String = commands.iter().map(|c| c.split(';').nth(1).unwrap()).collect();
        let packed = B64.decode(joined).unwrap();
        let mut unpacked = Vec::new();
        std::io::Read::read_to_end(&mut flate2::read::ZlibDecoder::new(&packed[..]), &mut unpacked).unwrap();
        assert_eq!(unpacked, pixels);
    }

    #[test]
    fn the_probe_answers_choose_how_to_send() {
        assert_eq!(probe_answers(b"\x1b[?62;22c"), None, "no answer: no images");
        assert_eq!(probe_answers(b"\x1b_Gi=31;OK\x1b\\\x1b_Gi=32;OK\x1b\\"), Some(Transfer::Shm));
        assert_eq!(
            probe_answers(b"\x1b_Gi=31;OK\x1b\\\x1b_Gi=32;EBADF:x\x1b\\\x1b_Gi=33;OK\x1b\\"),
            Some(Transfer::File)
        );
        assert_eq!(probe_answers(b"\x1b_Gi=31;OK\x1b\\\x1b_Gi=33;ENOENT\x1b\\"), Some(Transfer::Zlib));
    }
}
