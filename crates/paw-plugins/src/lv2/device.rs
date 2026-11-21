//! The audio thread's half of an LV2 plugin.

use std::ffi::{CStr, c_char, c_void};
use std::ptr;
use std::sync::atomic::Ordering::Relaxed;
use std::sync::Arc;

use paw_engine::{Device, EventKind, Io, ProcessCtx, Rest, ump};
use lilv_sys::*;

use crate::lv2_patch;
use crate::{HeldNotes, write_output};
use super::urid::*;
use super::atom::*;
use super::worker::*;
use super::shared::*;

#[derive(Clone, Copy)]
pub(super) enum Connect {
    Control(usize),
    /// Whether it is an input, and its index among the buffers of that kind.
    Audio(bool, usize),
    /// A side-chain input, by its index among those.
    Key(usize),
    Atom(usize),
    Spare,
}

pub(super) struct Lv2Device {
    pub(super) shared: Arc<Shared>,
    /// Messages from the editor for the plugin's atom inputs, and from the
    /// plugin's atom outputs for the editor. Each is a port index followed by
    /// one atom.
    pub(super) from_ui: rtrb::Consumer<u8>,
    pub(super) to_ui: rtrb::Producer<u8>,
    pub(super) message: Vec<u8>,
    pub(super) audio_in: Vec<Vec<f32>>,
    pub(super) audio_out: Vec<Vec<f32>>,
    /// The side-chain inputs, and whether they hold a key.
    pub(super) key_in: Vec<Vec<f32>>,
    pub(super) keyed: bool,
    /// The outputs as stereo pairs, the main one first.
    pub(super) out_pairs: Vec<crate::OutPair>,
    pub(super) atoms: Vec<AtomBuffer>,
    /// Index in `atoms` of the port that takes MIDI.
    pub(super) midi_in: Option<usize>,
    /// The port that is told where the song is and how fast it goes, and
    /// what it was last told: playing, tempo, signature, and the position
    /// the next block starts at if nothing jumps.
    pub(super) time_in: Option<usize>,
    pub(super) time_sent: Option<(bool, f64, u32, u32, f64)>,
    pub(super) _spare: Vec<f32>,
    pub(super) held: HeldNotes,
    pub(super) response: Vec<u8>,
    /// Messages a state lane handed for the next block, each as its frame,
    /// the index of its atom input, its length and the atom.
    pub(super) queued: Vec<u8>,
    /// Whether the plugin may sleep (see [`Device::resting`]).
    pub(super) rest: Rest,
    /// How long, in frames, the plugin may ring after its input stops,
    /// besides its latency. LV2 has no way to say it.
    pub(super) tail: u64,
}

/// Room for the messages of state lanes that one block takes.
pub(super) const QUEUED_CAPACITY: usize = 16384;

/// The tail an LV2 plugin is given: it sleeps once its input was silent
/// for this long, plus its latency, and its output is silent too.
pub(super) const TAIL_SECONDS: f64 = 5.0;

impl Lv2Device {
    /// Put the messages state lanes handed into their atom inputs: those
    /// for the first frame, or (`later`) the others.
    fn push_queued(&mut self, n: usize, later: bool) {
        let mut at = 0;
        while let Some(head) = self.queued.get(at..at + 12) {
            let word = |i: usize| u32::from_le_bytes(head[i..i + 4].try_into().unwrap()) as usize;
            let (frame, index, len) = (word(0).min(n.saturating_sub(1)), word(4), word(8));
            if let Some(atom) = self.queued.get(at + 12..at + 12 + len)
                && (frame > 0) == later
            {
                self.atoms[index].push_atom(frame as u32, atom);
            }
            at += 12 + len;
        }
    }
}

impl Device for Lv2Device {
    /// Once its tail has gone by in silence and its output was silent,
    /// unless a control, a message or the worker has something for it.
    fn resting(&self) -> bool {
        self.rest.resting()
            && self.queued.is_empty()
            && self.from_ui.slots() == 0
            && !self.shared.wake.load(Relaxed)
            && !self.shared.working()
    }

