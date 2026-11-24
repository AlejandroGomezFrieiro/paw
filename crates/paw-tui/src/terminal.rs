//! The terminal frontend: shows the kernel's grid and turns terminal events
//! into kernel input.
#![expect(clippy::cast_lossless, reason = "debt: pay down")]
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::cast_sign_loss, reason = "debt: pay down")]

use std::io::{BufWriter, Read, Write};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::time::{Duration, Instant};

use anyhow::Result;
use crossterm::event::{
    self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers, MouseButton, MouseEvent,
    MouseEventKind,
};
use crossterm::style::{
    Attribute, SetAttribute,
};
use crossterm::{cursor, execute, queue, terminal};
use paw_core::grid::{self, Caps, Color, Grid};
use paw_core::{Frontend, InputEvent};
use paw_raster::kitty;
use paw_raster::probe::{self, Probe};
use rustix::event::{PollFd, PollFlags, Timespec, poll};
use rustix::termios::{self, OptionalActions, Termios};
use signal_hook::consts::{SIGHUP, SIGTERM};

use crate::graphics::{self, Graphics};
use crate::keys;
use crate::stdio::{self, Screen};

pub(crate) struct Terminal {
    out: BufWriter<Screen>,
    /// What is on screen now, to send only the cells that changed.
    shown: Option<Grid>,
    /// Whether the terminal reports the pointer, or keeps it for its own
    /// selection (`paw.opt.mouse` off).
    mouse: bool,
    /// What the terminal said about itself at startup.
    probe: Probe,
    /// Images, when the terminal shows them.
    graphics: Option<Graphics>,
    /// What strips under the text had painted in, where backgrounds hide them.
    backing: graphics::Backing,
    /// A cell's size in pixels, as width << 16 | height, for the thread
    /// that reads the pointer in pixels.
    cell: Arc<AtomicU32>,
    /// The bytes of a frame's cells, kept from one frame to the next.
    cells: Vec<u8>,
}

/// What [`restore`] sends, as plain bytes for a signal handler to write:
/// the pointer, pasting and focus reported no more (crossterm's
/// `DisableMouseCapture` turns off 1006, 1015, 1003, 1002 and 1000; and
/// pixels, 1016), the normal screen back, the cursor shown.
const RESTORE: &[u8] =
    b"\x1b[?1004l\x1b[?2004l\x1b[?1016l\x1b[?1006l\x1b[?1015l\x1b[?1003l\x1b[?1002l\x1b[?1000l\x1b[?1049l\x1b[?25h";

/// Images were shown: leaving deletes them, or they stay in the pane.
static IMAGES: AtomicBool = AtomicBool::new(false);

/// The terminal's settings before raw mode, for a signal handler to put back.
static COOKED: std::sync::OnceLock<Termios> = std::sync::OnceLock::new();

/// Killed (`kill`, a multiplexer closing the pane), the program would leave
/// the terminal reporting every move of the pointer to the shell. A handler
/// gives it back, then lets the signal end the program as it would have.
/// It runs in the signal handler, so it stays async-signal-safe: it writes
/// only bytes made beforehand and makes plain system calls, with no
/// allocation and no lock.
fn on_signal(signal: i32) {
    if IMAGES.load(Ordering::Relaxed) {
        stdio::write_from_signal(kitty::DELETE_ALL);
    }
    stdio::write_from_signal(RESTORE);
    if let Some(cooked) = COOKED.get() {
        let _ = termios::tcsetattr(rustix::stdio::stdin(), OptionalActions::Now, cooked);
    }
    let _ = signal_hook::low_level::emulate_default_handler(signal);
}

