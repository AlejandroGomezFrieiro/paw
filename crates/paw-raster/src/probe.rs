//! What a terminal says about itself when asked at startup: its colours
//! (`OSC 10`/`11`), its cell size (`CSI 16 t`), its name (XTVERSION),
//! whether it draws images (the graphics queries of [`crate::kitty::probe`]),
//! whether it reports the pointer in pixels (DECRQM for mode 1016), ended
//! by the answer to DA1, which every terminal gives after the others.
//! (After the measuring spike's `term.rs`.)
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]

use crate::kitty::Transfer;

/// Everything asked at once, before anything else reads the input.
pub fn queries(out: &mut Vec<u8>) {
    out.extend_from_slice(b"\x1b]10;?\x1b\\\x1b]11;?\x1b\\\x1b[16t\x1b[>q\x1b[?1016$p");
    crate::kitty::probe(out);
    out.extend_from_slice(b"\x1b[c");
}

/// One answer, or a byte that is not one.
#[derive(Debug, PartialEq)]
pub enum Answer {
    Byte(u8),
    /// The answer to DA1, the end of the probe.
    Da1,
    /// `CSI 6 ; height ; width t`: the cell size in pixels.
    Cell(u16, u16),
    /// An `OSC 10`/`11` colour.
    Color(u32, (u8, u8, u8)),
    /// A graphics answer: the image id and the message.
    Graphics(u32, String),
    /// XTVERSION: the terminal's name and version.
    Version(String),
    /// DECRQM: a mode and whether it is known (1 set, 2 reset; 0 unknown).
    Mode(u32, u32),
}

/// Take what is complete off the front of `buf`. A sequence cut short
/// stays for the next read.
pub fn parse(buf: &mut Vec<u8>) -> Vec<Answer> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < buf.len() {
        if buf[i] != 0x1b {
            out.push(Answer::Byte(buf[i]));
            i += 1;
            continue;
        }
        let Some(&kind) = buf.get(i + 1) else { break };
        let body = i + 2;
        // Where the sequence ends (exclusive) and where its text ends.
        let end = match kind {
            b'[' => buf[body..]
                .iter()
                .position(|b| (0x40..=0x7e).contains(b))
                .map(|p| (body + p + 1, body + p + 1)),
            b']' | b'_' | b'P' => (body..buf.len()).find_map(|j| match buf[j] {
                0x07 if kind == b']' => Some((j + 1, j)),
                0x1b if buf.get(j + 1) == Some(&b'\\') => Some((j + 2, j)),
                0x1b if j + 1 < buf.len() => Some((j, j)),
                _ => None,
            }),
            _ => Some((i + 2, i + 2)),
        };
        let Some((next, text_end)) = end else { break };
        let text = String::from_utf8_lossy(&buf[body..text_end.max(body)]).into_owned();
        match kind {
            b'[' if text.starts_with('?') && text.ends_with('c') => out.push(Answer::Da1),
            b'[' if text.starts_with('?') && text.ends_with("$y") => {
                let n: Vec<u32> = text[1..text.len() - 2].split(';').filter_map(|v| v.parse().ok()).collect();
                if let [mode, state] = n[..] {
                    out.push(Answer::Mode(mode, state));
                }
            }
            b'[' if text.starts_with("6;") && text.ends_with('t') => {
                let n: Vec<u16> = text[2..text.len() - 1].split(';').filter_map(|v| v.parse().ok()).collect();
                if let [h, w] = n[..] {
                    out.push(Answer::Cell(w, h));
                }
            }
            b']' => {
                if let Some((n, rgb)) = text.split_once(";rgb:") {
                    let parts: Vec<u8> = rgb.split('/').filter_map(channel).collect();
                    if let (Ok(n), &[r, g, b]) = (n.parse(), &parts[..]) {
                        out.push(Answer::Color(n, (r, g, b)));
                    }
                }
            }
            b'_' => {
                if let Some(rest) = text.strip_prefix('G') {
                    let (keys, msg) = rest.split_once(';').unwrap_or((rest, ""));
                    let id = keys.split(',').find_map(|k| k.strip_prefix("i=")?.parse().ok()).unwrap_or(0);
                    out.push(Answer::Graphics(id, msg.to_string()));
                }
            }
            b'P' => {
                if let Some(v) = text.strip_prefix(">|") {
                    out.push(Answer::Version(v.to_string()));
                }
            }
            _ => {}
        }
        i = next;
    }
    buf.drain(..i);
    out
}

/// One channel of an X colour, `h` to `hhhh` hex digits, as a byte.
fn channel(s: &str) -> Option<u8> {
    let v = u32::from_str_radix(s, 16).ok()?;
    let max = (1u32 << (4 * s.len() as u32)) - 1;
    Some(((v * 255 + max / 2) / max) as u8)
}

/// What the probe found.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Probe {
    pub fg: Option<(u8, u8, u8)>,
    pub bg: Option<(u8, u8, u8)>,
    pub cell: Option<(u16, u16)>,
    /// How to send images, when the terminal draws them.
    pub transfer: Option<Transfer>,
    pub version: Option<String>,
    pub pixel_mouse: bool,
    /// The DA1 answer came: the terminal answered everything it would.
    pub done: bool,
}

