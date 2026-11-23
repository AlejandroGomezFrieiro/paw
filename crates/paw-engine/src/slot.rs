//! Where a part, a processor or a device lives in the engine's tables.
//!
//! The main thread gives out the slots. Parts and devices are two separate
//! number spaces, so each has its own type: a device slot cannot be passed
//! where a part slot is meant. Each is a `u32` in memory.

/// The index of a part in the engine's tables.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
#[repr(transparent)]
pub struct PartSlot(pub u32);

/// The index of a device in the engine's tables.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
#[repr(transparent)]
pub struct DeviceSlot(pub u32);

/// A processor of the engine: what runs a chain of devices (see
/// [`crate::plan`]). Each part has one processor, in the slot of the same
/// number; the routing of the mix keeps the order of the processors.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
#[repr(transparent)]
pub struct ProcessorSlot(pub u32);

impl ProcessorSlot {
    /// The slot as an index into a table.
    #[inline]
    pub const fn index(self) -> usize {
        self.0 as usize
    }
}

impl From<PartSlot> for ProcessorSlot {
    /// The processor of a part.
    fn from(part: PartSlot) -> Self {
        Self(part.0)
    }
}

impl PartSlot {
    /// The master part always lives in slot 0.
    pub const MASTER: Self = Self(0);
    /// No part: where the master part's output goes.
    pub const NONE: Self = Self(u32::MAX);

    /// The slot as an index into a table.
    #[inline]
    pub const fn index(self) -> usize {
        self.0 as usize
    }
}

impl DeviceSlot {
    /// No device.
    pub const NONE: Self = Self(u32::MAX);

    /// The slot as an index into a table.
    #[inline]
    pub const fn index(self) -> usize {
        self.0 as usize
    }
}