impl Terminal {
    /// Take over the terminal and start handing its events to `send`, which
    /// says whether anyone is still listening: the kernel in this program,
    /// or a connection to one somewhere else. Call [`stdio::capture`]
    /// first, so that other output does not cover the frame.
    pub(crate) fn start(send: impl Fn(InputEvent) -> bool + Send + 'static) -> Result<(Self, u16, u16)> {
        if let Ok(cooked) = termios::tcgetattr(rustix::stdio::stdin()) {
            let _ = COOKED.set(cooked);
        }
        for signal in [SIGTERM, SIGHUP] {
            // SAFETY: on_signal is async-signal-safe (see there).
            let _ = unsafe { signal_hook::low_level::register(signal, move || on_signal(signal)) };
        }
        terminal::enable_raw_mode()?;
        // Asked before anything else reads what the terminal sends.
        let mut probe = ask();
        if let Some(cell) = cell_size() {
            probe.cell = Some(cell);
        }
        let graphics = probe.transfer.filter(|_| probe.cell.is_some()).map(|transfer| {
            IMAGES.store(true, Ordering::Relaxed);
            Graphics::new(transfer, probe.layered())
        });
        // The pointer in pixels, where views show pixels and it is known
        // how big a cell is.
        probe.pixel_mouse &= graphics.is_some();
        // The pointer, pasting and focus are asked for; no keyboard
        // protocol is (neither kitty's flags nor xterm's modifyOtherKeys):
        // keys come as a terminal sends them by default. So Ctrl with = and
        // 0 comes as the bare character and Ctrl with - as Ctrl-_, or not
        // at all, and the vertical zoom has `z+` `z-` `z=` too
        // (runtime/lua/paw/vzoom.tl). A terminal set to send them anyway
        // as CSI u gets `<C-=>`, `<C-->` and `<C-0>`.
        execute!(
            Screen,
            terminal::EnterAlternateScreen,
            event::EnableMouseCapture,
            event::EnableBracketedPaste,
            // Coming back to the terminal is known (mode 1004): changes to
            // the project's files made meanwhile are acted on then.
            event::EnableFocusChange,
            cursor::Hide
        )?;
        if probe.pixel_mouse {
            Screen.write_all(PIXEL_MOUSE)?;
        }
        let (width, height) = terminal::size()?;
        let (cw, ch) = probe.cell.unwrap_or((0, 0));
        let cell = Arc::new(AtomicU32::new((cw as u32) << 16 | ch as u32));
        let pixels = probe.pixel_mouse;
        let seen = cell.clone();
        std::thread::spawn(move || {
            let mut keys = keys::Joiner::new(keys::Terminal, keys::ttimeout());
            while let Some(event) = keys.next_event() {
                let input = match event {
                    Event::Key(key) if key.kind != KeyEventKind::Release => {
                        key_notation(key).map(InputEvent::Key)
                    }
                    Event::Mouse(mouse) => {
                        let packed = seen.load(Ordering::Relaxed);
                        let cell = (pixels && packed != 0).then_some(((packed >> 16) as u16, packed as u16));
                        Some(mouse_event(mouse, cell))
                    }
                    Event::Resize(width, height) => {
                        // A font zoom or another monitor: cells of another size.
                        if let Some((w, h)) = cell_size() {
                            let packed = (w as u32) << 16 | h as u32;
                            if seen.swap(packed, Ordering::Relaxed) != packed && !send(InputEvent::CellSize(w, h)) {
                                break;
                            }
                        }
                        Some(InputEvent::Resize(width, height))
                    }
                    Event::Paste(text) => Some(InputEvent::Paste(text)),
                    Event::FocusGained => Some(InputEvent::Focus(true)),
                    Event::FocusLost => Some(InputEvent::Focus(false)),
                    _ => None,
                };
                if let Some(input) = input
                    && !send(input)
                {
                    break;
                }
            }
        });
        Ok((
            Self {
                out: BufWriter::with_capacity(1 << 16, Screen),
                shown: None,
                mouse: true,
                probe,
                graphics,
                backing: graphics::Backing::default(),
                cell,
                cells: Vec::new(),
            },
            width,
            height,
        ))
    }

    /// What this terminal can show besides cells, for the kernel to know.
    pub(crate) fn caps(&self) -> Caps {
        let packed = self.cell.load(Ordering::Relaxed);
        Caps {
            graphics: self.graphics.is_some(),
            cell: ((packed >> 16) as u16, packed as u16),
            pixel_mouse: self.probe.pixel_mouse,
            fg: self.probe.fg,
            bg: self.probe.bg,
            under: self.graphics.is_some(),
        }
    }