impl Probe {
    /// Take in answers as they come.
    pub fn hear(&mut self, answers: Vec<Answer>, graphics: &mut Vec<u8>) {
        for answer in answers {
            match answer {
                Answer::Da1 => self.done = true,
                Answer::Cell(w, h) if w > 0 && h > 0 => self.cell = Some((w, h)),
                Answer::Color(10, c) => self.fg = Some(c),
                Answer::Color(11, c) => self.bg = Some(c),
                Answer::Graphics(id, msg) => {
                    graphics.extend_from_slice(format!("\x1b_Gi={id};{msg}\x1b\\").as_bytes());
                    self.transfer = crate::kitty::probe_answers(graphics);
                }
                Answer::Version(v) => self.version = Some(v),
                Answer::Mode(1016, state) => self.pixel_mouse = state == 1 || state == 2,
                _ => {}
            }
        }
    }

    /// Whether the terminal itself puts images above text and keeps them
    /// when text is written under them: herdr's emulator (libghostty),
    /// kitty and Ghostty do; WezTerm does not. Elsewhere the overlay is
    /// baked into the page.
    pub fn layered(&self) -> bool {
        self.version.as_deref().is_some_and(|v| {
            let v = v.to_ascii_lowercase();
            v.contains("ghostty") || v.contains("kitty")
        })
    }

    /// Whether the terminal draws text above an image placed under it (a
    /// negative z), over cells of any background, as the kitty protocol
    /// says: kitty, Ghostty (herdr) and WezTerm do. Konsole lets a cell's
    /// coloured background hide the image; others are not known to work.
    pub fn under(&self) -> bool {
        self.layered() || self.version.as_deref().is_some_and(|v| v.to_ascii_lowercase().contains("wezterm"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn answers_and_keys_are_told_apart() {
        let mut buf = b"1\x1b[?62;22c\x1b[6;27;13tq\x1b]11;rgb:1e1e/1e1e/2e2e\x1b\\\x1b_Gi=31;OK\x1b\\\x1bP>|libghostty 1.2\x1b\\\x1b[?1016;2$y".to_vec();
        assert_eq!(
            parse(&mut buf),
            vec![
                Answer::Byte(b'1'),
                Answer::Da1,
                Answer::Cell(13, 27),
                Answer::Byte(b'q'),
                Answer::Color(11, (0x1e, 0x1e, 0x2e)),
                Answer::Graphics(31, "OK".into()),
                Answer::Version("libghostty 1.2".into()),
                Answer::Mode(1016, 2),
            ]
        );
        assert!(buf.is_empty());
    }

    #[test]
    fn a_sequence_cut_short_waits_for_the_rest() {
        let mut buf = b"2\x1b]10;rgb:cd".to_vec();
        assert_eq!(parse(&mut buf), vec![Answer::Byte(b'2')]);
        buf.extend_from_slice(b"cd/d6d6/f4f4\x07");
        assert_eq!(parse(&mut buf), vec![Answer::Color(10, (0xcd, 0xd6, 0xf4))]);
    }

    #[test]
    fn what_the_terminal_said_decides_how_it_is_drawn_on() {
        let mut probe = Probe::default();
        let mut graphics = Vec::new();
        let mut buf = b"\x1bP>|libghostty 1.2\x1b\\\x1b_Gi=31;OK\x1b\\\x1b_Gi=32;OK\x1b\\\x1b[?1016;2$y\x1b[6;27;13t\x1b[?62;22c".to_vec();
        probe.hear(parse(&mut buf), &mut graphics);
        assert!(probe.done && probe.layered() && probe.under() && probe.pixel_mouse);
        assert_eq!((probe.transfer, probe.cell), (Some(Transfer::Shm), Some((13, 27))));

        // WezTerm: images, by file; no layering; pixel mouse not known.
        let mut probe = Probe::default();
        let mut graphics = Vec::new();
        let mut buf = b"\x1bP>|WezTerm 20240203\x1b\\\x1b_Gi=31;OK\x1b\\\x1b_Gi=33;OK\x1b\\\x1b[?1016;0$y\x1b[?65;4c".to_vec();
        probe.hear(parse(&mut buf), &mut graphics);
        assert!(!probe.layered() && !probe.pixel_mouse);
        assert!(probe.under(), "text over images under it");
        assert_eq!(probe.transfer, Some(Transfer::File));

        // tmux: nothing but DA1.
        let mut probe = Probe::default();
        probe.hear(parse(&mut b"\x1b[?1;2c".to_vec()), &mut Vec::new());
        assert!(probe.done && probe.transfer.is_none());
    }

    #[test]
    fn the_queries_end_with_da1() {
        let mut out = Vec::new();
        queries(&mut out);
        crate::kitty::probe_done();
        let text = String::from_utf8_lossy(&out);
        assert!(text.starts_with("\x1b]10;?\x1b\\"));
        assert!(text.contains("\x1b_Gi=31,s=1,v=1,a=q,t=d,f=32;"));
        assert!(text.ends_with("\x1b[c"));
    }
}