    fn message(&mut self, frame: u32, data: &[u8]) -> bool {
        let Some((port, atom)) = data.split_at_checked(4) else {
            return false;
        };
        let port = u32::from_le_bytes(port.try_into().unwrap());
        let Some(index) = self.shared.atom_ports.iter().position(|p| *p == port) else {
            return false;
        };
        if !self.atoms[index].input || self.queued.len() + 12 + atom.len() > self.queued.capacity() {
            return false;
        }
        self.queued.extend_from_slice(&frame.to_le_bytes());
        self.queued.extend_from_slice(&(index as u32).to_le_bytes());
        self.queued.extend_from_slice(&(atom.len() as u32).to_le_bytes());
        self.queued.extend_from_slice(atom);
        true
    }

    fn process(&mut self, ctx: &ProcessCtx, io: &mut Io) {
        let n = io.left.len();
        // Woken: its tail starts again from here.
        self.rest.begin(io, self.shared.wake.swap(false, Relaxed));
        match self.audio_in.as_mut_slice() {
            [] => {}
            [mono] => {
                for (m, (l, r)) in mono.iter_mut().zip(io.left.iter().zip(io.right.iter())) {
                    *m = (l + r) * 0.5;
                }
            }
            [left, right, ..] => {
                left[..n].copy_from_slice(io.left);
                right[..n].copy_from_slice(io.right);
            }
        }
        self.keyed = crate::put_key(self.key_in.as_mut_slice(), io.sidechain, self.keyed, n);
        for atom in &mut self.atoms {
            atom.reset();
        }
        // What state lanes handed for the block's first frame.
        self.push_queued(n, false);
        if let Some(port) = self.time_in {
            // Told when something changes: starting, stopping, a jump, a new
            // tempo. In between, the plugin counts on from what it was told.
            let beats = n as f64 * ctx.tempo / (60.0 * ctx.sample_rate as f64);
            let expected = self.time_sent.map(|(.., next)| next);
            let state = (ctx.playing, ctx.tempo, ctx.sig_num, ctx.sig_den);
            let unchanged = self
                .time_sent
                .is_some_and(|(p, t, n, d, _)| (p, t, n, d) == state)
                && expected.is_some_and(|next| (next - ctx.position).abs() < 1e-6);
            if !unchanged {
                self.atoms[port].push_atom(0, &time_position(ctx));
            }
            let next = ctx.position + if ctx.playing { beats } else { 0.0 };
            self.time_sent = Some((ctx.playing, ctx.tempo, ctx.sig_num, ctx.sig_den, next));
        }
        if let Some(port) = self.midi_in {
            let atom = &mut self.atoms[port];
            self.held.expand(io.events.as_slice(), |frame, kind| {
                ump::midi1(kind, |bytes, len| atom.push_midi(frame, bytes, len));
            });
        } else {
            // Keep the held-note bookkeeping in step even with nowhere to send.
            self.held.expand(io.events.as_slice(), |_, _: EventKind| {});
        }
        // What the editor sent, such as the path of a file to load.
        while read_message(&mut self.from_ui, &mut self.message) {
            let Some((port, atom)) = self.message.split_at_checked(4) else {
                continue;
            };
            let port = u32::from_le_bytes(port.try_into().unwrap());
            if let Some(index) = self.shared.atom_ports.iter().position(|p| *p == port)
                && self.atoms[index].input
            {
                self.atoms[index].push_atom(0, atom);
            }
        }
        // What state lanes handed for a later frame: after the rest, so
        // that each sequence stays in the order of its frames.
        self.push_queued(n, true);
        self.queued.clear();

        let shared = &self.shared;
        // SAFETY: `shared.instance` is an instantiated and activated plugin that this device runs on the audio
        // thread only; its ports were connected to buffers owned by this device and `shared` for
        // the life of the instance, and each is at least `n` frames. The worker interface and its
        // handle belong to the same instance; the worker's responses queue has only this thread as
        // consumer (`finish` waits on atomics only).
        unsafe {
            lilv_instance_run(shared.instance, n as u32);
            if let (Some(worker), Some(interface)) =
                (shared.host.worker.get(), shared.worker_interface.as_ref())
            {
                let handle = lilv_instance_get_handle(shared.instance).cast();
                worker.finish();
                while read_message(&mut *worker.responses.get(), &mut self.response) {
                    (interface.work_response)(
                        handle,
                        self.response.len() as u32,
                        self.response.as_ptr().cast(),
                    );
                }
                if let Some(end_run) = interface.end_run {
                    end_run(handle);
                }
            }
        }

        // An open editor hears everything the plugin sends; with none open,
        // the controller still hears the new values of its properties.
        let ui_open = shared.ui_open.load(Relaxed);
        if ui_open || shared.patch_port.is_some() {
            for (atom, port) in self
                .atoms
                .iter()
                .zip(&shared.atom_ports)
                .filter(|(atom, _)| !atom.input)
            {
                atom.each_event(|event| {
                    if !ui_open && !lv2_patch::is_set(&urids().patch, event) {
                        return;
                    }
                    self.message.clear();
                    self.message.extend_from_slice(&port.to_le_bytes());
                    self.message.extend_from_slice(event);
                    write_message(&mut self.to_ui, &self.message);
                });
            }
        }

        let latency = shared.latency.map_or(0, |slot| shared.control(slot).max(0.0) as u64);
        self.rest.end_after_tail(
            Some(self.tail + latency),
            self.audio_out.iter().all(|c| paw_engine::device::silent(&c[..n])),
        );

        let add = self.audio_in.is_empty();
        match self.audio_out.as_slice() {
            [] => {}
            [mono] => write_output(io.left, io.right, &[&mono[..n]], add),
            [left, right, ..] => write_output(io.left, io.right, &[&left[..n], &right[..n]], add),
        }
        crate::write_pairs(
            &self.out_pairs,
            std::slice::from_ref(&self.audio_out),
            io.outputs,
            n,
        );
    }

