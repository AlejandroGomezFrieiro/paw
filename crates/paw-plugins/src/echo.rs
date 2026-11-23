//! Tells the echo of a state from an edit, for each format the same way.
//!
//! After the host gives a plugin a state, the plugin tells of the values
//! that the state gave its parameters. That is the echo of the state: the
//! state is the truth, and the echo only mirrors it (no undo step, no
//! automation). A person who moves a control in the plugin's window makes
//! an edit. The plugin's own words tell the two apart, not the time:
//!
//! - A change inside a gesture (CLAP's `GESTURE_BEGIN` and `GESTURE_END`,
//!   VST3's `beginEdit` and `endEdit`) is an edit.
//! - A value that the host read back from the plugin after a state is the
//!   echo: the host knows that it asked. So is a change outside a gesture
//!   that a CLAP plugin tells in the first block after a state, the block
//!   in which a plugin such as Surge XT takes the state on.
//! - A change outside a gesture is the echo when its value is a value that
//!   a state since the parameter's last edit gave: a value that matches the
//!   state is the state, however late it comes. Another value is an edit.

use std::sync::atomic::{AtomicU64, Ordering};

use paw_engine::device::Change;

/// The values a parameter keeps, from the states given since its last
/// edit: an undo, then a redo, give two states before either echo comes.
const KEEP: usize = 8;

/// What the states given to a plugin set each of its parameters to, since
/// that parameter's last edit.
#[derive(Default)]
pub(crate) struct Echo {
    states: Vec<Vec<f64>>,
}

impl Echo {
    /// The plugin holds a state now, which gives its parameters these
    /// values (`None` for a value the plugin does not tell).
    pub fn given(&mut self, values: impl IntoIterator<Item = Option<f64>>) {
        for (index, value) in values.into_iter().enumerate() {
            if let Some(value) = value {
                self.keep(index, value);
            }
        }
    }

    /// A value that the host knows is the state's: the plugin told it in
    /// the block in which it took the state on, with no gesture.
    pub fn state(&mut self, index: usize, value: f64) -> Change {
        self.keep(index, value);
        Change {
            index,
            value,
            edit: false,
        }
    }

    fn keep(&mut self, index: usize, value: f64) {
        if index >= self.states.len() {
            self.states.resize_with(index + 1, Vec::new);
        }
        let kept = &mut self.states[index];
        if !kept.iter().any(|v| same(*v, value)) {
            if kept.len() == KEEP {
                kept.remove(0);
            }
            kept.push(value);
        }
    }

    /// A value that the plugin told of a parameter by itself, inside a
    /// gesture or not: an edit, or the echo of a state.
    pub fn change(&mut self, index: usize, value: f64, gesture: bool) -> Change {
        let kept = self.states.get_mut(index);
        let echo = !gesture
            && kept
                .as_ref()
                .is_some_and(|k| k.iter().any(|v| same(*v, value)));
        if !echo && let Some(kept) = kept {
            // Edited: an older state's value is no echo from here on.
            kept.clear();
        }
        Change {
            index,
            value,
            edit: !echo,
        }
    }
}

/// The blocks a plugin has run, to tell when it has taken on a state that
/// it takes on only at the start of a block (Surge XT). The audio thread
/// counts each block; the main thread marks when it gives a state, and
/// reads the plugin's values back once a block that began after the mark
/// is done. The block under way at the mark began before the state came,
/// and may not have taken it on.
#[derive(Default)]
pub(crate) struct Blocks {
    /// Blocks begun: counted before the plugin runs one.
    begun: AtomicU64,
    /// Blocks done: counted after. Never more than `begun`.
    done: AtomicU64,
}

impl Blocks {
    /// Run one block of the plugin (on the audio thread), counted.
    pub(crate) fn run<R>(&self, block: impl FnOnce() -> R) -> R {
        // SeqCst pairs with `mark`: a block counted after the mark sees
        // what the main thread gave the plugin before it.
        self.begun.fetch_add(1, Ordering::SeqCst);
        let out = block();
        // Counted once the block is done: a state taken on in it, and the
        // plugin's words of it, are there before the count is.
        self.done.fetch_add(1, Ordering::Release);
        out
    }

    /// After a state is given (on the main thread): the mark for `after`.
    pub(crate) fn mark(&self) -> u64 {
        self.begun.load(Ordering::SeqCst)
    }

    /// Whether a block that began after `mark` is done.
    pub(crate) fn after(&self, mark: u64) -> bool {
        self.done.load(Ordering::Acquire) > mark
    }
}

/// A value read back as `f32` is the same value.
fn same(a: f64, b: f64) -> bool {
    (a - b).abs() <= 1e-6 * a.abs().max(1.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_echo_of_each_state_since_an_edit_is_no_edit_and_another_value_is() {
        let mut echo = Echo::default();
        echo.given([Some(0.25), Some(1.0)]);
        echo.given([Some(0.75), Some(1.0)]);
        assert!(
            !echo.change(0, 0.25, false).edit,
            "the echo of the first state, late"
        );
        assert!(!echo.change(0, 0.75, false).edit, "the echo of the second");
        assert!(echo.change(0, 0.6, false).edit, "a value no state gave");
        assert!(
            echo.change(0, 0.75, false).edit,
            "after an edit, a state's value is a move"
        );
    }
}
