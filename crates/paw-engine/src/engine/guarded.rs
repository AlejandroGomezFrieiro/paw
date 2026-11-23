//! A cell that one thread at a time may claim, without a lock.

use std::cell::UnsafeCell;
use std::ops::{Deref, DerefMut};
use std::sync::atomic::{AtomicBool, Ordering, Ordering::Relaxed};

/// Something one thread at a time may work on: a part or a device, while
/// the parts of a group are processed side by side. A second thread asking
/// for the same one is turned away, so even a schedule that names a part
/// twice, or two parts that share a device, cannot make two threads touch it.
pub(super) struct Guarded<T> {
    busy: AtomicBool,
    value: UnsafeCell<T>,
}

// SAFETY: as a `Mutex<T>` is: a shared `Guarded` reaches the value only
// through a `Claim`, and a `Claim` exists only for the thread whose
// compare-exchange set `busy` (Acquire) until it is dropped and clears it
// (Release), so one thread at a time touches the value, and each sees what
// the one before it wrote. `T: Send` because the value moves between threads
// that way.
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
        // SAFETY: this claim set `busy`, so no other claim of the value
        // exists and nothing else reaches it while this borrow lasts.
        unsafe { &*self.0.value.get() }
    }
}

impl<T> DerefMut for Claim<'_, T> {
    fn deref_mut(&mut self) -> &mut T {
        // SAFETY: as in `deref`; `&mut self` makes this the only borrow
        // through this claim.
        unsafe { &mut *self.0.value.get() }
    }
}

impl<T> Drop for Claim<'_, T> {
    fn drop(&mut self) {
        self.0.busy.store(false, Ordering::Release);
    }
}
