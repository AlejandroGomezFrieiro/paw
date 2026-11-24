//! A surface cut into pieces, each a terminal image of its own: an edit
//! sends again only the pieces whose pixels changed. Pieces are whole
//! cells, cut at the barlines the drawing marks (`cut` operations) where it
//! marks them, and kept to a modest size elsewhere.
#![expect(clippy::cast_lossless, reason = "debt: pay down")]
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::cast_sign_loss, reason = "debt: pay down")]

use crate::Cut;

/// The most rows and columns of cells a piece takes.
pub const MAX_ROWS: u16 = 8;
pub const MAX_COLS: u16 = 24;

/// A rectangle of cells, from the surface's top left corner.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Cells {
    pub col: u16,
    pub row: u16,
    pub cols: u16,
    pub rows: u16,
}

/// Split `0..total` at `points`, then split what is longer than `most`
/// into equal parts.
fn split(total: u16, mut points: Vec<u16>, most: u16) -> Vec<(u16, u16)> {
    points.push(0);
    points.push(total);
    points.retain(|p| *p <= total);
    points.sort_unstable();
    points.dedup();
    let mut out = Vec::new();
    for pair in points.windows(2) {
        let (from, to) = (pair[0], pair[1]);
        let parts = (to - from).div_ceil(most).max(1);
        for i in 0..parts {
            let a = from + (to - from) * i / parts;
            let b = from + (to - from) * (i + 1) / parts;
            if b > a {
                out.push((a, b));
            }
        }
    }
    out
}

/// The pieces of a surface `cols` by `rows` cells, each cell `cell` pixels.
/// Rows are cut at the top and bottom of each marked stretch (a system),
/// and columns at its marks (barlines) within each band of rows.
pub fn tiles(cols: u16, rows: u16, cell: (u16, u16), cuts: &[Cut]) -> Vec<Cells> {
    let (cw, ch) = (cell.0.max(1) as f32, cell.1.max(1) as f32);
    let mut row_points = Vec::new();
    for cut in cuts {
        if cut.top > f32::MIN {
            row_points.push((cut.top / ch).floor().max(0.0) as u16);
        }
        if cut.bottom < f32::MAX {
            row_points.push((cut.bottom / ch).ceil().max(0.0).min(u16::MAX as f32) as u16);
        }
    }
    let mut out = Vec::new();
    for (r0, r1) in split(rows, row_points, MAX_ROWS) {
        let (top, bottom) = (r0 as f32 * ch, r1 as f32 * ch);
        let col_points = cuts
            .iter()
            .filter(|cut| cut.top < bottom && cut.bottom > top)
            .map(|cut| (cut.x / cw).round().clamp(0.0, cols as f32) as u16)
            .collect();
        for (c0, c1) in split(cols, col_points, MAX_COLS) {
            out.push(Cells { col: c0, row: r0, cols: c1 - c0, rows: r1 - r0 });
        }
    }
    out
}

/// The parts of a piece not covered by anything drawn over the surface
/// (a menu, a floating view), as rectangles: `covered(col, row)` says
/// whether a cell of the surface is covered.
pub fn uncovered(tile: Cells, covered: impl Fn(u16, u16) -> bool) -> Vec<Cells> {
    let mut done: Vec<Cells> = Vec::new();
    let mut open: Vec<Cells> = Vec::new();
    for row in tile.row..tile.row + tile.rows {
        let mut runs = Vec::new();
        let mut start = None;
        for col in tile.col..tile.col + tile.cols + 1 {
            let free = col < tile.col + tile.cols && !covered(col, row);
            match (free, start) {
                (true, None) => start = Some(col),
                (false, Some(s)) => {
                    runs.push((s, col - s));
                    start = None;
                }
                _ => {}
            }
        }
        // A run the same as the one above it makes that rectangle taller.
        let mut next = Vec::new();
        for (col, cols) in runs {
            match open.iter().position(|r| r.col == col && r.cols == cols) {
                Some(i) => {
                    let mut r = open.swap_remove(i);
                    r.rows += 1;
                    next.push(r);
                }
                None => next.push(Cells { col, row, cols, rows: 1 }),
            }
        }
        done.append(&mut open);
        open = next;
    }
    done.append(&mut open);
    done.sort_by_key(|r| (r.row, r.col));
    done
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_surface_without_marks_is_cut_into_pieces_of_modest_size() {
        let pieces = tiles(50, 10, (10, 20), &[]);
        // 50 columns in three, 10 rows in two.
        assert_eq!(pieces.len(), 6);
        assert!(pieces.iter().all(|p| p.cols <= MAX_COLS && p.rows <= MAX_ROWS));
        let area: u32 = pieces.iter().map(|p| p.cols as u32 * p.rows as u32).sum();
        assert_eq!(area, 500, "every cell in exactly one piece");
    }

    #[test]
    fn systems_and_barlines_are_where_pieces_meet() {
        // Two systems of 5 rows (100 px); barlines at 120 px in the first
        // and 70 px in the second (cells of 10 by 20).
        let cuts = [
            Cut { x: 120.0, top: 0.0, bottom: 100.0 },
            Cut { x: 70.0, top: 100.0, bottom: 200.0 },
        ];
        let pieces = tiles(20, 10, (10, 20), &cuts);
        assert_eq!(
            pieces,
            vec![
                Cells { col: 0, row: 0, cols: 12, rows: 5 },
                Cells { col: 12, row: 0, cols: 8, rows: 5 },
                Cells { col: 0, row: 5, cols: 7, rows: 5 },
                Cells { col: 7, row: 5, cols: 13, rows: 5 },
            ]
        );
    }

    #[test]
    fn what_a_menu_covers_is_left_out_of_a_piece() {
        let tile = Cells { col: 0, row: 0, cols: 6, rows: 4 };
        // A menu over columns 2 and 3 of rows 1 and 2.
        let parts = uncovered(tile, |c, r| (2..4).contains(&c) && (1..3).contains(&r));
        assert_eq!(
            parts,
            vec![
                Cells { col: 0, row: 0, cols: 6, rows: 1 },
                Cells { col: 0, row: 1, cols: 2, rows: 2 },
                Cells { col: 4, row: 1, cols: 2, rows: 2 },
                Cells { col: 0, row: 3, cols: 6, rows: 1 },
            ]
        );
        assert_eq!(uncovered(tile, |_, _| false), vec![tile]);
        assert!(uncovered(tile, |_, _| true).is_empty());
    }
}