    /// What the terminal said about itself, in a line, for the log.
    pub(crate) fn describe(&self) -> String {
        let p = &self.probe;
        let packed = self.cell.load(Ordering::Relaxed);
        format!(
            "terminal: {}; images {}; cell {}x{} px; pointer in pixels {}",
            p.version.as_deref().unwrap_or("unnamed"),
            match (&self.graphics, p.transfer) {
                (Some(g), Some(t)) => format!("by {t:?}, overlay {}", if g.layered { "as a sprite" } else { "baked" }),
                _ => "no".into(),
            },
            packed >> 16,
            packed & 0xffff,
            if p.pixel_mouse { "yes" } else { "no" },
        )
    }
}

/// Mode 1016: the pointer reported in pixels, in the form of 1006.
const PIXEL_MOUSE: &[u8] = b"\x1b[?1016h";

/// The size of a cell in pixels from the terminal's size, when it says.
fn cell_size() -> Option<(u16, u16)> {
    let size = terminal::window_size().ok()?;
    (size.columns > 0 && size.rows > 0 && size.width > 0 && size.height > 0)
        .then(|| (size.width / size.columns, size.height / size.rows))
}

/// Ask the terminal what it is and can do, and read the answers until the
/// one to DA1, which comes last, or a second and a half has gone by.
fn ask() -> Probe {
    let mut found = Probe::default();
    let Ok(mut tty) = std::fs::OpenOptions::new().read(true).open("/dev/tty") else {
        return found;
    };
    let mut queries = Vec::new();
    probe::queries(&mut queries);
    if Screen.write_all(&queries).is_err() {
        kitty::probe_done();
        return found;
    }
    let (mut buf, mut graphics) = (Vec::new(), Vec::new());
    let deadline = Instant::now() + Duration::from_millis(1500);
    while !found.done && Instant::now() < deadline {
        let left = deadline.saturating_duration_since(Instant::now());
        let timeout = Timespec::try_from(left).unwrap_or_default();
        if !matches!(poll(&mut [PollFd::new(&tty, PollFlags::IN)], Some(&timeout)), Ok(n) if n > 0) {
            continue;
        }
        let mut chunk = [0u8; 4096];
        match tty.read(&mut chunk) {
            Ok(n) if n > 0 => buf.extend_from_slice(&chunk[..n]),
            _ => break,
        }
        found.hear(probe::parse(&mut buf), &mut graphics);
    }
    kitty::probe_done();
    found
}

/// Give the terminal back. Safe to call more than once.
pub(crate) fn restore() {
    if IMAGES.swap(false, Ordering::Relaxed) {
        let _ = Screen.write_all(kitty::DELETE_ALL);
        let _ = Screen.write_all(b"\x1b[?1016l");
    }
    let _ = execute!(
        Screen,
        event::DisableBracketedPaste,
        event::DisableFocusChange,
        event::DisableMouseCapture,
        terminal::LeaveAlternateScreen,
        cursor::Show
    );
    let _ = terminal::disable_raw_mode();
}

impl Drop for Terminal {
    fn drop(&mut self) {
        if let Some(graphics) = &mut self.graphics {
            // What the terminal never read goes too.
            let mut bytes = Vec::new();
            graphics.clear(&mut bytes);
            let _ = self.out.write_all(&bytes);
            let _ = self.out.flush();
        }
        restore();
    }
}

