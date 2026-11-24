//! Keys that arrive in pieces. Some terminals (the tty of BrowserPod, a slow
//! SSH link) hand over an Escape alone and the rest of its sequence later, so
//! crossterm reports `Esc`, `[`, `A` for one Up arrow. [`Joiner`] does what
//! Vim's `ttimeoutlen` does: after a lone Escape it waits a short time for
//! the rest, and joins what arrives into the key, mouse or paste event it was.
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]

use std::collections::VecDeque;
use std::time::Duration;

use crossterm::event::{
    self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers, MouseButton, MouseEvent,
    MouseEventKind,
};

/// How long to wait for the rest of a sequence, in milliseconds, unless
/// `PAW_TTIMEOUTLEN` says another time (0 turns the joining off).
const DEFAULT_MS: u64 = 15;

/// How long to wait between two pieces of a paste.
const PASTE_WAIT: Duration = Duration::from_millis(500);

/// The time to wait after a lone Escape.
pub fn ttimeout() -> Duration {
    let ms = std::env::var("PAW_TTIMEOUTLEN").ok().and_then(|v| v.trim().parse().ok());
    Duration::from_millis(ms.unwrap_or(DEFAULT_MS))
}

/// Where events come from.
pub trait Source {
    /// Whether an event arrives within `wait`.
    fn poll(&mut self, wait: Duration) -> bool;
    /// The next event, waiting for it; `None` when the source ends.
    fn read(&mut self) -> Option<Event>;
}

/// The terminal, through crossterm.
pub struct Terminal;

impl Source for Terminal {
    fn poll(&mut self, wait: Duration) -> bool {
        event::poll(wait).unwrap_or(false)
    }

    fn read(&mut self) -> Option<Event> {
        event::read().ok()
    }
}

/// Events and pauses, as a slow tty delivers them: a `None` is a gap in
/// which nothing arrives, so a wait for the rest of a sequence ends there.
/// No time passes. The tests and the fuzz target `terminal_keys` use it.
pub struct Scripted(VecDeque<Option<Event>>);

impl Scripted {
    pub fn new(steps: impl IntoIterator<Item = Option<Event>>) -> Self {
        Self(steps.into_iter().collect())
    }
}

impl Source for Scripted {
    fn poll(&mut self, _: Duration) -> bool {
        match self.0.front() {
            Some(Some(_)) => true,
            Some(None) => {
                self.0.pop_front();
                false
            }
            None => false,
        }
    }

    fn read(&mut self) -> Option<Event> {
        while let Some(step) = self.0.pop_front() {
            if step.is_some() {
                return step;
            }
        }
        None
    }
}

/// Events with split sequences joined.
pub struct Joiner<S> {
    source: S,
    wait: Duration,
    /// Events read ahead that were not part of a sequence.
    pending: VecDeque<Event>,
}

impl<S: Source> Joiner<S> {
    pub fn new(source: S, wait: Duration) -> Self {
        Self { source, wait, pending: VecDeque::new() }
    }

    /// The next event, waiting for it.
    pub fn next_event(&mut self) -> Option<Event> {
        let event = match self.pending.pop_front() {
            Some(event) => event,
            None => self.source.read()?,
        };
        if self.wait.is_zero() || !is_bare_esc(&event) {
            return Some(event);
        }
        Some(self.after_escape(event))
    }

    /// The next event if it comes within `wait`.
    fn within(&mut self, wait: Duration) -> Option<Event> {
        if let Some(event) = self.pending.pop_front() {
            return Some(event);
        }
        if self.source.poll(wait) { self.source.read() } else { None }
    }

    /// Put events back, in front of the ones read ahead.
    fn unread(&mut self, events: Vec<Event>) {
        for event in events.into_iter().rev() {
            self.pending.push_front(event);
        }
    }

    /// An Escape came: it is a key of its own, or the start of a sequence.
    fn after_escape(&mut self, esc: Event) -> Event {
        let Some(next) = self.within(self.wait) else { return esc };
        let Event::Key(key) = &next else {
            self.unread(vec![next]);
            return esc;
        };
        let plain = !key.modifiers.intersects(KeyModifiers::CONTROL | KeyModifiers::ALT);
        match key.code {
            KeyCode::Char(c @ ('[' | 'O')) if plain => {
                let mut seen = vec![next.clone()];
                match self.sequence(c, &mut seen) {
                    Some(event) => event,
                    None => {
                        self.unread(seen);
                        esc
                    }
                }
            }
            // Escape then a character, as one key: Alt with it.
            KeyCode::Char(_) if plain => {
                let mut key = *key;
                key.modifiers |= KeyModifiers::ALT;
                Event::Key(key)
            }
            _ => {
                self.unread(vec![next]);
                esc
            }
        }
    }

