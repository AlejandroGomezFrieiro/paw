//! The state of a plugin after a request that changes it: a property set
//! to a file (an LV2 model), or one of its own presets. Many plugins take
//! the request on in a later block, and some then load in a thread of
//! their own. So the session does not wait for the plugin in a loop: the
//! load keeps the state that the plugin holds at once, and a later turn
//! reads the state again after the plugin ran blocks, and keeps it.
//!
//! The session looks on each frame tick while a state is owed, and before
//! each checkpoint, undo and redo. The new state goes into each step of the
//! undo tree that holds the load (the device's `loaded` count), also a step
//! that closed before. An undo before the plugin showed the new state
//! leaves the request aside, and a redo to its step asks the plugin again.
//!
//! On the stepped backend the blocks come only as the clock moves, so a
//! test waits for `paw.api.pending().plugins_owe` to fall to 0.

use std::collections::{HashMap, HashSet};

use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64;

use super::Session;
use crate::model::Id;

/// How long a plugin may show no new state after a request, in seconds of
/// its blocks while no thread of its own works: then the request changed
/// nothing.
const IDLE_SECONDS: u64 = 1;
/// How long a read back lasts at most, in seconds of blocks, also while a
/// thread of the plugin works: a thread that never rests (an editor that
/// draws, a worker that polls) does not keep the wait open for ever.
const MOST_SECONDS: u64 = 30;

/// A request to a plugin that it takes on later: a call or one of its own
/// presets.
#[derive(Clone, Debug)]
pub(crate) struct Request {
    pub method: String,
    pub data: Vec<u8>,
}

/// A request whose new state the session waits for.
struct Readback {
    /// What the plugin held before the request.
    before: Option<Vec<u8>>,
    request: Request,
    /// The device's `loaded` id in the step of the load: no other load of
    /// the session has it. An undo, a redo or another load changes the
    /// project's id: the plugin then holds another step's state.
    loaded: u32,
    /// The engine's count of blocks at the last look.
    seen: u64,
    /// The blocks that ran while no thread of the plugin worked.
    idle: u64,
    /// All the blocks that ran since the request.
    ran: u64,
    /// The blocks of one second.
    second: u64,
}

/// The requests whose new state is not read back yet, by device.
#[derive(Default)]
pub(crate) struct Readbacks {
    /// The requests that the session looks at.
    active: HashMap<Id, Readback>,
    /// The requests whose step was left (an undo) before the plugin showed
    /// the new state. When the undo tree comes back to that step (a redo),
    /// the session asks the plugin again.
    left: HashMap<Id, Readback>,
    /// The devices that do not know the call [`BUSY`](paw_engine::device::BUSY).
    no_busy: HashSet<Id>,
    /// The last load id given ([`Session::next_load_id`]).
    last_load: u32,
}

impl Readbacks {
    /// The devices that owe the session their new state.
    pub(crate) fn len(&self) -> usize {
        self.active.len()
    }
}

/// Whether a live plugin works on something that it shows in a later
/// block. A device that does not know [`BUSY`](paw_engine::device::BUSY) is
/// put in `no_busy`, and not asked again.
fn works(id: Id, live: &mut crate::sync::LiveDevice, no_busy: &mut HashSet<Id>) -> bool {
    let attached = live.attached;
    let Some(controller) = live.controller.as_mut().filter(|_| live.stopped.is_none()) else {
        return false;
    };
    if controller.threads_working() == Some(true) {
        return true;
    }
    if !attached || no_busy.contains(&id) {
        return false;
    }
    match controller.call(paw_engine::device::BUSY, &[]) {
        Ok(answer) => answer == b"1",
        Err(_) => {
            no_busy.insert(id);
            false
        }
    }
}

/// What one look at a read back found.
enum Look {
    /// No block ran since the last look, or the plugin still works.
    Wait,
    /// The plugin holds a new state: keep it.
    Changed(Vec<u8>),
    /// The undo tree left the step of the load.
    Left,
    /// The device is gone, or the request changed nothing.
    Drop,
}

