//! MIDI output to hardware and other programs, through the ALSA sequencer.
//!
//! A track can send what it plays to a port. The audio thread makes no
//! system calls, so it stamps each message with when it is to be heard, on
//! the clock of [`clock_ns`], and pushes it into a lock-free queue. A thread
//! of its own reads the queue and hands each message to the sequencer,
//! scheduled on a sequencer queue at that time in real time: it leaves on
//! time however late the thread itself wakes. The audio is heard later than
//! it is made (the output's latency, and the delay that lines plugins up),
//! so the messages are stamped that much later too, and an instrument on
//! the port sounds together with the tracks.
//!
//! What leaves is MIDI 2.0 where the port takes Universal MIDI Packets (the
//! sequencer and the port's program both speak MIDI 2.0), and otherwise the
//! MIDI 1.0 form the track's route asks for, plain, MPE or with fourteen-bit
//! controllers ([`crate::midi_form`]).
//!
//! The thread remembers the notes it has sent on, and when a track stops or
//! jumps (an `AllNotesOff` from the engine) it ends them with note-offs and
//! an All Notes Off on each channel that had one.
//!
//! It can also make ports of its own that other programs read from
//! ([`MidiOutputs::open_port`]): what a track sends there goes to whoever
//! is subscribed, a synth in another program for one.

use std::collections::HashMap;
use std::sync::mpsc::{Receiver, Sender, channel};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread::JoinHandle;
use std::time::Instant;

use anyhow::Result;
use rtrb::Consumer;

use crate::event::EventKind;
use crate::midi::{PortInfo, port_key};
use crate::midi_form::{Converter, Form, Wire};

/// The name of the sequencer client that sends: its ports are not read
/// back as MIDI input.
pub const CLIENT: &str = "paw out";

/// Messages that may wait between the audio thread and the sender.
pub const MIDI_OUT_CAPACITY: usize = 4096;

/// A message for a port: when it is to be heard, on [`clock_ns`]; the
/// port's [`port_key`](crate::midi::port_key); the form the route sends
/// in; and the message, on the channel it goes out on.
#[derive(Clone, Copy, Debug)]
pub struct MidiOut {
    pub at: u64,
    pub port: u32,
    pub form: Form,
    pub kind: EventKind,
}

/// Nanoseconds on a clock shared by the audio thread and the sender: a
/// monotonic one, from the first time it is asked.
pub fn clock_ns() -> u64 {
    static EPOCH: OnceLock<Instant> = OnceLock::new();
    EPOCH.get_or_init(Instant::now).elapsed().as_nanos() as u64
}

/// The same message on another channel, from 0; as it is with `None`.
pub fn on_channel(kind: EventKind, ch: Option<u8>) -> EventKind {
    let Some(to) = ch else { return kind };
    match kind {
        EventKind::NoteOn { key, vel, attr, .. } => EventKind::NoteOn {
            key,
            vel,
            ch: to,
            attr,
        },
        EventKind::NoteOff { key, .. } => EventKind::NoteOff { key, ch: to },
        EventKind::Control { ctl, value, .. } => EventKind::Control { ctl, value, ch: to },
        EventKind::NoteControl {
            key, ctl, value, ..
        } => EventKind::NoteControl {
            key,
            ctl,
            value,
            ch: to,
        },
        EventKind::Program { program, bank, .. } => EventKind::Program {
            program,
            bank,
            ch: to,
        },
        EventKind::AllNotesOff => EventKind::AllNotesOff,
    }
}

/// When a message stamped `at` on [`clock_ns`] leaves: nanoseconds from
/// `started`, when the sequencer queue started, while the stamp is still
/// to come at `now`; `None` for at once, when it has no stamp or its time
/// has come.
// Without the `midi` feature no sequencer queue takes the time.
#[cfg_attr(not(feature = "midi"), allow(dead_code))]
fn queue_time(at: Option<u64>, now: u64, started: u64) -> Option<u64> {
    at.filter(|at| *at > now)
        .map(|at| at.saturating_sub(started))
}

// Without the `midi` feature no thread reads the commands.
#[cfg_attr(not(feature = "midi"), allow(dead_code))]
enum Command {
    /// Read messages from this queue from now on: a new engine's.
    Queue(Consumer<MidiOut>),
    /// Make a port of our own for others to read, or take it away.
    Open(String),
    Close(String),
    Stop,
}