    /// Read the rest of a sequence after `ESC [` or `ESC O`. `seen` collects
    /// what was read, for the caller to put back when it is no sequence.
    fn sequence(&mut self, intro: char, seen: &mut Vec<Event>) -> Option<Event> {
        let mut params = String::new();
        let last = loop {
            let event = self.within(self.wait)?;
            seen.push(event.clone());
            let Event::Key(key) = event else { return None };
            let KeyCode::Char(c) = key.code else { return None };
            match c {
                '0'..='?' if intro == '[' => params.push(c),
                '@'..='~' => break c,
                _ => return None,
            }
        };
        if intro == 'O' {
            return key_of(&params, last, true);
        }
        if params == "200" && last == '~' {
            return Some(self.paste());
        }
        csi(&params, last)
    }

    /// The text of a bracketed paste, up to `ESC [ 201 ~`.
    fn paste(&mut self) -> Event {
        let mut text = String::new();
        while let Some(event) = self.within(PASTE_WAIT) {
            let Event::Key(key) = &event else {
                self.unread(vec![event]);
                break;
            };
            match key.code {
                KeyCode::Char(c) => text.push(c),
                KeyCode::Enter => text.push('\n'),
                KeyCode::Tab => text.push('\t'),
                KeyCode::Esc => {
                    let mut tail = Vec::new();
                    let mut chars = String::new();
                    while chars.len() < 5 {
                        let Some(next) = self.within(self.wait) else { break };
                        let c = match &next {
                            Event::Key(KeyEvent { code: KeyCode::Char(c), .. }) => Some(*c),
                            _ => None,
                        };
                        tail.push(next);
                        let Some(c) = c else { break };
                        chars.push(c);
                        if !"[201~".starts_with(&chars) {
                            break;
                        }
                    }
                    if chars == "[201~" {
                        return Event::Paste(text);
                    }
                    // Not the end: the Escape and the characters are text.
                    text.push('\x1b');
                    text.push_str(&chars);
                    tail.retain(|e| !matches!(e, Event::Key(k) if matches!(k.code, KeyCode::Char(_))));
                    self.unread(tail);
                }
                _ => {}
            }
        }
        Event::Paste(text)
    }
}

fn is_bare_esc(event: &Event) -> bool {
    matches!(event, Event::Key(k) if k.code == KeyCode::Esc
        && k.modifiers.is_empty() && k.kind == KeyEventKind::Press)
}

/// The modifiers of xterm's `1;m` parameter.
fn modifiers(m: u32) -> KeyModifiers {
    let bits = m.saturating_sub(1);
    let mut mods = KeyModifiers::NONE;
    if bits & 1 != 0 {
        mods |= KeyModifiers::SHIFT;
    }
    if bits & 2 != 0 {
        mods |= KeyModifiers::ALT;
    }
    if bits & 4 != 0 {
        mods |= KeyModifiers::CONTROL;
    }
    mods
}

/// A key of a CSI or SS3 sequence from its parameters and last byte.
fn key_of(params: &str, last: char, ss3: bool) -> Option<Event> {
    let nums: Vec<u32> = params.split(';').map(|p| p.parse().unwrap_or(0)).collect();
    let mods = nums.get(1).copied().map_or(KeyModifiers::NONE, modifiers);
    let code = match last {
        'A' => KeyCode::Up,
        'B' => KeyCode::Down,
        'C' => KeyCode::Right,
        'D' => KeyCode::Left,
        'H' => KeyCode::Home,
        'F' => KeyCode::End,
        'P' => KeyCode::F(1),
        'Q' => KeyCode::F(2),
        'R' => KeyCode::F(3),
        'S' => KeyCode::F(4),
        'Z' if !ss3 => return Some(Event::Key(KeyEvent::new(KeyCode::BackTab, KeyModifiers::SHIFT))),
        '~' if !ss3 => match nums[0] {
            1 | 7 => KeyCode::Home,
            2 => KeyCode::Insert,
            3 => KeyCode::Delete,
            4 | 8 => KeyCode::End,
            5 => KeyCode::PageUp,
            6 => KeyCode::PageDown,
            n @ 11..=15 => KeyCode::F((n - 10) as u8),
            n @ 17..=21 => KeyCode::F((n - 11) as u8),
            n @ 23..=24 => KeyCode::F((n - 12) as u8),
            _ => return None,
        },
        _ => return None,
    };
    Some(Event::Key(KeyEvent::new(code, mods)))
}