impl Session {
    /// Wait for the state of device `id` after `request`, which it takes on
    /// later: `before` is what it held before the request.
    pub(super) fn read_back_later(&mut self, id: Id, before: Option<Vec<u8>>, request: Request) {
        let Some(loaded) = self.doc.project.device(id).map(|d| d.loaded) else {
            return;
        };
        let info = &self.engine.stream.info;
        let second = u64::from(info.sample_rate.div_ceil(info.buffer_size.max(1)));
        let seen = self.blocks(None).unwrap_or(0);
        self.readbacks.left.remove(&id);
        let readback = Readback { before, request, loaded, seen, idle: 0, ran: 0, second };
        self.readbacks.active.insert(id, readback);
    }

    /// An id for a new load of device `id` that no other load of this
    /// session has, also on another branch of the undo tree: a read back
    /// finds the steps of its load by it.
    pub(super) fn next_load_id(&mut self, id: Id) -> u32 {
        let held = [&self.doc.project, &self.doc.undo.checkpoint, &self.synced]
            .iter()
            .filter_map(|project| project.device(id).map(|d| d.loaded))
            .max()
            .unwrap_or(0);
        self.readbacks.last_load = self.readbacks.last_load.max(held).wrapping_add(1);
        self.readbacks.last_load
    }

    /// Stop each read back of device `id`: a new load replaces it.
    pub(super) fn forget_read_back(&mut self, id: Id) {
        self.readbacks.active.remove(&id);
        self.readbacks.left.remove(&id);
    }

    /// Look at each read back once: keep each new state that a plugin
    /// holds now in the step that loaded it. Ask again for each request
    /// whose step the undo tree came back to.
    pub(super) fn read_back_states(&mut self) {
        self.ask_again();
        if self.readbacks.active.is_empty() {
            return;
        }
        let blocks = self.blocks(None).unwrap_or(0);
        let ids: Vec<Id> = self.readbacks.active.keys().copied().collect();
        for id in ids {
            match self.look_back(id, blocks) {
                Look::Wait => {}
                Look::Changed(state) => {
                    if let Some(readback) = self.readbacks.active.remove(&id) {
                        let old = readback.before.as_ref().map(|b| BASE64.encode(b));
                        self.keep_loaded_state(id, readback.loaded, old.as_deref(), &BASE64.encode(state));
                    }
                }
                Look::Left => {
                    if let Some(readback) = self.readbacks.active.remove(&id) {
                        self.readbacks.left.insert(id, readback);
                    }
                }
                Look::Drop => {
                    self.readbacks.active.remove(&id);
                }
            }
        }
    }

    fn look_back(&mut self, id: Id, blocks: u64) -> Look {
        let Some(loaded) = self.doc.project.device(id).map(|d| d.loaded) else {
            return Look::Drop;
        };
        let (Some(readback), Some(live)) = (self.readbacks.active.get_mut(&id), self.live.get_mut(&id)) else {
            return Look::Drop;
        };
        let Some(controller) = live.controller.as_mut().filter(|_| live.stopped.is_none()) else {
            return Look::Drop;
        };
        if loaded != readback.loaded {
            return Look::Left;
        }
        if blocks == readback.seen {
            return Look::Wait;
        }
        let ran = blocks.saturating_sub(readback.seen);
        readback.seen = blocks;
        readback.ran += ran;
        let busy = controller.threads_working() == Some(true);
        let state = match controller.save_state() {
            Ok(state) => state,
            Err(_) => return Look::Drop,
        };
        if state != readback.before {
            return state.map_or(Look::Drop, Look::Changed);
        }
        // The plugin's own threads work on what the request started: those
        // blocks count only against the larger limit.
        if !busy {
            readback.idle += ran;
        }
        let over = readback.idle >= IDLE_SECONDS * readback.second || readback.ran >= MOST_SECONDS * readback.second;
        if over { Look::Drop } else { Look::Wait }
    }