/// The running MIDI output thread. Dropping it ends every note it started.
pub struct MidiOutputs {
    ports: Arc<Mutex<Vec<PortInfo>>>,
    commands: Sender<Command>,
    thread: Option<JoinHandle<()>>,
}

impl MidiOutputs {
    pub fn start() -> Result<Self> {
        let ports = Arc::new(Mutex::new(Vec::new()));
        let (commands, rx) = channel();
        let thread = imp::start(ports.clone(), rx)?;
        Ok(Self {
            ports,
            commands,
            thread: Some(thread),
        })
    }

    /// Every port that can be sent MIDI, and ours that others read from
    /// (`own`).
    pub fn ports(&self) -> Vec<PortInfo> {
        self.ports.lock().map(|p| p.clone()).unwrap_or_default()
    }

    /// Send what arrives in this queue: the one an engine fills (see
    /// [`EngineHandle::midi_output`](crate::EngineHandle::midi_output)).
    pub fn set_queue(&self, queue: Consumer<MidiOut>) {
        let _ = self.commands.send(Command::Queue(queue));
    }

    /// Make a port of this program's that other programs read MIDI from,
    /// shown to them as `paw out: <name>`; tracks send to it by `name`.
    pub fn open_port(&self, name: &str) {
        let _ = self.commands.send(Command::Open(name.to_string()));
    }

    /// Take away a port made by `open_port`, ending the notes sent there.
    pub fn close_port(&self, name: &str) {
        let _ = self.commands.send(Command::Close(name.to_string()));
    }
}

