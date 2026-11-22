//! MIDI input from hardware and other programs, through the ALSA sequencer.
//!
//! One thread owns a sequencer client with a single input port, subscribes it
//! to the selected source ports (all of them by default, including ones that
//! appear later) and pushes notes straight into the engine's MIDI input queue.
//! PipeWire bridges its MIDI devices to the sequencer, so this sees them too.
//!
//! The client can also make ports of its own for other programs to send to
//! ([`MidiInputs::open_port`]). What arrives at one is told apart by the port
//! it arrived at, whoever sent it.

use std::sync::mpsc::{Receiver, Sender, channel};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;

use anyhow::Result;
use rtrb::Producer;

use crate::event::EventKind;
#[cfg(feature = "midi")]
use crate::event::{Ctl, NoteCtl};
#[cfg(feature = "midi")]
use crate::ump;

/// Where MIDI input goes.
#[derive(Default)]
pub struct MidiTarget {
    /// The engine's queue, replaced when the engine restarts. Each message
    /// goes with the [`port_key`] of the port it came from.
    pub engine: Option<Producer<(u32, EventKind)>>,
    /// Told of every message as well, with the [`port_key`] of its port, on
    /// the thread that reads the ports.
    pub tap: Option<Box<dyn FnMut(u32, EventKind) + Send>>,
}

pub type MidiSink = Arc<Mutex<MidiTarget>>;

#[derive(Clone, Debug)]
pub struct PortInfo {
    /// `client:port`, as `aconnect -l` shows it.
    pub id: String,
    /// `client name: port name`.
    pub name: String,
    pub open: bool,
    /// A port of this program's that others send to, made by `open_port`,
    /// and not a source it listens to.
    pub own: bool,
}

// Without the `midi` feature no thread reads the commands.
#[cfg_attr(not(feature = "midi"), allow(dead_code))]
enum Command {
    /// Open only these ports (by id or part of a name), or all with `None`.
    Select(Option<Vec<String>>),
    /// Make a port of our own by this name, or take it away.
    Open(String),
    Close(String),
    Stop,
}

/// The running MIDI input thread. Dropping it closes every port.
pub struct MidiInputs {
    ports: Arc<Mutex<Vec<PortInfo>>>,
    commands: Sender<Command>,
    thread: Option<JoinHandle<()>>,
}

impl MidiInputs {
    pub fn start(sink: MidiSink) -> Result<Self> {
        let ports = Arc::new(Mutex::new(Vec::new()));
        let (commands, rx) = channel();
        let thread = imp::start(sink, ports.clone(), rx)?;
        Ok(Self {
            ports,
            commands,
            thread: Some(thread),
        })
    }

    /// Every port that can send MIDI, and whether it is open.
    pub fn ports(&self) -> Vec<PortInfo> {
        self.ports.lock().map(|p| p.clone()).unwrap_or_default()
    }

    /// Open only the ports matching `which` (ids or parts of names), or every
    /// port with `None`. Notes held on a port that closes are released.
    pub fn select(&self, which: Option<Vec<String>>) {
        let _ = self.commands.send(Command::Select(which));
    }

    /// Make a port of this program's for other programs to send MIDI to,
    /// shown to them as `paw: <name>`. What arrives there goes with the
    /// [`port_key`] of `name`, and the port is listed among the inputs.
    pub fn open_port(&self, name: &str) {
        let _ = self.commands.send(Command::Open(name.to_string()));
    }

    /// Take away a port made by `open_port`; notes held on it are released.
    pub fn close_port(&self, name: &str) {
        let _ = self.commands.send(Command::Close(name.to_string()));
    }
}