impl Frontend for Terminal {
    fn present(&mut self, grid: &Grid, cursor_at: Option<(u16, u16)>) -> Result<()> {
        // Where a coloured background would hide a strip under the text,
        // the strip paints it instead.
        let backed = if self.graphics.is_some() && !self.probe.under() { self.backing.backed(grid) } else { None };
        let grid = backed.as_ref().unwrap_or(grid);
        let same_size = self
            .shown
            .as_ref()
            .is_some_and(|s| (s.width, s.height) == (grid.width, grid.height));
        let mut images = Vec::new();
        if !same_size {
            self.shown = None;
            // Images placed for the old size go before the screen is cleared.
            if let Some(graphics) = &mut self.graphics {
                graphics.clear(&mut images);
                self.out.write_all(&images)?;
                images.clear();
            }
            queue!(self.out, terminal::Clear(terminal::ClearType::All))?;
        }
        if grid.mouse_off == self.mouse {
            self.mouse = !grid.mouse_off;
            if self.mouse {
                queue!(self.out, event::EnableMouseCapture)?;
                if self.probe.pixel_mouse {
                    self.out.write_all(PIXEL_MOUSE)?;
                }
            } else {
                queue!(self.out, event::DisableMouseCapture)?;
            }
        }
        queue!(self.out, terminal::BeginSynchronizedUpdate, cursor::Hide)?;

        let width = grid.width as usize;
        // Cells written in this frame, where a surface's pixels are placed again.
        let part = self.graphics.is_some();
        let mut written = vec![false; if part { grid.cells.len() } else { 0 }];
        let mut cells = std::mem::take(&mut self.cells);
        cells.clear();
        write_cells(&mut cells, self.shown.as_ref(), grid, &mut written, write_pen);
        self.out.write_all(&cells)?;
        self.cells = cells;
        queue!(self.out, SetAttribute(Attribute::Reset))?;
        if let Some(graphics) = &mut self.graphics {
            graphics.frame(&mut images, grid, |x, y| {
                x >= 0 && y >= 0 && (x as usize) < width && written.get(y as usize * width + x as usize) == Some(&true)
            });
            self.out.write_all(&images)?;
        }
        if let Some((x, y)) = cursor_at
            && !graphics::under_pixels(grid, x, y)
        {
            queue!(self.out, cursor::MoveTo(x, y), cursor::Show)?;
        }
        queue!(self.out, terminal::EndSynchronizedUpdate)?;
        self.out.flush()?;
        grid.copy_shown(&mut self.shown);
        Ok(())
    }

    /// The next frame clears the terminal and writes each cell, as after a
    /// change of size.
    fn repaint(&mut self) {
        self.shown = None;
    }
}

/// The style the terminal writes in: foreground, background, attributes.
type Pen = (Color, Color, u8);

/// Write the cells of `grid` that differ from `shown` (all of them without
/// it): the cursor moved only to a cell that does not follow the last one
/// written, the style changed by `pen` from the last one. `written` marks
/// each cell written, when it is not empty.
fn write_cells(out: &mut Vec<u8>, shown: Option<&Grid>, grid: &Grid, written: &mut [bool], pen: impl Fn(&mut Vec<u8>, Option<Pen>, Pen)) {
    // The style and position the terminal is in: not known at first.
    let mut style: Option<Pen> = None;
    let mut at: Option<(u16, u16)> = None;
    let width = grid.width as usize;
    for (index, cell) in grid.cells.iter().enumerate() {
        let unchanged = shown.is_some_and(|s| s.cells[index] == *cell);
        if unchanged || cell.ch == '\0' {
            continue;
        }
        let (x, y) = ((index % width) as u16, (index / width) as u16);
        if let Some(mark) = written.get_mut(index) {
            *mark = true;
        }
        if at != Some((x, y)) {
            queue!(out, cursor::MoveTo(x, y)).expect("writing to memory");
        }
        let now = (cell.fg, cell.bg, cell.attrs);
        if style != Some(now) {
            pen(out, style, now);
            style = Some(now);
        }
        let mut utf8 = [0; 4];
        out.extend_from_slice(cell.ch.encode_utf8(&mut utf8).as_bytes());
        let wide = grid.cells.get(index + 1).is_some_and(|next| next.ch == '\0');
        at = Some((x + if wide { 2 } else { 1 }, y));
    }
}

/// The attributes, each with the SGR parameter that sets it and the one
/// that ends it (bold and dim end together, with 22).
const ATTRIBUTES: [(u8, &str, &str); 6] = [
    (grid::BOLD, "1", "22"),
    (grid::DIM, "2", "22"),
    (grid::ITALIC, "3", "23"),
    (grid::UNDERLINE, "4", "24"),
    (grid::REVERSE, "7", "27"),
    (grid::STRIKE, "9", "29"),
];