    /// Ask each plugin again for a request whose step the undo tree came
    /// back to, once the engine holds that step's state.
    fn ask_again(&mut self) {
        if self.readbacks.left.is_empty() {
            return;
        }
        let ids: Vec<Id> = self.readbacks.left.keys().copied().collect();
        for id in ids {
            let Some(loaded) = self.doc.project.device(id).map(|d| d.loaded) else {
                self.readbacks.left.remove(&id);
                continue;
            };
            let synced = self.synced.device(id).map(|d| d.loaded);
            if self.readbacks.left.get(&id).is_none_or(|r| loaded != r.loaded || synced != Some(r.loaded)) {
                continue;
            }
            let Some(readback) = self.readbacks.left.remove(&id) else { continue };
            let Some(controller) = self
                .live
                .get_mut(&id)
                .filter(|live| live.stopped.is_none())
                .and_then(|live| live.controller.as_mut())
            else {
                continue;
            };
            if controller.call(&readback.request.method, &readback.request.data).is_err() {
                continue;
            }
            self.read_back_later(id, readback.before, readback.request);
        }
    }

    /// The plugins that owe the session their state after a request.
    pub(crate) fn plugins_owe(&self) -> usize {
        self.readbacks.len()
    }

    /// The live plugins that work on something that they show in a later
    /// block: a thread of their own works now
    /// ([`Controller::threads_working`](paw_engine::device::Controller::threads_working)),
    /// or an attachment says that its plugin works (an ARA analysis,
    /// [`BUSY`](paw_engine::device::BUSY)).
    pub(crate) fn plugins_busy(&mut self) -> usize {
        let no_busy = &mut self.readbacks.no_busy;
        self.live.iter_mut().map(|(id, live)| works(*id, live, no_busy)).filter(|&busy| busy).count()
    }

    /// The live plugins with a thread of their own at work, for a caller
    /// that cannot make calls to the plugins.
    pub(crate) fn plugin_threads_busy(&self) -> usize {
        self.live
            .values()
            .filter(|live| live.stopped.is_none())
            .filter_map(|live| live.controller.as_ref())
            .filter(|controller| controller.threads_working() == Some(true))
            .count()
    }

    /// Put a state that device `id` holds now into the project, the undo
    /// step it is in and the engine's copy, so that no step is made and
    /// nothing is loaded into the plugin again.
    pub(super) fn keep_device_state(&mut self, id: Id, state: &str) {
        for snapshot in [&mut self.doc.project, &mut self.doc.undo.checkpoint, &mut self.synced] {
            if let Some(device) = snapshot.device_mut(id) {
                device.state = Some(state.to_string());
            }
        }
    }

    /// Put the state that device `id` holds after a load into each copy of
    /// the project whose device has the load's `loaded` id and still holds
    /// `old`, the state that the load kept: the project, the engine's copy,
    /// and each step of the undo tree since the load. No step is made and
    /// nothing is loaded into the plugin again.
    fn keep_loaded_state(&mut self, id: Id, loaded: u32, old: Option<&str>, state: &str) {
        let keep = |project: &mut crate::model::Project| {
            let ours = project.device(id).is_some_and(|d| d.loaded == loaded && d.state.as_deref() == old);
            if ours && let Some(device) = project.device_mut(id) {
                device.state = Some(state.to_string());
            }
            ours
        };
        for snapshot in [&mut self.doc.project, &mut self.doc.undo.checkpoint, &mut self.synced] {
            keep(snapshot);
        }
        self.doc.undo.history.change_snapshots(keep);
        self.doc.emit(crate::events::KernelEvent::DeviceChanged(crate::events::Item::on(id, None)));
    }
}