impl Drop for MidiInputs {
    fn drop(&mut self) {
        let _ = self.commands.send(Command::Stop);
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

/// A short number that stands for a port by its name, for the audio thread
/// to tell ports apart by: never 0, which stands for every port. A port keeps
/// its key when it is unplugged and comes back under another number.
pub fn port_key(name: &str) -> u32 {
    // FNV-1a.
    let mut hash: u32 = 0x811c_9dc5;
    for byte in name.bytes() {
        hash ^= byte as u32;
        hash = hash.wrapping_mul(0x0100_0193);
    }
    hash.max(1)
}

/// Send a message into the engine's queue, if there is one, and to the tap.
#[cfg(feature = "midi")]
fn deliver(sink: &MidiSink, port: u32, kind: EventKind) {
    if let Ok(mut guard) = sink.lock() {
        if let Some(tx) = guard.engine.as_mut()
            && tx.push((port, kind)).is_err()
        {
            crate::event::count_dropped();
        }
        if let Some(tap) = guard.tap.as_mut() {
            tap(port, kind);
        }
    }
}

#[cfg(feature = "midi")]
fn wanted(select: &Option<Vec<String>>, port: &PortInfo) -> bool {
    match select {
        None => true,
        Some(list) => list
            .iter()
            .any(|w| port.id == *w || port.name.to_lowercase().contains(&w.to_lowercase())),
    }
}

#[cfg(feature = "midi")]
mod imp {
    use std::collections::HashMap;
    use std::ffi::{CStr, c_int};
    use std::os::fd::BorrowedFd;
    use std::time::Duration;

    use alsa_sys::*;
    use rustix::event::{PollFd, PollFlags, Timespec, poll};

    use super::*;
    use crate::alsa::*;

    /// Stands for this client in the address of one of its own ports, which
    /// no client of the sequencer has as its number.
    const OWN: i32 = -1;

    /// A port of some client: its client and port numbers.
    type Addr = (i32, i32);

    /// Keys held down per source port and channel, to release when it goes away.
    type Held = HashMap<Addr, [u128; 16]>;
    /// The key of each port by its address, from its name.
    type Keys = HashMap<Addr, u32>;

    /// An event of either kind, copied out of the sequencer: what `drain`
    /// reads of it.
    struct Event {
        type_: u32,
        flags: u8,
        source: snd_seq_addr_t,
        dest: snd_seq_addr_t,
        words: [u32; 4],
        data: snd_seq_event_data_t,
    }

    /// The sequencer handle, closed when dropped.
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

    pub fn start(
        sink: MidiSink,
        ports: Arc<Mutex<Vec<PortInfo>>>,
        rx: Receiver<Command>,
    ) -> Result<JoinHandle<()>> {
        let mut handle = std::ptr::null_mut();
        // SAFETY: `handle` is a live out-pointer and the name a C string.
        let opened = unsafe { snd_seq_open(&mut handle, c"default".as_ptr(), OPEN_INPUT, NONBLOCK) };
        check(opened, "opening the sequencer")?;
        let seq = Seq(handle);
        // SAFETY: `seq` holds an open handle; the names are C strings that
        // outlive the calls, which only read them.
        let (ump, me) = unsafe {
            check(
                snd_seq_set_client_name(seq.0, c"paw".as_ptr()),
                "naming the client",
            )?;
            // Ask for MIDI 2.0: the sequencer then hands over Universal MIDI
            // Packets, and turns what MIDI 1.0 devices send into the same.
            // An older system refuses, and MIDI 1.0 events arrive as before.
            let ump = snd_seq_set_client_midi_version(seq.0, MIDI_2_0) >= 0;
            let port = check(
                snd_seq_create_simple_port(
                    seq.0,
                    c"input".as_ptr(),
                    (Caps::WRITE | Caps::SUBS_WRITE).bits(),
                    (PortType::MIDI_GENERIC | PortType::APPLICATION).bits(),
                ),
                "making the input port",
            )?;
            let me = (
                check(snd_seq_client_id(seq.0), "asking the client's id")?,
                port,
            );
            // Hear about ports that come and go.
            check(
                snd_seq_connect_from(seq.0, port, SYSTEM_CLIENT, SYSTEM_ANNOUNCE),
                "listening for ports",
            )?;
            (ump, me)
        };
        let mut client = Client {
            seq,
            ump,
            me,
            sink,
            ports,
            select: None,
            open: Vec::new(),
            own: Vec::new(),
            held: Held::new(),
            keys: Keys::new(),
        };
        client.refresh();
        let thread = std::thread::Builder::new()
            .name("paw-midi-in".into())
            .spawn(move || client.run(rx))?;
        Ok(thread)
    }

    struct Client {
        seq: Seq,
        /// Whether the client speaks MIDI 2.0, and so reads packets.
        ump: bool,
        me: Addr,
        sink: MidiSink,
        ports: Arc<Mutex<Vec<PortInfo>>>,
        select: Option<Vec<String>>,
        /// Source ports we are subscribed to.
        open: Vec<Addr>,
        /// Ports of our own that others send to: the port's number and name.
        own: Vec<(i32, String)>,
        held: Held,
        keys: Keys,
    }

    impl Client {
        fn run(mut self, rx: Receiver<Command>) {
            // SAFETY: the handle is open.
            let count = unsafe { snd_seq_poll_descriptors_count(self.seq.0, libc::POLLIN) }.max(0);
            let mut fds = vec![
                libc::pollfd {
                    fd: -1,
                    events: 0,
                    revents: 0
                };
                count as usize
            ];
            // SAFETY: the handle is open, and `fds` has room for the `count`
            // entries it may write; ALSA's `pollfd` is the C `struct pollfd`,
            // as `libc::pollfd` is.
            let filled = unsafe {
                snd_seq_poll_descriptors(
                    self.seq.0,
                    fds.as_mut_ptr().cast(),
                    count as u32,
                    libc::POLLIN,
                )
            };
            fds.truncate(filled.max(0) as usize);
            let mut fds = fds
                .iter()
                .map(|fd| {
                    // SAFETY: the sequencer filled this entry with one of its
                    // open descriptors. The handle that owns them stays open
                    // while this thread polls: `self` outlives `fds`.
                    let fd = unsafe { BorrowedFd::borrow_raw(fd.fd) };
                    PollFd::from_borrowed_fd(fd, PollFlags::IN)
                })
                .collect::<Vec<_>>();
            loop {
                while let Ok(command) = rx.try_recv() {
                    match command {
                        Command::Select(which) => {
                            self.select = which;
                            self.refresh();
                        }
                        Command::Open(name) => self.open_own(name),
                        Command::Close(name) => self.close_own(&name),
                        Command::Stop => {
                            let open = std::mem::take(&mut self.open);
                            for addr in open {
                                self.release(addr);
                            }
                            for (port, _) in std::mem::take(&mut self.own) {
                                self.release((OWN, port));
                            }
                            return;
                        }
                    }
                }
                // Wake at least every 50 ms to look at commands.
                let ready = poll(
                    &mut fds,
                    Some(&Timespec {
                        tv_sec: 0,
                        tv_nsec: 50_000_000,
                    }),
                );
                if ready.is_err() || fds.is_empty() {
                    std::thread::sleep(Duration::from_millis(50));
                }
                self.drain();
            }
        }

        /// Take every event that is waiting.
        fn drain(&mut self) {
            let mut changed = false;
            while let Some(Event {
                type_,
                flags,
                source,
                dest,
                words,
                data,
            }) = self.next_event()
            {
                // What arrives at a port of our own is that port's,
                // whoever sent it.
                let at = dest.port as i32;
                let source = if at != self.me.1 && self.own.iter().any(|(port, _)| *port == at)
                {
                    (OWN, at)
                } else {
                    (source.client as i32, source.port as i32)
                };
                if flags & EVENT_UMP != 0 {
                    // The group is the port's business; the channel is the event's.
                    if let Some((_, kind)) = ump::decode(&words) {
                        self.take(source, kind);
                    }
                    continue;
                }
                match type_ {
                    SND_SEQ_EVENT_PORT_START
                    | SND_SEQ_EVENT_PORT_EXIT
                    | SND_SEQ_EVENT_CLIENT_EXIT
                    | SND_SEQ_EVENT_PORT_UNSUBSCRIBED => changed = true,
                    _ => {
                        if let Some(kind) = legacy(type_, &data) {
                            self.take(source, kind);
                        }
                    }
                }
            }
            if changed {
                self.refresh();
            }
        }

        /// The next event that is waiting, copied out of the sequencer's
        /// buffer, or `None` when there is none or it cannot be read.
        fn next_event(&mut self) -> Option<Event> {
            // SAFETY: the handle is open.
            if unsafe { snd_seq_event_input_pending(self.seq.0, 1) } <= 0 {
                return None;
            }
            // The two kinds of event start with the same fields.
            if self.ump {
                let mut ev: *mut snd_seq_ump_event_t = std::ptr::null_mut();
                // SAFETY: the handle is open and `ev` a live out-pointer.
                if unsafe { snd_seq_ump_event_input(self.seq.0, &mut ev) } < 0 || ev.is_null() {
                    return None;
                }
                // SAFETY: the sequencer points `ev` at an event in its own
                // buffer, valid until the next input call, and it is copied
                // out here at once.
                let ev = unsafe { &*ev };
                // SAFETY: both fields of the union are plain integers (and
                // a pointer that is not followed), so any bits are valid.
                let (words, data) = unsafe { (ev.__bindgen_anon_1.ump, ev.__bindgen_anon_1.data) };
                Some(Event {
                    type_: ev.type_ as u32,
                    flags: ev.flags,
                    source: ev.source,
                    dest: ev.dest,
                    words,
                    data,
                })
            } else {
                let mut ev: *mut snd_seq_event_t = std::ptr::null_mut();
                // SAFETY: the handle is open and `ev` a live out-pointer.
                if unsafe { snd_seq_event_input(self.seq.0, &mut ev) } < 0 || ev.is_null() {
                    return None;
                }
                // SAFETY: as for the packet above: an event in the
                // sequencer's buffer, copied out before the next input call.
                let ev = unsafe { &*ev };
                Some(Event {
                    type_: ev.type_ as u32,
                    flags: ev.flags,
                    source: ev.source,
                    dest: ev.dest,
                    words: [0; 4],
                    data: ev.data,
                })
            }
        }

        /// Pass a message on, remembering which keys are down.
        fn take(&mut self, source: Addr, kind: EventKind) {
            let held = self.held.entry(source).or_insert([0; 16]);
            match kind {
                EventKind::NoteOn { key, ch, .. } => {
                    held[(ch & 15) as usize] |= 1u128 << (key & 127)
                }
                EventKind::NoteOff { key, ch } => {
                    held[(ch & 15) as usize] &= !(1u128 << (key & 127))
                }
                _ => {}
            }
            let port = self.keys.get(&source).copied().unwrap_or(0);
            deliver(&self.sink, port, kind);
        }

        /// Make a port others can send to.
        fn open_own(&mut self, name: String) {
            if self.own.iter().any(|(_, known)| *known == name) {
                return;
            }
            let Ok(text) = std::ffi::CString::new(name.as_str()) else {
                return;
            };
            // SAFETY: the handle is open, and `text` is a C string that
            // outlives the call.
            let port = unsafe {
                snd_seq_create_simple_port(
                    self.seq.0,
                    text.as_ptr(),
                    (Caps::WRITE | Caps::SUBS_WRITE).bits(),
                    (PortType::MIDI_GENERIC | PortType::APPLICATION).bits(),
                )
            };
            if port >= 0 {
                self.keys.insert((OWN, port), port_key(&name));
                self.own.push((port, name));
                self.refresh();
            }
        }

        fn close_own(&mut self, name: &str) {
            let Some(at) = self.own.iter().position(|(_, known)| known == name) else {
                return;
            };
            let (port, _) = self.own.remove(at);
            self.release((OWN, port));
            self.keys.remove(&(OWN, port));
            // SAFETY: the handle is open; a port number that is not ours
            // any more is an error code, not UB.
            unsafe {
                snd_seq_delete_simple_port(self.seq.0, port);
            }
            self.refresh();
        }

        /// Release every note still held on a port that is no longer heard.
        fn release(&mut self, addr: Addr) {
            let port = self.keys.get(&addr).copied().unwrap_or(0);
            if let Some(held) = self.held.remove(&addr) {
                for (ch, mut keys) in held.into_iter().enumerate() {
                    while keys != 0 {
                        let key = keys.trailing_zeros() as u8;
                        keys &= !(1 << key);
                        deliver(&self.sink, port, EventKind::NoteOff { key, ch: ch as u8 });
                    }
                }
            }
        }

        /// Every port that can be read from, with its names.
        fn sources(&self) -> Vec<(Addr, PortInfo)> {
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
                    return found;
                }
                if snd_seq_port_info_malloc(&mut port) < 0 {
                    snd_seq_client_info_free(client);
                    return found;
                }
                snd_seq_client_info_set_client(client, -1);
                while snd_seq_query_next_client(self.seq.0, client) >= 0 {
                    let id = snd_seq_client_info_get_client(client);
                    // The system client only announces; ours is the destination.
                    if id == SYSTEM_CLIENT || id == self.me.0 {
                        continue;
                    }
                    let client_name = text(snd_seq_client_info_get_name(client));
                    // What tracks send out (`midi_out`) would come straight
                    // back in to the tracks that sent it.
                    if client_name == crate::midi_out::CLIENT {
                        continue;
                    }
                    snd_seq_port_info_set_client(port, id);
                    snd_seq_port_info_set_port(port, -1);
                    while snd_seq_query_next_port(self.seq.0, port) >= 0 {
                        let caps = Caps::from_bits_retain(snd_seq_port_info_get_capability(port));
                        let readable = Caps::READ | Caps::SUBS_READ;
                        if !caps.contains(readable) || caps.contains(Caps::NO_EXPORT) {
                            continue;
                        }
                        let addr = (id, snd_seq_port_info_get_port(port));
                        let name = text(snd_seq_port_info_get_name(port));
                        found.push((
                            addr,
                            PortInfo {
                                id: format!("{}:{}", addr.0, addr.1),
                                name: format!("{client_name}: {name}"),
                                open: false,
                                own: false,
                            },
                        ));
                    }
                }
                snd_seq_port_info_free(port);
                snd_seq_client_info_free(client);
            }
            found
        }

        /// List the ports there are now, subscribe to the wanted ones, and
        /// let go of the rest.
        fn refresh(&mut self) {
            let mut found = self.sources();
            let mut keep = Vec::new();
            for (addr, info) in &found {
                self.keys.insert(*addr, port_key(&info.name));
            }
            for (addr, info) in &mut found {
                if !wanted(&self.select, info) {
                    continue;
                }
                // SAFETY: the handle is open; a port that went away is an
                // error code, not UB.
                let ok = self.open.contains(addr)
                    || unsafe { snd_seq_connect_from(self.seq.0, self.me.1, addr.0, addr.1) } >= 0;
                if ok {
                    info.open = true;
                    keep.push(*addr);
                }
            }
            let gone: Vec<Addr> = self
                .open
                .iter()
                .filter(|a| !keep.contains(a))
                .copied()
                .collect();
            for addr in gone {
                // Fails harmlessly when the port has disappeared already.
                // SAFETY: the handle is open.
                unsafe {
                    snd_seq_disconnect_from(self.seq.0, self.me.1, addr.0, addr.1);
                }
                self.release(addr);
            }
            self.open = keep;
            if let Ok(mut ports) = self.ports.lock() {
                *ports = found.into_iter().map(|(_, info)| info).collect();
                ports.extend(self.own.iter().map(|(port, name)| PortInfo {
                    id: format!("{}:{}", self.me.0, port),
                    name: name.clone(),
                    open: true,
                    own: true,
                }));
            }
        }
    }

