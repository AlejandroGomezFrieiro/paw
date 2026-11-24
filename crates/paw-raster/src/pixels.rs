//! Pictures of pixels (`paw.canvas.image`): a frame of a video, a
//! spectrogram, a photo. A drawing names one by its content key in an `i`
//! operation, and a frontend draws it from the pixels kept here under that
//! key.
//!
//! The key is made from the pixels, so a key always names the same
//! pixels: the store is one for the process, as the fonts' outlines are,
//! and any drawing can find a picture in it. The kernel keeps what views
//! make; the window keeps what it fetched from the kernel (`scene.blob`).
//! The pictures used last are kept, up to [`BUDGET`] bytes.
//!
//! A picture travels to a window as a blob: `{ "w": W, "h": H, "rgba":
//! base64 }`, its pixels as straight RGBA, row by row.
#![expect(clippy::cast_lossless, reason = "debt: pay down")]
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::cast_precision_loss, reason = "debt: pay down")]
#![expect(clippy::cast_sign_loss, reason = "debt: pay down")]

use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

use base64::Engine as _;
use serde_json::{Value, json};
use tiny_skia::{IntSize, Pixmap};

use crate::Rgba;

/// How many bytes of pixels the store keeps before it forgets the
/// pictures used longest ago.
pub const BUDGET: usize = 256 << 20;

/// The largest width or height of a picture.
pub const MAX_SIDE: u32 = 8192;

/// Why bytes are not a picture.
#[derive(Debug, thiserror::Error, PartialEq)]
pub enum PictureError {
    #[error("an RGBA picture needs its width and height")]
    NoSize,
    #[error("a picture of {w}x{h} pixels is too big (at most {MAX_SIDE} on a side)")]
    TooBig { w: u32, h: u32 },
    #[error("a picture of {w}x{h} pixels in RGBA is {need} bytes, not {got}")]
    Length { w: u32, h: u32, need: usize, got: usize },
    #[error("not a PNG picture: {0}")]
    Png(String),
    #[error("unknown picture format `{0}` (rgba or png)")]
    Format(String),
}

const PNG_SIGNATURE: &[u8] = b"\x89PNG\r\n\x1a\n";

/// The pixels of `bytes`: PNG, or straight RGBA of `size` row by row.
/// `format` is `png` or `rgba`; without it, bytes that start as a PNG file
/// does are PNG.
pub fn decode(bytes: &[u8], format: Option<&str>, size: Option<(u32, u32)>) -> Result<Pixmap, PictureError> {
    let png = match format {
        Some("png") => true,
        Some("rgba") => false,
        Some(other) => return Err(PictureError::Format(other.to_string())),
        None => bytes.starts_with(PNG_SIGNATURE),
    };
    let pixmap = if png {
        Pixmap::decode_png(bytes).map_err(|e| PictureError::Png(e.to_string()))?
    } else {
        let (w, h) = size.ok_or(PictureError::NoSize)?;
        from_rgba(bytes, w, h)?
    };
    if pixmap.width() > MAX_SIDE || pixmap.height() > MAX_SIDE {
        return Err(PictureError::TooBig { w: pixmap.width(), h: pixmap.height() });
    }
    Ok(pixmap)
}

/// Straight RGBA, row by row, as a pixmap (premultiplied).
fn from_rgba(bytes: &[u8], w: u32, h: u32) -> Result<Pixmap, PictureError> {
    if w == 0 || h == 0 || w > MAX_SIDE || h > MAX_SIDE {
        return Err(PictureError::TooBig { w, h });
    }
    let need = w as usize * h as usize * 4;
    if bytes.len() != need {
        return Err(PictureError::Length { w, h, need, got: bytes.len() });
    }
    let mut data = bytes.to_vec();
    for px in data.chunks_exact_mut(4) {
        let a = px[3] as u32;
        if a != 255 {
            for c in &mut px[..3] {
                *c = ((*c as u32 * a + 127) / 255) as u8;
            }
        }
    }
    let size = IntSize::from_wh(w, h).ok_or(PictureError::TooBig { w, h })?;
    Pixmap::from_vec(data, size).ok_or(PictureError::TooBig { w, h })
}

