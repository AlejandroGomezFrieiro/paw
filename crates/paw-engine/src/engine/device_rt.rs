//! A device as the audio thread holds it, with its side-chain and further outputs.

use crate::device::{Device, Io, ProcessCtx};
use crate::guard;

use super::MAX_BLOCK;

/// A device's side-chain input: a block of the track it listens to.
pub type KeyBuf = [Vec<f32>; 2];

/// A buffer for a side-chain, made on the main thread.
pub fn key_buf() -> Box<KeyBuf> {
    Box::new([vec![0.0; MAX_BLOCK], vec![0.0; MAX_BLOCK]])
}

/// A device's further output pairs: see [`Io::outputs`].
pub type OutBufs = Vec<Option<[Vec<f32>; 2]>>;

/// Buffers for the further output pairs that are routed, by their index
/// (0 for the second pair), made on the main thread.
pub fn out_bufs(routed: &[usize]) -> Box<OutBufs> {
    let count = routed.iter().map(|i| i + 1).max().unwrap_or(0);
    Box::new(
        (0..count)
            .map(|i| {
                routed
                    .contains(&i)
                    .then(|| [vec![0.0; MAX_BLOCK], vec![0.0; MAX_BLOCK]])
            })
            .collect(),
    )
}

pub(super) struct DeviceRt {
    pub(super) device: Box<dyn Device>,
    pub(super) bypass: bool,
    pub(super) host: Option<Box<crate::host::HostPath>>,
    /// Where the track it listens to puts its sound, when it has a side-chain.
    pub(super) key: Option<Box<KeyBuf>>,
    /// Where it puts its further output pairs, when some are routed.
    pub(super) outs: Option<Box<OutBufs>>,
    /// It panicked: it is not run again, and what comes in goes on as it is.
    pub(super) failed: bool,
    /// Its output held NaN or infinity, and that has been reported.
    pub(super) flagged: bool,
}

impl DeviceRt {
    /// Whether a silent block with no events can go by without running
    /// the device: it is at rest, and so is the host's mix around it.
    pub(super) fn rests(&self) -> bool {
        match self.host.as_deref() {
            Some(host) => {
                host.settled(self.bypass) && (host.dry_only(self.bypass) || self.device.resting())
            }
            None => self.bypass || self.device.resting(),
        }
    }

    /// Let a silent block go by without running the device.
    pub(super) fn skip(&mut self, n: usize) {
        if let Some(host) = self.host.as_deref_mut() {
            host.skip(n);
        }
    }

    /// A parameter of the device, or of the host's mix after the device's own.
    pub(super) fn set_param(&mut self, index: u32, value: f32) {
        if !self
            .host
            .as_mut()
            .is_some_and(|h| h.set_param(index, value))
        {
            self.device.set_param(index, value);
        }
    }

    /// Run the device with the host's mix around it. False if it panicked.
    pub(super) fn process(&mut self, ctx: &ProcessCtx, io: &mut Io) -> bool {
        match self.host.as_mut() {
            Some(host) => host.process(&mut *self.device, self.bypass, ctx, io),
            None if !self.bypass => guard::process(&mut *self.device, ctx, io),
            None => true,
        }
    }
}