/// A colour as SGR parameters: `base` is 30 for the foreground, 40 for the
/// background.
fn colour_params(out: &mut Vec<u8>, colour: Color, base: u8) {
    match colour {
        Color::Default => write!(out, "{}", base + 9),
        Color::Indexed(index) => write!(out, "{};5;{index}", base + 8),
        Color::Rgb(r, g, b) => write!(out, "{};2;{r};{g};{b}", base + 8),
    }
    .expect("writing to memory");
}

/// One SGR sequence that changes the terminal's pen from `from` to `to`
/// with only what differs; from a pen not known (`None`), all of `to`
/// after a reset. A terminal draws the same as with a reset and every
/// part at each change, in fewer bytes.
fn write_pen(out: &mut Vec<u8>, from: Option<Pen>, to: Pen) {
    let start = out.len();
    out.extend_from_slice(b"\x1b[");
    let mut params = 0;
    let mut param = |out: &mut Vec<u8>, text: &str| {
        if params > 0 {
            out.push(b';');
        }
        out.extend_from_slice(text.as_bytes());
        params += 1;
    };
    let (fg, bg, mut attrs) = match from {
        Some(pen) => pen,
        None => {
            param(out, "0");
            (Color::Default, Color::Default, 0)
        }
    };
    // What ends: bold and dim end together, and the other goes on again.
    let mut ended = 0u8;
    for (bit, _, off) in ATTRIBUTES {
        if attrs & bit != 0 && to.2 & bit == 0 && ended & bit == 0 {
            param(out, off);
            ended |= if off == "22" { grid::BOLD | grid::DIM } else { bit };
        }
    }
    attrs &= !ended;
    for (bit, on, _) in ATTRIBUTES {
        if to.2 & bit != 0 && attrs & bit == 0 {
            param(out, on);
        }
    }
    if to.0 != fg {
        param(out, "");
        colour_params(out, to.0, 30);
    }
    if to.1 != bg {
        param(out, "");
        colour_params(out, to.1, 40);
    }
    if params == 0 {
        out.truncate(start);
    } else {
        out.push(b'm');
    }
}

/// A key press in Neovim notation, or `None` for keys that are not bindable.
fn key_notation(key: KeyEvent) -> Option<String> {
    let mods = key.modifiers;
    let (name, is_char) = match key.code {
        // A terminal sends Ctrl-\ Ctrl-] Ctrl-^ Ctrl-_ as the bytes 0x1c to
        // 0x1f, which crossterm reads as Ctrl-4 to Ctrl-7: they are the keys
        // that were pressed (`Ctrl-]` follows a link in help).
        KeyCode::Char(c @ '4'..='7') if mods.contains(KeyModifiers::CONTROL) => {
            (['\\', ']', '^', '_'][c as usize - '4' as usize].to_string(), true)
        }
        KeyCode::Char(' ') => ("Space".to_string(), false),
        KeyCode::Char('<') => ("lt".to_string(), false),
        KeyCode::Char(c) => (c.to_string(), true),
        KeyCode::Enter => ("CR".to_string(), false),
        KeyCode::Esc => ("Esc".to_string(), false),
        KeyCode::Backspace => ("BS".to_string(), false),
        KeyCode::Tab => ("Tab".to_string(), false),
        KeyCode::BackTab => ("S-Tab".to_string(), false),
        KeyCode::Left => ("Left".to_string(), false),
        KeyCode::Right => ("Right".to_string(), false),
        KeyCode::Up => ("Up".to_string(), false),
        KeyCode::Down => ("Down".to_string(), false),
        KeyCode::Home => ("Home".to_string(), false),
        KeyCode::End => ("End".to_string(), false),
        KeyCode::PageUp => ("PageUp".to_string(), false),
        KeyCode::PageDown => ("PageDown".to_string(), false),
        KeyCode::Delete => ("Del".to_string(), false),
        KeyCode::Insert => ("Insert".to_string(), false),
        KeyCode::F(n) => (format!("F{n}"), false),
        _ => return None,
    };
    let mut prefix = String::new();
    if mods.contains(KeyModifiers::CONTROL) {
        prefix.push_str("C-");
    }
    if mods.contains(KeyModifiers::ALT) {
        prefix.push_str("A-");
    }
    // Shift is already part of a typed character, and of `S-Tab`.
    if mods.contains(KeyModifiers::SHIFT) && !is_char && key.code != KeyCode::BackTab {
        prefix.push_str("S-");
    }
    Some(if prefix.is_empty() && is_char {
        name
    } else {
        format!("<{prefix}{name}>")
    })
}