impl Drop for MidiOutputs {
    fn drop(&mut self) {
        let _ = self.commands.send(Command::Stop);
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

/// A port of some client of the sequencer: its client and port numbers.
type Addr = (i32, i32);

/// Where a port's messages go to.
#[derive(Clone, Copy, Debug, PartialEq)]
enum Dest {
    /// Every subscriber of the source port: a port of our own.
    Subscribers,
    /// One port of another program.
    Port(Addr),
}

/// Where a port's messages go: from which of our ports, to where, and
/// whether as packets.
#[derive(Clone, Copy, Debug, PartialEq)]
struct Route {
    source: i32,
    dest: Dest,
    ump: bool,
}

/// What puts the messages out: the sequencer, or a spy in the tests.
trait Output {
    /// Put one message out on `route`, scheduled at `at` on [`clock_ns`],
    /// or at once with `None`.
    fn output(&mut self, route: Route, wire: Wire, at: Option<u64>);
}

/// paw's part of the output, apart from the sequencer: which port a
/// message goes to, in which form, and which notes each route has left
/// sounding.
// Without the `midi` feature only the tests make one.
#[cfg_attr(not(feature = "midi"), allow(dead_code))]
struct Router {
    /// Whether our client speaks MIDI 2.0, and so can send packets.
    ump: bool,
    /// The port that messages to other programs' ports are sent from.
    port: i32,
    /// Ports of our own that others read from: number and name.
    own: Vec<(i32, String)>,
    /// Other programs' ports, by key, and whether each takes packets.
    dests: HashMap<u32, (Addr, bool)>,
    /// What each route to a port sends, by port key and form, and the
    /// notes it has left sounding there.
    converters: HashMap<(u32, Form), Converter>,
}

#[cfg_attr(not(feature = "midi"), allow(dead_code))]
impl Router {
    fn new(ump: bool, port: i32) -> Self {
        Self {
            ump,
            port,
            own: Vec::new(),
            dests: HashMap::new(),
            converters: HashMap::new(),
        }
    }

    /// Where a port's messages go from, and to: one of ours sends to its
    /// subscribers, another program's is sent to from our output port.
    /// And whether packets can go there: to our own ports when we speak
    /// MIDI 2.0 (the sequencer turns them into MIDI 1.0 for a subscriber
    /// that does not), to another program's when it does too.
    fn route(&self, key: u32) -> Option<Route> {
        if let Some((port, _)) = self.own.iter().find(|(_, name)| port_key(name) == key) {
            return Some(Route {
                source: *port,
                dest: Dest::Subscribers,
                ump: self.ump,
            });
        }
        let (addr, ump) = *self.dests.get(&key)?;
        Some(Route {
            source: self.port,
            dest: Dest::Port(addr),
            ump: self.ump && ump,
        })
    }

    /// Put a message out in its route's form. A message to a port that
    /// is not there is dropped.
    fn send(&mut self, message: MidiOut, out: &mut impl Output) {
        let Some(route) = self.route(message.port) else {
            return;
        };
        if message.kind == EventKind::AllNotesOff {
            return self.release(message.port, Some(message.at), out);
        }
        let converter = self
            .converters
            .entry((message.port, message.form))
            .or_insert_with(|| Converter::new(message.form, route.ump));
        // The port's program changed its mind about packets: what the
        // old way left sounding is ended that way first.
        if converter.ump() != route.ump {
            converter.release(&mut |wire| out.output(route, wire, None));
            *converter = Converter::new(message.form, route.ump);
        }
        converter.convert(message.kind, &mut |wire| {
            out.output(route, wire, Some(message.at))
        });
    }

    /// End every note held on a port, at a time or now, with an All
    /// Notes Off on each channel that had one. Where the port is gone,
    /// the notes are forgotten.
    fn release(&mut self, key: u32, at: Option<u64>, out: &mut impl Output) {
        let route = self.route(key);
        for ((port, _), converter) in self.converters.iter_mut() {
            if *port != key {
                continue;
            }
            match route {
                Some(route) => converter.release(&mut |wire| out.output(route, wire, at)),
                None => converter.release(&mut |_| {}),
            }
        }
    }

    /// End every note on every port, now.
    fn release_all(&mut self, out: &mut impl Output) {
        let mut keys: Vec<u32> = self.converters.keys().map(|(key, _)| *key).collect();
        keys.sort_unstable();
        keys.dedup();
        for key in keys {
            self.release(key, None, out);
        }
    }

    /// Forget the routes to a port that is taken away.
    fn forget(&mut self, key: u32) {
        self.converters.retain(|(port, _), _| *port != key);
    }
}

#[cfg(feature = "midi")]
mod imp {
    use std::ffi::{CStr, CString, c_int};
    use std::time::Duration;

    use alsa_sys::*;

    use super::*;
    use crate::alsa::*;

    /// Sent at once rather than through a queue.
    const QUEUE_DIRECT: u8 = 253;
    /// The destination that stands for every subscriber of the source.
    const SUBSCRIBERS: u8 = 254;
    const UNKNOWN: u8 = 253;
    /// A time stamp in real time, from the queue's start.
    const TIME_STAMP_REAL: u8 = 1;
    /// How often the list of ports is read again.
    const REFRESH: Duration = Duration::from_secs(1);
    /// The catch-all input of this program's MIDI input, which would send
    /// what it is sent straight back to the tracks that send it.
    const OWN_INPUT: &str = "paw: input";

    struct Seq(*mut snd_seq_t);

    // SAFETY: an ALSA sequencer handle may be used from any thread, one at a
    // time. `Seq` is not `Sync` and not `Clone`: it is made on the thread
    // that calls `start`, then moved whole into the client's thread, the only
    // one that uses it from then on.
    unsafe impl Send for Seq {}

    impl Drop for Seq {
        fn drop(&mut self) {
            // SAFETY: the handle came from a successful `snd_seq_open`, and
            // this is its one owner, so it is closed once.
            unsafe {
                snd_seq_close(self.0);
            }
        }
    }

    fn check(code: c_int, what: &str) -> Result<c_int> {
        if code < 0 {
            anyhow::bail!("{what}: ALSA error {code}");
        }
        Ok(code)
    }

    pub(super) fn start(
        ports: Arc<Mutex<Vec<PortInfo>>>,
        rx: Receiver<Command>,
    ) -> Result<JoinHandle<()>> {
        let mut handle = std::ptr::null_mut();
        // SAFETY: `handle` is a live out-pointer and the name a C string.
        let opened = unsafe { snd_seq_open(&mut handle, c"default".as_ptr(), OPEN_OUTPUT, 0) };
        check(opened, "opening the sequencer")?;
        let seq = Seq(handle);
        // SAFETY: `seq` holds an open handle; the names are C strings that
        // outlive the calls, which only read them, and the queue control
        // takes no event (null).
        let (ump, port, queue, me) = unsafe {
            check(
                snd_seq_set_client_name(seq.0, c"paw out".as_ptr()),
                "naming the client",
            )?;
            // A MIDI 2.0 client can send packets; an older system refuses,
            // and everything goes as MIDI 1.0.
            let ump = snd_seq_set_client_midi_version(seq.0, MIDI_2_0) >= 0;
            let port = check(
                snd_seq_create_simple_port(
                    seq.0,
                    c"output".as_ptr(),
                    Caps::READ.bits(),
                    (PortType::MIDI_GENERIC | PortType::APPLICATION).bits(),
                ),
                "making the output port",
            )?;
            let queue = check(
                snd_seq_alloc_named_queue(seq.0, c"paw".as_ptr()),
                "making a queue",
            )?;
            check(
                snd_seq_control_queue(
                    seq.0,
                    queue,
                    SND_SEQ_EVENT_START as c_int,
                    0,
                    std::ptr::null_mut(),
                ),
                "starting the queue",
            )?;
            snd_seq_drain_output(seq.0);
            let me = check(snd_seq_client_id(seq.0), "asking the client's id")?;
            (ump, port, queue, me)
        };
        let mut client = Client {
            me,
            sink: Sink {
                seq,
                queue,
                started: clock_ns(),
            },
            router: Router::new(ump, port),
            rx: None,
            ports,
            refreshed: None,
        };
        client.refresh();
        let thread = std::thread::Builder::new()
            .name("paw-midi-out".into())
            .spawn(move || client.run(rx))?;
        Ok(thread)
    }

    struct Client {
        sink: Sink,
        me: i32,
        router: Router,
        rx: Option<Consumer<MidiOut>>,
        ports: Arc<Mutex<Vec<PortInfo>>>,
        refreshed: Option<Instant>,
    }

    impl Client {
        fn run(mut self, rx: Receiver<Command>) {
            loop {
                while let Ok(command) = rx.try_recv() {
                    match command {
                        Command::Queue(queue) => self.rx = Some(queue),
                        Command::Open(name) => self.open_own(name),
                        Command::Close(name) => self.close_own(&name),
                        Command::Stop => {
                            self.router.release_all(&mut self.sink);
                            self.sink.drain();
                            return;
                        }
                    }
                }
                if self.refreshed.is_none_or(|at| at.elapsed() >= REFRESH) {
                    self.refresh();
                }
                let mut sent = false;
                while let Some(message) = self.rx.as_mut().and_then(|rx| rx.pop().ok()) {
                    self.router.send(message, &mut self.sink);
                    sent = true;
                }
                if sent {
                    self.sink.drain();
                }
                std::thread::sleep(Duration::from_millis(1));
            }
        }
    }

    /// The client's handle and queue, through which everything leaves.
    struct Sink {
        seq: Seq,
        queue: c_int,
        /// When the queue started, on [`clock_ns`].
        started: u64,
    }

    impl Output for Sink {
        /// Put one message out, scheduled at `at` on [`clock_ns`] when that
        /// is still to come, else at once.
        fn output(&mut self, route: Route, wire: Wire, at: Option<u64>) {
            // The two kinds of event start with the same fields.
            // SAFETY: both are plain C structs and unions of integers (and a
            // pointer, null here): all zeros is a valid value, the empty event.
            let mut ump: snd_seq_ump_event_t = unsafe { std::mem::zeroed() };
            // SAFETY: as above.
            let mut ev: snd_seq_event_t = unsafe { std::mem::zeroed() };
            match wire {
                Wire::Ump(words) if route.ump => {
                    ump.flags = EVENT_UMP;
                    ump.__bindgen_anon_1.ump = [words[0], words[1], 0, 0];
                }
                Wire::Ump(_) => return,
                Wire::Midi1(bytes, _) => {
                    let ch = bytes[0] & 15;
                    let (type_, data) = match bytes[0] & 0xF0 {
                        0x90 => (SND_SEQ_EVENT_NOTEON, note(ch, bytes[1], bytes[2])),
                        0x80 => (SND_SEQ_EVENT_NOTEOFF, note(ch, bytes[1], 0)),
                        0xA0 => (SND_SEQ_EVENT_KEYPRESS, note(ch, bytes[1], bytes[2])),
                        0xB0 => (
                            SND_SEQ_EVENT_CONTROLLER,
                            control(ch, bytes[1] as u32, bytes[2] as i32),
                        ),
                        0xC0 => (SND_SEQ_EVENT_PGMCHANGE, control(ch, 0, bytes[1] as i32)),
                        0xD0 => (SND_SEQ_EVENT_CHANPRESS, control(ch, 0, bytes[1] as i32)),
                        0xE0 => (
                            SND_SEQ_EVENT_PITCHBEND,
                            control(ch, 0, (bytes[1] as i32 | (bytes[2] as i32) << 7) - 8192),
                        ),
                        _ => return,
                    };
                    ev.type_ = type_ as u8;
                    ev.data = data;
                }
            }
            // A port of ours sends to its subscribers, whoever they are.
            let (client, port) = match route.dest {
                Dest::Subscribers => (SUBSCRIBERS, UNKNOWN),
                Dest::Port((client, port)) => (client as u8, port as u8),
            };
            let (flags, queue, time) = match queue_time(at, clock_ns(), self.started) {
                Some(from_start) => {
                    let time = snd_seq_timestamp_t {
                        time: snd_seq_real_time_t {
                            tv_sec: (from_start / 1_000_000_000) as u32,
                            tv_nsec: (from_start % 1_000_000_000) as u32,
                        },
                    };
                    (TIME_STAMP_REAL, self.queue as u8, time)
                }
                None => (
                    0,
                    QUEUE_DIRECT,
                    snd_seq_timestamp_t {
                        time: snd_seq_real_time_t {
                            tv_sec: 0,
                            tv_nsec: 0,
                        },
                    },
                ),
            };
            if let Wire::Ump(_) = wire {
                ump.flags |= flags;
                ump.queue = queue;
                ump.time = time;
                ump.source.port = route.source as u8;
                ump.dest.client = client;
                ump.dest.port = port;
                // SAFETY: the handle is open, and `ump` a whole event that
                // the call only reads.
                unsafe { snd_seq_ump_event_output(self.seq.0, &mut ump) };
            } else {
                ev.flags = flags;
                ev.queue = queue;
                ev.time = time;
                ev.source.port = route.source as u8;
                ev.dest.client = client;
                ev.dest.port = port;
                // SAFETY: as above, for `ev`.
                unsafe { snd_seq_event_output(self.seq.0, &mut ev) };
            }
        }
    }

    impl Sink {
        fn drain(&self) {
            // SAFETY: the handle is open.
            unsafe {
                snd_seq_drain_output(self.seq.0);
            }
        }
    }

    impl Client {
        fn open_own(&mut self, name: String) {
            if self.router.own.iter().any(|(_, known)| *known == name) {
                return;
            }
            let Ok(text) = CString::new(name.as_str()) else {
                return;
            };
            // SAFETY: the handle is open, and `text` is a C string that
            // outlives the call.
            let port = unsafe {
                snd_seq_create_simple_port(
                    self.sink.seq.0,
                    text.as_ptr(),
                    (Caps::READ | Caps::SUBS_READ).bits(),
                    (PortType::MIDI_GENERIC | PortType::APPLICATION).bits(),
                )
            };
            if port >= 0 {
                self.router.own.push((port, name));
                self.refresh();
            }
        }

        fn close_own(&mut self, name: &str) {
            let Some(at) = self.router.own.iter().position(|(_, known)| known == name) else {
                return;
            };
            let key = port_key(name);
            self.router.release(key, None, &mut self.sink);
            self.sink.drain();
            self.router.forget(key);
            let (port, _) = self.router.own.remove(at);
            // SAFETY: the handle is open; a port number that is not ours
            // any more is an error code, not UB.
            unsafe {
                snd_seq_delete_simple_port(self.sink.seq.0, port);
            }
            self.refresh();
        }

        /// List the ports that can be written to now, and ours.
        fn refresh(&mut self) {
            self.refreshed = Some(Instant::now());
            let mut found = Vec::new();
            let text = |ptr: *const std::ffi::c_char| {
                if ptr.is_null() {
                    "?".to_string()
                } else {
                    // SAFETY: called below only with a name that ALSA gives
                    // from an info object that is alive: a C string that
                    // stays valid while that object does.
                    unsafe { CStr::from_ptr(ptr) }
                        .to_string_lossy()
                        .into_owned()
                }
            };
            // SAFETY: the handle is open. `client` and `port` are used only
            // after their `malloc` succeeded, and each is freed once, on
            // every way out after that. The names read from them are copied
            // before they are freed.
            unsafe {
                let mut client = std::ptr::null_mut();
                let mut port = std::ptr::null_mut();
                if snd_seq_client_info_malloc(&mut client) < 0 {
                    return;
                }
                if snd_seq_port_info_malloc(&mut port) < 0 {
                    snd_seq_client_info_free(client);
                    return;
                }
                snd_seq_client_info_set_client(client, -1);
                while snd_seq_query_next_client(self.sink.seq.0, client) >= 0 {
                    let id = snd_seq_client_info_get_client(client);
                    if id == SYSTEM_CLIENT || id == self.me {
                        continue;
                    }
                    let client_name = text(snd_seq_client_info_get_name(client));
                    let ump = snd_seq_client_info_get_midi_version(client) > 0;
                    snd_seq_port_info_set_client(port, id);
                    snd_seq_port_info_set_port(port, -1);
                    while snd_seq_query_next_port(self.sink.seq.0, port) >= 0 {
                        let caps = Caps::from_bits_retain(snd_seq_port_info_get_capability(port));
                        let writable = Caps::WRITE | Caps::SUBS_WRITE;
                        if !caps.contains(writable) || caps.contains(Caps::NO_EXPORT) {
                            continue;
                        }
                        let name =
                            format!("{client_name}: {}", text(snd_seq_port_info_get_name(port)));
                        if name == OWN_INPUT {
                            continue;
                        }
                        found.push(((id, snd_seq_port_info_get_port(port)), name, ump));
                    }
                }
                snd_seq_port_info_free(port);
                snd_seq_client_info_free(client);
            }
            self.router.dests = found
                .iter()
                .map(|(addr, name, ump)| (port_key(name), (*addr, *ump)))
                .collect();
            if let Ok(mut ports) = self.ports.lock() {
                *ports = found
                    .into_iter()
                    .map(|((client, port), name, _)| PortInfo {
                        id: format!("{client}:{port}"),
                        name,
                        open: true,
                        own: false,
                    })
                    .chain(self.router.own.iter().map(|(port, name)| PortInfo {
                        id: format!("{}:{port}", self.me),
                        name: name.clone(),
                        open: true,
                        own: true,
                    }))
                    .collect();
            }
        }
    }

    fn note(channel: u8, note: u8, velocity: u8) -> snd_seq_event_data_t {
        // SAFETY: a C union of integer structs (and a pointer): all zeros is
        // a valid value, and keeps the bytes past `note` zero.
        let mut data: snd_seq_event_data_t = unsafe { std::mem::zeroed() };
        data.note = snd_seq_ev_note_t {
            channel,
            note,
            velocity,
            off_velocity: 0,
            duration: 0,
        };
        data
    }

    fn control(channel: u8, param: u32, value: i32) -> snd_seq_event_data_t {
        // SAFETY: as in `note`.
        let mut data: snd_seq_event_data_t = unsafe { std::mem::zeroed() };
        data.control = snd_seq_ev_ctrl_t {
            channel,
            unused: [0; 3],
            param,
            value,
        };
        data
    }
}

#[cfg(not(feature = "midi"))]
mod imp {
    use super::*;

    pub fn start(
        _ports: Arc<Mutex<Vec<PortInfo>>>,
        _rx: Receiver<Command>,
    ) -> Result<JoinHandle<()>> {
        anyhow::bail!("built without MIDI support")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The stamp `at` at `now`, on a queue that started at 1 000 ns.
    fn check(at: Option<u64>, now: u64, expected: Option<u64>) {
        assert_eq!(queue_time(at, now, 1_000), expected, "stamp {at:?} at {now}");
    }

    #[test]
    fn a_message_is_queued_for_its_stamp_or_sent_at_once() {
        // Still to come: queued for its stamp, from the queue's start.
        check(Some(5_000), 4_000, Some(4_000));
        check(Some(4_001), 4_000, Some(3_001));
        // Its time has come or gone, or it has no stamp: at once.
        check(Some(4_000), 4_000, None);
        check(Some(2_000), 4_000, None);
        check(None, 4_000, None);
    }

    /// A spy in place of the sequencer: each message put out, in order.
    #[derive(Default)]
    struct Sent(Vec<(Route, Wire, Option<u64>)>);

    impl Output for Sent {
        fn output(&mut self, route: Route, wire: Wire, at: Option<u64>) {
            self.0.push((route, wire, at));
        }
    }

    /// Another program's port, "Synth: in", at 130:0, and one of ours,
    /// "Loop", our port 5. Our client sends from port 0 and speaks MIDI
    /// 1.0, so each message is plain bytes.
    const SYNTH: Addr = (130, 0);
    fn router() -> Router {
        let mut router = Router::new(false, 0);
        router.own.push((5, "Loop".to_string()));
        router.dests.insert(port_key("Synth: in"), (SYNTH, false));
        router
    }

    fn message(port: &str, form: Form, at: u64, kind: EventKind) -> MidiOut {
        MidiOut { at, port: port_key(port), form, kind }
    }

    fn on(key: u8) -> EventKind {
        EventKind::NoteOn { key, vel: 0.8, ch: 0, attr: crate::event::Attr::NONE }
    }

    /// Where each note-on went, on which channel, and its key.
    fn note_ons(sent: &Sent) -> Vec<(Dest, u8, u8)> {
        sent.0
            .iter()
            .filter_map(|(route, wire, _)| match *wire {
                Wire::Midi1([status, key, velocity], 3) if status & 0xF0 == 0x90 && velocity > 0 => {
                    Some((route.dest, status & 15, key))
                }
                _ => None,
            })
            .collect()
    }

    #[test]
    fn a_message_goes_to_the_port_it_names_in_the_form_of_its_route() {
        let (mut router, mut sent) = (router(), Sent::default());
        for key in [60, 64, 67] {
            router.send(message("Synth: in", Form::Mpe(3), 1_000, on(key)), &mut sent);
        }
        router.send(message("Loop", Form::Auto, 2_000, on(72)), &mut sent);
        let before = sent.0.len();
        router.send(message("Gone: in", Form::Auto, 3_000, on(48)), &mut sent);

        assert_eq!(sent.0.len(), before, "a port that is not there is sent nothing");
        assert_eq!(
            note_ons(&sent),
            [
                (Dest::Port(SYNTH), 1, 60),
                (Dest::Port(SYNTH), 2, 64),
                (Dest::Port(SYNTH), 3, 67),
                (Dest::Subscribers, 0, 72),
            ],
            "the chord across the zone's channels at the synth, the note as it was to our port"
        );
        let froms: Vec<(Dest, i32, Option<u64>)> =
            sent.0.iter().map(|(route, _, at)| (route.dest, route.source, *at)).collect();
        assert!(
            froms.iter().all(|from| matches!(
                from,
                (Dest::Port(SYNTH), 0, Some(1_000)) | (Dest::Subscribers, 5, Some(2_000))
            )),
            "from our output port to the synth, from our own port to its subscribers, each at its stamp: {froms:?}"
        );
    }

    #[test]
    fn all_notes_off_ends_the_notes_of_its_port_and_a_stop_ends_the_rest() {
        let (mut router, mut sent) = (router(), Sent::default());
        router.send(message("Synth: in", Form::Auto, 1_000, on(60)), &mut sent);
        router.send(message("Loop", Form::Auto, 1_000, on(62)), &mut sent);

        sent.0.clear();
        router.send(message("Synth: in", Form::Auto, 9_000, EventKind::AllNotesOff), &mut sent);
        let ended: Vec<(Dest, Wire, Option<u64>)> =
            sent.0.iter().map(|(route, wire, at)| (route.dest, *wire, *at)).collect();
        assert_eq!(
            ended,
            [
                (Dest::Port(SYNTH), Wire::Midi1([0x80, 60, 0], 3), Some(9_000)),
                (Dest::Port(SYNTH), Wire::Midi1([0xB0, 123, 0], 3), Some(9_000)),
            ],
            "the synth's note ends at the stamp, and our port's note still sounds"
        );

        sent.0.clear();
        router.release_all(&mut sent);
        let ended: Vec<(Dest, Wire, Option<u64>)> =
            sent.0.iter().map(|(route, wire, at)| (route.dest, *wire, *at)).collect();
        assert_eq!(
            ended,
            [
                (Dest::Subscribers, Wire::Midi1([0x80, 62, 0], 3), None),
                (Dest::Subscribers, Wire::Midi1([0xB0, 123, 0], 3), None),
            ],
            "a stop ends what still sounds, at once"
        );
    }
}