    fn set_param(&mut self, index: u32, value: f32) {
        if let Some(&slot) = self.shared.param_slots.get(index as usize) {
            self.shared.set_control(slot, value);
        }
    }
}

impl Drop for Lv2Device {
    fn drop(&mut self) {
        // SAFETY: `instance` is live (the Shared that owns it is alive through `self`) and was activated
        // in `create`; it is deactivated once, here, on a thread that is not inside `run`.
        unsafe { lilv_instance_deactivate(self.shared.instance) };
    }
}

pub(super) unsafe extern "C" fn get_port_value(
    symbol: *const c_char,
    shared: *mut c_void,
    size: *mut u32,
    type_: *mut u32,
) -> *const c_void {
    // SAFETY: lilv passes back the `shared` pointer given in `save_state` (a live `&Shared` for the
    // call), a NUL-terminated port symbol, and writable `size` and `type_` slots; `scratch` is
    // written only by this callback and the value read before lilv asks for the next one.
    unsafe {
        let shared = &*(shared as *const Shared);
        let Some(&slot) = shared.symbols.get(CStr::from_ptr(symbol)) else {
            *size = 0;
            *type_ = 0;
            return ptr::null();
        };
        // lilv copies the value before asking for the next one.
        *shared.scratch.get() = shared.control(slot);
        *size = 4;
        *type_ = urids().float;
        shared.scratch.get().cast()
    }
}

unsafe extern "C" fn set_port_value(
    symbol: *const c_char,
    shared: *mut c_void,
    value: *const c_void,
    size: u32,
    type_: u32,
) {
    // SAFETY: lilv passes back the `shared` pointer given in `restore` (a live `&Shared`), a
    // NUL-terminated port symbol and, for a 4-byte float or int type, a pointer to that many readable bytes.
    unsafe {
        let shared = &*(shared as *const Shared);
        let Some(&slot) = shared.symbols.get(CStr::from_ptr(symbol)) else {
            return;
        };
        let u = urids();
        if type_ == u.float && size == 4 {
            shared.set_control(slot, *(value as *const f32));
        } else if type_ == u.int && size == 4 {
            shared.set_control(slot, *(value as *const i32) as f32);
        }
    }
}

pub(super) unsafe fn restore(shared: &Shared, state: *const LilvState) {
    // SAFETY: `state` is a live LilvState (the callers hold it until after the call), `instance` is
    // live and `shared` lives through the call, which is the `user_data` of `set_port_value`;
    // `feature_list` is the NULL-terminated array that `host_data` built, owned by `shared.host`.
    unsafe {
        lilv_state_restore(
            state,
            shared.instance,
            Some(set_port_value),
            shared as *const Shared as *mut c_void,
            0,
            shared.host.feature_list.as_ptr().cast(),
        );
    }
    // A plugin may take part of a state on only in its next block.
    shared.wake.store(true, Relaxed);
}