/// A CSI sequence: focus, an SGR mouse report, or a key.
fn csi(params: &str, last: char) -> Option<Event> {
    match (params, last) {
        ("", 'I') => Some(Event::FocusGained),
        ("", 'O') => Some(Event::FocusLost),
        (p, 'M' | 'm') if p.starts_with('<') => mouse(&p[1..], last == 'M'),
        _ => key_of(params, last, false),
    }
}

/// An SGR mouse report, `button;column;row`, as crossterm reads it.
fn mouse(params: &str, down: bool) -> Option<Event> {
    let mut nums = params.split(';').map(|p| p.parse::<u16>().ok());
    let (b, x, y) = (nums.next()??, nums.next()??, nums.next()??);
    let mut mods = KeyModifiers::NONE;
    if b & 4 != 0 {
        mods |= KeyModifiers::SHIFT;
    }
    if b & 8 != 0 {
        mods |= KeyModifiers::ALT;
    }
    if b & 16 != 0 {
        mods |= KeyModifiers::CONTROL;
    }
    let button = match b & 3 {
        0 => MouseButton::Left,
        1 => MouseButton::Middle,
        _ => MouseButton::Right,
    };
    let kind = if b & 64 != 0 {
        match b & 3 {
            0 => MouseEventKind::ScrollUp,
            1 => MouseEventKind::ScrollDown,
            2 => MouseEventKind::ScrollLeft,
            _ => MouseEventKind::ScrollRight,
        }
    } else if b & 32 != 0 {
        if b & 3 == 3 { MouseEventKind::Moved } else { MouseEventKind::Drag(button) }
    } else if down {
        MouseEventKind::Down(button)
    } else {
        MouseEventKind::Up(button)
    };
    Some(Event::Mouse(MouseEvent {
        kind,
        column: x.saturating_sub(1),
        row: y.saturating_sub(1),
        modifiers: mods,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn key(c: char) -> Option<Event> {
        Some(Event::Key(KeyEvent::new(KeyCode::Char(c), KeyModifiers::NONE)))
    }

    fn esc() -> Option<Event> {
        Some(Event::Key(KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE)))
    }

    /// What the program sees from the pieces crossterm reports.
    fn join(steps: Vec<Option<Event>>) -> Vec<Event> {
        let mut joiner = Joiner::new(Scripted::new(steps), Duration::from_millis(10));
        std::iter::from_fn(|| joiner.next_event()).collect()
    }

    fn chars(s: &str) -> Vec<Option<Event>> {
        s.chars().map(key).collect()
    }

    #[test]
    fn an_arrow_that_arrives_in_pieces_is_one_key() {
        let mut steps = vec![esc()];
        steps.extend(chars("[A"));
        let up = Event::Key(KeyEvent::new(KeyCode::Up, KeyModifiers::NONE));
        assert_eq!(join(steps), vec![up]);
    }

    #[test]
    fn modified_keys_and_alt_arrive_whole() {
        let mut steps = vec![esc()];
        steps.extend(chars("[1;5C"));
        steps.push(esc());
        steps.extend(chars("x"));
        steps.push(esc());
        steps.extend(chars("[15~"));
        let k = |code, mods| Event::Key(KeyEvent::new(code, mods));
        assert_eq!(
            join(steps),
            vec![
                k(KeyCode::Right, KeyModifiers::CONTROL),
                k(KeyCode::Char('x'), KeyModifiers::ALT),
                k(KeyCode::F(5), KeyModifiers::NONE),
            ]
        );
    }

    #[test]
    fn a_split_mouse_report_and_paste_are_events() {
        let mut steps = vec![esc()];
        steps.extend(chars("[<0;10;5M"));
        steps.push(esc());
        steps.extend(chars("[200~hi"));
        steps.push(Some(Event::Key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE))));
        steps.push(esc());
        steps.extend(chars("[201~"));
        let got = join(steps);
        assert_eq!(
            got,
            vec![
                Event::Mouse(MouseEvent {
                    kind: MouseEventKind::Down(MouseButton::Left),
                    column: 9,
                    row: 4,
                    modifiers: KeyModifiers::NONE
                }),
                Event::Paste("hi\n".into()),
            ]
        );
    }

    #[test]
    fn a_lone_escape_stays_one_and_keeps_what_follows() {
        // Esc, a pause, then `[j` typed later: not a sequence.
        let mut steps = vec![esc(), None];
        steps.extend(chars("[j"));
        assert_eq!(join(steps), vec![esc().unwrap(), key('[').unwrap(), key('j').unwrap()]);
        // An unfinished sequence falls apart into the keys it was.
        let mut steps = vec![esc()];
        steps.extend(chars("[1"));
        steps.push(None);
        steps.extend(chars("j"));
        assert_eq!(
            join(steps),
            vec![esc().unwrap(), key('[').unwrap(), key('1').unwrap(), key('j').unwrap()]
        );
    }
}