#[cfg(test)]
mod tests {
    use std::rc::Rc;
    use std::sync::Arc;
    use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};

    use paw_engine::backend::{BackendChoice, BackendOptions};
    use paw_engine::device::{Controller, Device, DeviceFactory, DeviceInfo, Instance, Io, ParamInfo};
    use paw_engine::{ProcessCtx, Registry};

    use super::*;
    use crate::session::document::PartOpts;
    use crate::session::{LoadCall, PresetLoad};

    /// What a call asks for, and what the plugin holds: a block copies the
    /// first to the second, as an LV2 plugin takes a property in its `run`.
    /// `busy` is what the plugin says of its own threads.
    #[derive(Clone, Default)]
    struct Values {
        asked: Arc<AtomicU8>,
        held: Arc<AtomicU8>,
        busy: Arc<AtomicBool>,
    }

    struct LateDevice(Values);

    impl Device for LateDevice {
        fn process(&mut self, _ctx: &ProcessCtx, _io: &mut Io) {
            self.0.held.store(self.0.asked.load(Ordering::Relaxed), Ordering::Relaxed);
        }
        fn set_param(&mut self, _index: u32, _value: f32) {}
    }

    struct LateController(Values);

    impl Controller for LateController {
        fn params(&self) -> Vec<ParamInfo> {
            Vec::new()
        }
        fn value(&self, _index: usize) -> Option<f64> {
            None
        }
        fn save_state(&mut self) -> anyhow::Result<Option<Vec<u8>>> {
            Ok(Some(vec![self.0.held.load(Ordering::Relaxed)]))
        }
        fn load_state(&mut self, state: &[u8]) -> anyhow::Result<()> {
            let value = state.first().copied().unwrap_or(0);
            self.0.asked.store(value, Ordering::Relaxed);
            self.0.held.store(value, Ordering::Relaxed);
            Ok(())
        }
        fn call(&mut self, _method: &str, data: &[u8]) -> anyhow::Result<Vec<u8>> {
            self.0.asked.store(data.first().copied().unwrap_or(0), Ordering::Relaxed);
            Ok(Vec::new())
        }
        fn threads_working(&self) -> Option<bool> {
            Some(self.0.busy.load(Ordering::Relaxed))
        }
    }

    /// A plugin that takes a call on in its next block (a fake).
    struct Late(Values, DeviceInfo);

    impl DeviceFactory for Late {
        fn info(&self) -> &DeviceInfo {
            &self.1
        }
        fn create(&self, _sample_rate: f32, _max_block: usize) -> anyhow::Result<Instance> {
            Ok(Instance {
                device: Box::new(LateDevice(self.0.clone())),
                controller: Some(Box::new(LateController(self.0.clone()))),
            })
        }
    }

    /// A session on the stepped backend with one fake plugin on a part.
    struct Setup {
        session: Session,
        id: Id,
        values: Values,
    }

    fn setup() -> Setup {
        let values = Values::default();
        let mut registry = Registry::with_builtins();
        let info = DeviceInfo { kind: "late".into(), ..Default::default() };
        registry.register(Rc::new(Late(values.clone(), info)));
        let backend = BackendOptions { backend: BackendChoice::Step, ..Default::default() };
        let mut session = Session::new(&backend, registry).unwrap();
        let part = session.doc.part_add(PartOpts::default()).unwrap();
        let id = session.device_add(part, "late", Default::default()).unwrap();
        session.flush();
        session.checkpoint();
        Setup { session, id, values }
    }

    impl Setup {
        /// Ask the plugin for `value` with a call, as one step.
        fn load(&mut self, value: u8) {
            let call = LoadCall { method: "set".into(), data: String::from(char::from(value)) };
            self.session.device_load(self.id, PresetLoad { call: Some(call), ..Default::default() }).unwrap();
            self.session.checkpoint();
        }

        /// Play `blocks` blocks, and do one turn.
        fn play(&mut self, blocks: u64) {
            let end = self.session.stepped_end_of(blocks).unwrap();
            self.session.set_now(end);
            self.session.flush();
            self.session.idle();
        }

        /// The blocks of one second.
        fn second(&self) -> u64 {
            let info = &self.session.engine.stream.info;
            u64::from(info.sample_rate.div_ceil(info.buffer_size.max(1)))
        }

        fn state(&self) -> Option<String> {
            self.session.doc.project.device(self.id).and_then(|d| d.state.clone())
        }
    }

    fn held(value: u8) -> Option<String> {
        Some(BASE64.encode([value]))
    }

    /// The load keeps the state of before and owes the new one; the turn
    /// after the plugin's next block keeps the new one in the load's undo
    /// step, with no step of its own.
    #[test]
    fn a_call_that_a_plugin_takes_on_in_its_next_block_is_kept_after_that_block() {
        let mut s = setup();
        s.load(7);
        assert_eq!(s.state(), held(0), "no block ran: the state of before");
        assert_eq!(s.session.plugins_owe(), 1, "the plugin owes its new state");

        s.play(1);
        assert_eq!(s.state(), held(7), "after a block, the new state");
        assert_eq!(s.session.plugins_owe(), 0);
        assert!(s.session.undo() && s.session.redo(), "one step back and forward");
        assert_eq!(s.state(), held(7), "the load's step holds the new state");
    }

    /// An undo before the plugin showed the new state, then a redo: the
    /// redo asks the plugin again, and its step gets the new state.
    #[test]
    fn a_redo_of_a_load_that_was_not_read_back_asks_the_plugin_again() {
        let mut s = setup();
        s.load(7);
        assert!(s.session.undo(), "undo at once, before a block");
        s.play(1);
        assert_eq!(s.values.held.load(Ordering::Relaxed), 0, "the undo gave the plugin the state of before");
        assert_eq!(s.session.plugins_owe(), 0, "the step of the load is left");

        assert!(s.session.redo());
        s.play(1);
        s.play(1);
        assert_eq!(s.values.held.load(Ordering::Relaxed), 7, "the redo asked the plugin again");
        assert_eq!(s.state(), held(7), "and its step holds the new state");
        assert!(s.session.undo() && s.session.redo());
        s.play(1);
        assert_eq!(s.state(), held(7), "for good");
    }

    /// A second edit closes its step before the plugin showed the new
    /// state: the step of the load gets the new state too.
    #[test]
    fn a_step_closed_before_the_read_back_gets_the_new_state() {
        let mut s = setup();
        s.load(7);
        s.session.doc.part_add(PartOpts::default()).unwrap();
        s.session.checkpoint();
        s.play(1);
        assert_eq!(s.state(), held(7));

        assert!(s.session.undo(), "undo of the second edit");
        s.play(1);
        assert_eq!(s.state(), held(7), "the step of the load holds the new state");
        assert_eq!(s.values.held.load(Ordering::Relaxed), 7, "and the plugin keeps it");
    }

    /// An undo before the read back, then a load that changes the state at
    /// once: the request set aside is not sent to the plugin again.
    #[test]
    fn a_load_after_an_undo_ends_the_request_set_aside() {
        let mut s = setup();
        s.load(7);
        assert!(s.session.undo(), "undo before a block");
        let state = Some(BASE64.encode([5]));
        s.session.device_load(s.id, PresetLoad { state, ..Default::default() }).unwrap();
        s.session.checkpoint();
        s.play(1);
        s.play(1);
        assert_eq!(s.values.held.load(Ordering::Relaxed), 5, "the plugin holds the second load");
        assert_eq!(s.state(), held(5), "and so does its step");
    }

    /// A load on another branch of the undo tree: its read back does not
    /// write into the step of the first load.
    #[test]
    fn a_read_back_keeps_to_the_steps_of_its_own_load() {
        let mut s = setup();
        s.load(7);
        s.play(1);
        let first = s.session.doc.project.device(s.id).map(|d| d.loaded);
        assert!(s.session.undo());
        s.load(9);
        s.play(1);
        assert_eq!(s.state(), held(9), "the second load");
        let steps: Vec<Option<String>> = s
            .session
            .doc
            .undo
            .history
            .states()
            .filter_map(|step| step.snapshot.device(s.id))
            .filter(|d| Some(d.loaded) == first)
            .map(|d| d.state.clone())
            .collect();
        assert_eq!(steps, vec![held(7)], "the step of the first load keeps its own state");
    }

    /// A call that changes nothing stops the wait after a second of blocks.
    #[test]
    fn a_call_that_changes_nothing_is_not_waited_for_after_a_second() {
        let mut s = setup();
        s.load(0);
        let second = s.second();
        s.play(second - 1);
        assert_eq!(s.session.plugins_owe(), 1, "less than a second: the wait goes on");
        s.play(1);
        assert_eq!(s.session.plugins_owe(), 0, "a second: the wait ends");
    }

    /// A thread of the plugin that works at each look holds the wait open,
    /// but not for longer than the larger limit.
    #[test]
    fn a_plugin_thread_that_never_rests_does_not_hold_the_wait_for_ever() {
        let mut s = setup();
        s.values.busy.store(true, Ordering::Relaxed);
        s.load(0);
        let second = s.second();
        s.play(2 * second);
        assert_eq!(s.session.plugins_owe(), 1, "a working thread: the wait goes on");
        s.play(MOST_SECONDS * second);
        assert_eq!(s.session.plugins_owe(), 0, "the larger limit ends it");
    }
}