    /// A MIDI 1.0 event of the sequencer as the engine's. `data` is the data
    /// of an event of type `type_`, or the result means nothing.
    fn legacy(type_: u32, data: &snd_seq_event_data_t) -> Option<EventKind> {
        Some(match type_ {
            SND_SEQ_EVENT_NOTEON | SND_SEQ_EVENT_NOTEOFF => {
                // SAFETY: the union's `note` holds plain integers: any bits
                // are a valid value.
                let note = unsafe { data.note };
                let (key, ch) = (note.note & 127, note.channel & 15);
                if type_ == SND_SEQ_EVENT_NOTEON && note.velocity > 0 {
                    EventKind::NoteOn {
                        key,
                        vel: ump::velocity7(note.velocity.min(127)),
                        ch,
                        attr: crate::event::Attr::NONE,
                    }
                } else {
                    EventKind::NoteOff { key, ch }
                }
            }
            SND_SEQ_EVENT_KEYPRESS => {
                // SAFETY: as above.
                let note = unsafe { data.note };
                EventKind::NoteControl {
                    key: note.note & 127,
                    ctl: NoteCtl::Pressure,
                    value: ump::unit7(note.velocity.min(127)),
                    ch: note.channel & 15,
                }
            }
            SND_SEQ_EVENT_CONTROLLER
            | SND_SEQ_EVENT_PITCHBEND
            | SND_SEQ_EVENT_CHANPRESS
            | SND_SEQ_EVENT_PGMCHANGE => {
                // SAFETY: the union's `control` holds plain integers: any
                // bits are a valid value.
                let control = unsafe { data.control };
                let ch = control.channel & 15;
                let seven = control.value.clamp(0, 127) as u8;
                match type_ {
                    SND_SEQ_EVENT_CONTROLLER => EventKind::Control {
                        ctl: Ctl::Cc((control.param & 127) as u8),
                        value: ump::unit7(seven),
                        ch,
                    },
                    // The sequencer has the wheel at rest as 0.
                    SND_SEQ_EVENT_PITCHBEND => EventKind::Control {
                        ctl: Ctl::Bend,
                        value: ump::bend14((control.value.clamp(-8192, 8191) + 8192) as u16),
                        ch,
                    },
                    SND_SEQ_EVENT_PGMCHANGE => EventKind::Program {
                        program: seven,
                        bank: None,
                        ch,
                    },
                    _ => EventKind::Control {
                        ctl: Ctl::Pressure,
                        value: ump::unit7(seven),
                        ch,
                    },
                }
            }
            _ => return None,
        })
    }
}

#[cfg(not(feature = "midi"))]
mod imp {
    use super::*;

    pub fn start(
        _sink: MidiSink,
        _ports: Arc<Mutex<Vec<PortInfo>>>,
        _rx: Receiver<Command>,
    ) -> Result<JoinHandle<()>> {
        anyhow::bail!("built without MIDI input support")
    }
}
