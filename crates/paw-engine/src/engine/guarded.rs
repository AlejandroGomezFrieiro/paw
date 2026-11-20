//! A cell that one thread at a time may claim, without a lock.

use std::cell::UnsafeCell;
use std::ops::{Deref, DerefMut};
use std::sync::atomic::{AtomicBool, Ordering, Ordering::Relaxed};

/// Something one thread at a time may work on: a track or a device, while
/// the tracks of a group are processed side by side. A second thread asking
/// for the same one is turned away, so even a schedule that names a track
/// twice, or two tracks that share a device, cannot make two threads touch it.
pub(super) struct Guarded<T> {
    pub(super) busy: AtomicBool,
    pub(super) value: UnsafeCell<T>,
}

// Only the thread that set `busy` reaches the value.
unsafe impl<T: Send> Sync for Guarded<T> {}

impl<T> Guarded<T> {
    pub(super) fn new(value: T) -> Self {
        Self {
            busy: AtomicBool::new(false),
            value: UnsafeCell::new(value),
        }
    }

    pub(super) fn get_mut(&mut self) -> &mut T {
        self.value.get_mut()
    }

    pub(super) fn claim(&self) -> Option<Claim<'_, T>> {
        self.busy
            .compare_exchange(false, true, Ordering::Acquire, Relaxed)
            .ok()
            .map(|_| Claim(self))
    }
}

pub(super) struct Claim<'a, T>(&'a Guarded<T>);

impl<T> Deref for Claim<'_, T> {
    type Target = T;
    fn deref(&self) -> &T {
        unsafe { &*self.0.value.get() }
    }
}

impl<T> DerefMut for Claim<'_, T> {
    fn deref_mut(&mut self) -> &mut T {
        unsafe { &mut *self.0.value.get() }
    }
}

impl<T> Drop for Claim<'_, T> {
    fn drop(&mut self) {
        self.0.busy.store(false, Ordering::Release);
    }
}