/// A pointer event, in cells; with the terminal reporting pixels, `cell`
/// is a cell's size, which makes cells of them.
fn mouse_event(mouse: MouseEvent, cell: Option<(u16, u16)>) -> InputEvent {
    let button = |b: MouseButton| match b {
        MouseButton::Left => "left",
        MouseButton::Right => "right",
        MouseButton::Middle => "middle",
    };
    let (kind, button) = match mouse.kind {
        MouseEventKind::Down(b) => ("down", button(b)),
        MouseEventKind::Up(b) => ("up", button(b)),
        MouseEventKind::Drag(b) => ("drag", button(b)),
        MouseEventKind::Moved => ("move", ""),
        MouseEventKind::ScrollUp => ("scroll_up", ""),
        MouseEventKind::ScrollDown => ("scroll_down", ""),
        MouseEventKind::ScrollLeft => ("scroll_left", ""),
        MouseEventKind::ScrollRight => ("scroll_right", ""),
    };
    let mut mods = String::new();
    for (flag, letter) in [
        (KeyModifiers::CONTROL, 'C'),
        (KeyModifiers::ALT, 'A'),
        (KeyModifiers::SHIFT, 'S'),
    ] {
        if mouse.modifiers.contains(flag) {
            mods.push(letter);
        }
    }
    let (x, y, pixel) = match cell {
        Some((w, h)) => (mouse.column / w.max(1), mouse.row / h.max(1), Some((mouse.column, mouse.row))),
        None => (mouse.column, mouse.row, None),
    };
    InputEvent::Mouse {
        kind: kind.into(),
        button: button.into(),
        x,
        y,
        mods,
        pixel,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crossterm::style::{Color as TermColor, SetBackgroundColor, SetForegroundColor};
    use paw_core::grid::Cell;

    fn term_color(color: Color) -> TermColor {
        match color {
            Color::Default => TermColor::Reset,
            Color::Indexed(index) => TermColor::AnsiValue(index),
            Color::Rgb(r, g, b) => TermColor::Rgb { r, g, b },
        }
    }

    #[test]
    fn control_and_a_bracket_is_that_key_not_a_digit() {
        let ctrl = |c| key_notation(KeyEvent::new(KeyCode::Char(c), KeyModifiers::CONTROL));
        assert_eq!(ctrl('5').as_deref(), Some("<C-]>"));
        assert_eq!(ctrl('4').as_deref(), Some("<C-\\>"));
        assert_eq!(ctrl('w').as_deref(), Some("<C-w>"));
        let five = key_notation(KeyEvent::new(KeyCode::Char('5'), KeyModifiers::NONE));
        assert_eq!(five.as_deref(), Some("5"));
    }

    /// A terminal for the tests: what is written replayed onto a screen of
    /// cells, as a terminal shows it. It knows what paw writes: the
    /// cursor's moves, SGR, clearing; the rest is passed over.
    struct Screen {
        width: usize,
        cells: Vec<(char, Pen)>,
        at: (usize, usize),
        pen: Pen,
    }

    const PLAIN: Pen = (Color::Default, Color::Default, 0);

    fn wide(c: char) -> bool {
        matches!(c as u32, 0x1100..=0x115F | 0x2E80..=0xA4CF | 0xAC00..=0xD7A3 | 0xF900..=0xFAFF | 0xFF00..=0xFF60)
    }

    impl Screen {
        fn new(width: usize, height: usize) -> Screen {
            Screen { width, cells: vec![(' ', PLAIN); width * height], at: (0, 0), pen: PLAIN }
        }

        fn feed(&mut self, bytes: &[u8]) {
            let text = std::str::from_utf8(bytes).expect("UTF-8");
            let mut chars = text.chars().peekable();
            while let Some(c) = chars.next() {
                if c == '\x1b' {
                    if chars.next() != Some('[') {
                        continue;
                    }
                    let mut params = String::new();
                    let mut last = ' ';
                    for n in chars.by_ref() {
                        if ('@'..='~').contains(&n) {
                            last = n;
                            break;
                        }
                        params.push(n);
                    }
                    self.csi(&params, last);
                    continue;
                }
                let (x, y) = self.at;
                self.cells[y * self.width + x] = (c, self.pen);
                if wide(c) {
                    self.cells[y * self.width + x + 1] = ('\0', self.pen);
                }
                self.at.0 += if wide(c) { 2 } else { 1 };
            }
        }

        fn csi(&mut self, params: &str, last: char) {
            match last {
                'H' => {
                    let mut it = params.split(';').map(|p| p.parse::<usize>().unwrap_or(1));
                    let (row, col) = (it.next().unwrap_or(1), it.next().unwrap_or(1));
                    self.at = (col - 1, row - 1);
                }
                'J' if params == "2" => self.cells.fill((' ', PLAIN)),
                'm' => {
                    let numbers: Vec<u32> = params.split(';').map(|p| p.parse().unwrap_or(0)).collect();
                    let mut it = numbers.into_iter();
                    while let Some(n) = it.next() {
                        let colour = |it: &mut std::vec::IntoIter<u32>| match it.next() {
                            Some(5) => Color::Indexed(it.next().unwrap() as u8),
                            Some(2) => Color::Rgb(it.next().unwrap() as u8, it.next().unwrap() as u8, it.next().unwrap() as u8),
                            other => panic!("a colour of kind {other:?}"),
                        };
                        let pen = &mut self.pen;
                        match n {
                            0 => *pen = PLAIN,
                            1 => pen.2 |= grid::BOLD,
                            2 => pen.2 |= grid::DIM,
                            3 => pen.2 |= grid::ITALIC,
                            4 => pen.2 |= grid::UNDERLINE,
                            7 => pen.2 |= grid::REVERSE,
                            9 => pen.2 |= grid::STRIKE,
                            22 => pen.2 &= !(grid::BOLD | grid::DIM),
                            23 => pen.2 &= !grid::ITALIC,
                            24 => pen.2 &= !grid::UNDERLINE,
                            27 => pen.2 &= !grid::REVERSE,
                            29 => pen.2 &= !grid::STRIKE,
                            39 => pen.0 = Color::Default,
                            49 => pen.1 = Color::Default,
                            38 => pen.0 = colour(&mut it),
                            48 => pen.1 = colour(&mut it),
                            other => panic!("SGR {other}"),
                        }
                    }
                }
                _ => {}
            }
        }

        /// Whether it shows `grid`, each cell with its style.
        fn shows(&self, grid: &Grid) -> Result<(), String> {
            for (i, cell) in grid.cells.iter().enumerate() {
                if cell.ch == '\0' {
                    continue;
                }
                let (ch, pen) = self.cells[i];
                if (ch, pen) != (cell.ch, (cell.fg, cell.bg, cell.attrs)) {
                    return Err(format!("cell {i}: {:?} shown as {:?}", (cell.ch, cell.fg, cell.bg, cell.attrs), (ch, pen)));
                }
            }
            Ok(())
        }
    }

    /// Frames as a view's would be: rows of text in a few styles, the
    /// cursor's row and a meter changing from one to the next, with bold,
    /// dim and the rest coming and going, and a wide character.
    fn frames() -> Vec<Grid> {
        let colours = [Color::Default, Color::Rgb(0x20, 0x24, 0x2d), Color::Rgb(0xe3, 0xcf, 0x4f), Color::Indexed(4), Color::Rgb(0x6f, 0xbf, 0x73)];
        let mut seed = 7u32;
        let mut next = move || {
            seed = seed.wrapping_mul(1_103_515_245).wrapping_add(12345);
            (seed >> 16) as usize
        };
        let (width, height) = (60u16, 12u16);
        let mut out = Vec::new();
        let mut grid = Grid::new(width, height);
        for frame in 0..40 {
            for _ in 0..if frame == 0 { 400 } else { 30 } {
                let at = next() % grid.cells.len();
                if grid.cells[at].ch == '\0' || grid.cells.get(at + 1).is_some_and(|c| c.ch == '\0') {
                    continue;
                }
                grid.cells[at] = Cell {
                    ch: ['a', 'b', '─', '▆', ' ', 'x'][next() % 6],
                    fg: colours[next() % colours.len()],
                    bg: colours[next() % colours.len()],
                    attrs: (next() % 64) as u8 & if next() % 3 == 0 { 0xff } else { grid::BOLD | grid::DIM },
                };
            }
            if frame % 7 == 0 {
                let at = (frame as usize % 10) * 2 + width as usize;
                grid.cells[at] = Cell { ch: '漢', ..Cell::default() };
                grid.cells[at + 1] = Cell { ch: '\0', ..Cell::default() };
            }
            out.push(grid.clone());
        }
        out
    }

    /// What paw wrote before it sent only the changes: a reset, both
    /// colours and every attribute at each change of style.
    fn whole_pen(out: &mut Vec<u8>, _from: Option<Pen>, to: Pen) {
        queue!(out, SetAttribute(Attribute::Reset), SetForegroundColor(term_color(to.0)), SetBackgroundColor(term_color(to.1))).unwrap();
        for (bit, attribute) in [
            (grid::BOLD, Attribute::Bold),
            (grid::DIM, Attribute::Dim),
            (grid::ITALIC, Attribute::Italic),
            (grid::UNDERLINE, Attribute::Underlined),
            (grid::REVERSE, Attribute::Reverse),
            (grid::STRIKE, Attribute::CrossedOut),
        ] {
            if to.2 & bit != 0 {
                queue!(out, SetAttribute(attribute)).unwrap();
            }
        }
    }

    #[test]
    fn only_what_changed_of_the_style_is_sent_and_the_screen_is_the_same() {
        let frames = frames();
        let (mut screen, mut whole) = (Screen::new(60, 12), Screen::new(60, 12));
        let (mut bytes, mut whole_bytes) = (0, 0);
        let mut shown: Option<&Grid> = None;
        for (i, grid) in frames.iter().enumerate() {
            let mut out = Vec::new();
            write_cells(&mut out, shown, grid, &mut [], write_pen);
            out.extend_from_slice(b"\x1b[0m");
            screen.feed(&out);
            bytes += out.len();
            screen.shows(grid).unwrap_or_else(|err| panic!("frame {i}: {err}"));
            let mut out = Vec::new();
            write_cells(&mut out, shown, grid, &mut [], whole_pen);
            out.extend_from_slice(b"\x1b[0m");
            whole.feed(&out);
            whole_bytes += out.len();
            assert_eq!(screen.cells, whole.cells, "frame {i}: the same screen as before");
            shown = Some(grid);
        }
        assert!(bytes * 10 < whole_bytes * 9, "{bytes} bytes against {whole_bytes}: a tenth fewer at least");
    }

    #[test]
    fn a_change_of_pen_says_only_what_changed() {
        let pen = |from: Option<Pen>, to: Pen| {
            let mut out = Vec::new();
            write_pen(&mut out, from, to);
            String::from_utf8(out).unwrap()
        };
        let red = Color::Rgb(255, 0, 0);
        assert_eq!(pen(None, (red, Color::Default, grid::BOLD)), "\x1b[0;1;38;2;255;0;0m", "from a pen not known, all after a reset");
        assert_eq!(pen(Some((red, Color::Default, 0)), (red, Color::Indexed(4), 0)), "\x1b[48;5;4m", "the background alone");
        assert_eq!(pen(Some((red, Color::Default, 0)), PLAIN), "\x1b[39m");
        assert_eq!(pen(Some((red, red, grid::BOLD | grid::DIM)), (red, red, grid::DIM)), "\x1b[22;2m", "dim stays when bold ends: 22 ends both");
        assert_eq!(pen(Some((red, red, grid::BOLD | grid::UNDERLINE)), (red, red, grid::ITALIC)), "\x1b[22;24;3m");
        assert_eq!(pen(Some(PLAIN), PLAIN), "", "nothing for no change");
    }
}