struct Kept {
    pixmap: Arc<Pixmap>,
    used: u64,
}

#[derive(Default)]
struct Store {
    pictures: HashMap<String, Kept>,
    bytes: usize,
    tick: u64,
}

impl Store {
    fn insert(&mut self, key: String, pixmap: Arc<Pixmap>) {
        self.tick += 1;
        let used = self.tick;
        if let Some(kept) = self.pictures.get_mut(&key) {
            kept.used = used;
            return;
        }
        self.bytes += pixmap.data().len();
        self.pictures.insert(key.clone(), Kept { pixmap, used });
        // The pictures used longest ago go, never the one just made.
        while self.bytes > BUDGET && self.pictures.len() > 1 {
            let Some(oldest) = self.pictures.iter().filter(|(k, _)| **k != key).min_by_key(|(_, kept)| kept.used).map(|(k, _)| k.clone()) else { break };
            if let Some(gone) = self.pictures.remove(&oldest) {
                self.bytes -= gone.pixmap.data().len();
            }
        }
    }

    fn get(&mut self, key: &str) -> Option<Arc<Pixmap>> {
        self.tick += 1;
        let kept = self.pictures.get_mut(key)?;
        kept.used = self.tick;
        Some(kept.pixmap.clone())
    }
}

fn store() -> std::sync::MutexGuard<'static, Store> {
    static STORE: OnceLock<Mutex<Store>> = OnceLock::new();
    // A panic while it was held leaves a store that is still whole.
    STORE.get_or_init(Mutex::default).lock().unwrap_or_else(|e| e.into_inner())
}

/// The content key of a picture's pixels.
pub fn key_of(pixmap: &Pixmap) -> String {
    format!("img:{:016x}", crate::kitty::hash(pixmap.data(), pixmap.width(), pixmap.height()))
}

/// Keep a picture: its content key, which drawings name it by.
pub fn keep(pixmap: Pixmap) -> String {
    let key = key_of(&pixmap);
    store().insert(key.clone(), Arc::new(pixmap));
    key
}

/// Keep a picture by the key another process gave it (the window, with
/// what the kernel sent).
pub fn keep_as(key: &str, pixmap: Pixmap) {
    store().insert(key.to_string(), Arc::new(pixmap));
}

/// The picture kept under `key`, if it still is.
pub fn get(key: &str) -> Option<Arc<Pixmap>> {
    store().get(key)
}

/// Whether a key names a picture of pixels, not a drawing.
pub fn is_key(key: &str) -> bool {
    key.starts_with("img:")
}

/// A picture as it travels to a window: its size and its pixels as
/// straight RGBA in base64.
pub fn to_blob(pixmap: &Pixmap) -> Value {
    let rgba = crate::straight_rgba(pixmap);
    json!({ "w": pixmap.width(), "h": pixmap.height(), "rgba": base64::engine::general_purpose::STANDARD.encode(rgba) })
}

/// A picture from what [`to_blob`] made.
pub fn from_blob(blob: &Value) -> Option<Pixmap> {
    let (w, h) = (blob["w"].as_u64()? as u32, blob["h"].as_u64()? as u32);
    let rgba = base64::engine::general_purpose::STANDARD.decode(blob["rgba"].as_str()?).ok()?;
    from_rgba(&rgba, w, h).ok()
}

/// The keys of the pictures a drawing (`paw.canvas` operations) names.
pub fn keys_in(ops: &Value) -> impl Iterator<Item = &str> {
    ops.as_array().into_iter().flatten().filter(|op| op[0] == "i").filter_map(|op| op[5].as_str())
}

