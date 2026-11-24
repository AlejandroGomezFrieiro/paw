//! Places in a text as LSP gives them (a line, and a column in UTF-16 code
//! units) and as chain-syntax gives them (a byte offset).
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]

use lsp_types::{Position, Range};

/// The LSP position of the byte `offset` of `text`. An offset past the end
/// is the end of the text.
pub(crate) fn position(text: &str, offset: usize) -> Position {
    let offset = floor_char_boundary(text, offset.min(text.len()));
    let before = &text[..offset];
    let line_start = before.rfind('\n').map_or(0, |at| at + 1);
    let line = before.matches('\n').count() as u32;
    let character = before[line_start..].encode_utf16().count() as u32;
    Position { line, character }
}

/// The byte offset of an LSP position in `text`. A line past the end is the
/// end of the text, and a column past the end of its line is the end of
/// that line.
pub(crate) fn offset(text: &str, position: Position) -> usize {
    let Some(line_start) = line_start(text, position.line) else {
        return text.len();
    };
    let line = &text[line_start..];
    let line = &line[..line.find('\n').unwrap_or(line.len())];
    let mut units = 0;
    for (at, c) in line.char_indices() {
        if units >= position.character {
            return line_start + at;
        }
        units += c.len_utf16() as u32;
    }
    line_start + line.len()
}

/// The range of the bytes `start..end` of `text`.
pub(crate) fn range(text: &str, start: usize, end: usize) -> Range {
    Range {
        start: position(text, start),
        end: position(text, end),
    }
}

/// The byte where line `line` (from 0) starts. None past the last line.
fn line_start(text: &str, line: u32) -> Option<usize> {
    if line == 0 {
        return Some(0);
    }
    text.match_indices('\n')
        .nth(line as usize - 1)
        .map(|(at, _)| at + 1)
}

fn floor_char_boundary(text: &str, mut offset: usize) -> usize {
    while !text.is_char_boundary(offset) {
        offset -= 1;
    }
    offset
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_column_counts_utf16_units_and_comes_back_to_its_byte() {
        // `é` is two bytes and one unit, `𝄞` four bytes and two units.
        let text = "chain 1\neq \"é𝄞\" hp=90Hz\n";
        let hp = text.find("hp").unwrap();
        assert_eq!(
            position(text, hp),
            Position {
                line: 1,
                character: 9
            }
        );
        assert_eq!(
            offset(
                text,
                Position {
                    line: 1,
                    character: 9
                }
            ),
            hp
        );
        assert_eq!(
            offset(
                text,
                Position {
                    line: 1,
                    character: 99
                }
            ),
            text.len() - 1,
            "past the end of the line"
        );
        assert_eq!(
            offset(
                text,
                Position {
                    line: 9,
                    character: 0
                }
            ),
            text.len(),
            "past the last line"
        );
    }
}
