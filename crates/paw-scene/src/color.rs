//! One colour as the wire and the theme files write it: `#rrggbb`, or
//! `#rrggbbaa` with an alpha.

use std::fmt;
use std::str::FromStr;

/// A colour of 8 bits a channel, with alpha (255 is opaque).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Rgba {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

impl Rgba {
    pub const fn rgb(r: u8, g: u8, b: u8) -> Rgba {
        Rgba { r, g, b, a: 255 }
    }
}

/// An opaque colour from its red, green and blue.
impl From<(u8, u8, u8)> for Rgba {
    fn from((r, g, b): (u8, u8, u8)) -> Rgba {
        Rgba::rgb(r, g, b)
    }
}

/// `#rrggbb`, or `#rrggbbaa` when the colour is not opaque, in lower case.
impl fmt::Display for Rgba {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "#{:02x}{:02x}{:02x}", self.r, self.g, self.b)?;
        if self.a != 255 {
            write!(f, "{:02x}", self.a)?;
        }
        Ok(())
    }
}

/// The text was not `#rrggbb` or `#rrggbbaa`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ParseRgbaError;

impl fmt::Display for ParseRgbaError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("a colour is #rrggbb or #rrggbbaa")
    }
}

impl std::error::Error for ParseRgbaError {}

/// `#rrggbb` or `#rrggbbaa` in either case; the `#` is optional.
impl FromStr for Rgba {
    type Err = ParseRgbaError;

    fn from_str(text: &str) -> Result<Rgba, ParseRgbaError> {
        let hex = text.strip_prefix('#').unwrap_or(text);
        if !matches!(hex.len(), 6 | 8) || !hex.bytes().all(|b| b.is_ascii_hexdigit()) {
            return Err(ParseRgbaError);
        }
        let channel = |at: usize| u8::from_str_radix(&hex[at..at + 2], 16).map_err(|_| ParseRgbaError);
        let a = if hex.len() == 8 { channel(6)? } else { 255 };
        Ok(Rgba { r: channel(0)?, g: channel(2)?, b: channel(4)?, a })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn text_and_colour_round_trip() {
        for text in ["#000000", "#ff8040", "#12ab34", "#ff000080"] {
            assert_eq!(text.parse::<Rgba>().unwrap().to_string(), text);
        }
        assert_eq!("E4E5E8".parse(), Ok(Rgba::rgb(0xe4, 0xe5, 0xe8)));
        for bad in ["", "#", "#fff", "#12345", "#1234567", "nonsense", "#gg0000", "#+f0000", "#ééé"] {
            assert_eq!(bad.parse::<Rgba>(), Err(ParseRgbaError), "{bad}");
        }
    }
}