/// A picture in a terminal's cells, two pixels a cell (`▀`: the top half in
/// the cell's foreground, the bottom half in its background): the colour
/// of each half of each of `cols` by `rows` cells, row by row, top half
/// first, as the mean of the pixels under it. A half that is mostly
/// transparent is nothing: the terminal's own background shows there.
pub fn half_blocks(pixmap: &Pixmap, cols: u32, rows: u32) -> Vec<[Option<Rgba>; 2]> {
    let (w, h) = (pixmap.width() as f32, pixmap.height() as f32);
    let data = pixmap.data();
    let mean = |x0: f32, x1: f32, y0: f32, y1: f32| -> Option<Rgba> {
        let (px0, py0) = (x0.floor() as u32, y0.floor() as u32);
        let px1 = (x1.ceil() as u32).max(px0 + 1).min(pixmap.width());
        let py1 = (y1.ceil() as u32).max(py0 + 1).min(pixmap.height());
        let mut sum = [0u64; 4];
        let mut n = 0u64;
        for y in py0..py1 {
            for x in px0..px1 {
                let i = (y * pixmap.width() + x) as usize * 4;
                for (s, v) in sum.iter_mut().zip(&data[i..i + 4]) {
                    *s += *v as u64;
                }
                n += 1;
            }
        }
        let a = sum[3] / n.max(1);
        if a < 128 {
            return None;
        }
        // Premultiplied sums: divided by the alpha's, the straight colour.
        let c = |s: u64| ((s * 255 + sum[3] / 2) / sum[3].max(1)).min(255) as u8;
        Some(Rgba(c(sum[0]), c(sum[1]), c(sum[2]), 255))
    };
    let mut out = Vec::with_capacity((cols * rows) as usize);
    let (step_x, step_y) = (w / cols.max(1) as f32, h / (rows.max(1) * 2) as f32);
    for row in 0..rows {
        for col in 0..cols {
            let (x0, x1) = (col as f32 * step_x, (col + 1) as f32 * step_x);
            let top = (row * 2) as f32 * step_y;
            out.push([mean(x0, x1, top, top + step_y), mean(x0, x1, top + step_y, top + 2.0 * step_y)]);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    const RED: [u8; 4] = [255, 0, 0, 255];
    const GREEN: [u8; 4] = [0, 255, 0, 255];
    const BLUE: [u8; 4] = [0, 0, 255, 255];
    const CLEAR: [u8; 4] = [0, 0, 0, 0];

    #[test]
    fn a_two_by_two_picture_is_two_cells_of_half_blocks() {
        let rgba = [RED, GREEN, BLUE, CLEAR].concat();
        let pixmap = decode(&rgba, None, Some((2, 2))).unwrap();
        let cells = half_blocks(&pixmap, 2, 1);
        assert_eq!(cells, vec![[Some(Rgba(255, 0, 0, 255)), Some(Rgba(0, 0, 255, 255))], [Some(Rgba(0, 255, 0, 255)), None]]);
        // In one cell: each half the mean of its row.
        assert_eq!(half_blocks(&pixmap, 1, 1)[0][0], Some(Rgba(128, 128, 0, 255)));
    }

    #[test]
    fn a_picture_travels_as_a_blob_and_keeps_its_key() {
        let rgba = [RED, [10, 20, 30, 128], BLUE, CLEAR].concat();
        let pixmap = decode(&rgba, Some("rgba"), Some((2, 2))).unwrap();
        let back = from_blob(&to_blob(&pixmap)).unwrap();
        assert_eq!(key_of(&back), key_of(&pixmap));
        let png = pixmap.encode_png().unwrap();
        assert_eq!(key_of(&decode(&png, None, None).unwrap()), key_of(&pixmap), "a PNG of the same pixels");
        assert_eq!(decode(&rgba, None, Some((3, 2))).unwrap_err(), PictureError::Length { w: 3, h: 2, need: 24, got: 16 });
    }
}
