//! The device interface: anything that sits in a track's chain and makes or
//! changes sound. Built-in devices and hosted plugins both implement [`Device`].

use std::collections::BTreeMap;
use std::rc::Rc;
use std::sync::Arc;

use anyhow::Result;

use crate::event::EventBuf;

pub struct ProcessCtx {
    pub sample_rate: f32,
    pub tempo: f64,
    pub sig_num: u32,
    pub sig_den: u32,
    pub playing: bool,
    /// Project position, in beats, of the first frame of this block.
    pub position: f64,
    /// The same position in seconds from the start of the song.
    pub seconds: f64,
    /// The bar the block starts in, counting from 0, and where it starts
    /// in beats.
    pub bar: i64,
    pub bar_start: f64,
}

impl ProcessCtx {
    /// A context at the start of a song with one tempo and signature.
    pub fn at(sample_rate: f32, tempo: f64, sig_num: u32, sig_den: u32, playing: bool) -> Self {
        Self {
            sample_rate,
            tempo,
            sig_num,
            sig_den,
            playing,
            position: 0.0,
            seconds: 0.0,
            bar: 0,
            bar_start: 0.0,
        }
    }
}

/// What a device reads and writes for one block. Audio is processed in place.
pub struct Io<'a> {
    pub left: &'a mut [f32],
    pub right: &'a mut [f32],
    /// Events for this block, ordered by frame. A device may rewrite them for
    /// the devices after it.
    pub events: &'a mut EventBuf,
    /// The side-chain: another track's sound, as long as the block, for a
    /// device that listens to one ([`Ports::sidechain`]). None when nothing
    /// is connected; a compressor then listens to its own input.
    pub sidechain: Option<[&'a [f32]; 2]>,
    /// Where a device with more than one output pair puts the others: the
    /// second pair at index 0, up to the last that is routed somewhere
    /// (often none), and `None` for those that are not. Each channel holds
    /// at least a block; the device writes the first `left.len()` frames of
    /// the pairs it has, and leaves the rest silent. A device that can put
    /// a sound on its main pair or another (a drum kit) puts it on the other
    /// when that is routed.
    pub outputs: &'a mut [Option<[Vec<f32>; 2]>],
}

/// Most output pairs a device is heard on, its main one included.
pub const MAX_PAIRS: usize = 16;

/// The audio a device takes and gives besides its main stereo pair.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Ports {
    /// Whether it listens to a side-chain (see [`Io::sidechain`]).
    pub sidechain: bool,
    /// The names of its output pairs, the main one first, for a device
    /// with more than one (see [`Io::outputs`]); empty for one.
    pub outputs: Vec<String>,
}

/// Runs on the audio thread: implementations must not allocate, lock or block.
///
/// A device is created and dropped on the main thread, and only `process` and
/// `set_param` are called from the audio thread in between.
pub trait Device: Send {
    fn process(&mut self, ctx: &ProcessCtx, io: &mut Io);
    /// `index` is the position of the parameter in the device's parameter list.
    fn set_param(&mut self, index: u32, value: f32);
    /// Whether the device is at rest: given a block of silence (side-chain
    /// included) and no events, it would put out silence. The host may then
    /// leave it asleep, without calling `process`, until a block that is not
    /// silent or has events. Asked on the audio thread after each block and
    /// after parameter changes.
    ///
    /// A device that says so must also stay as it is through such a block
    /// when it is called (a built-in device returns at once), so that its
    /// sound is the very same whether the host calls it or not. A device
    /// that cannot tell (most plugins) says false, and is never put to sleep.
    fn resting(&self) -> bool {
        false
    }
    /// Take a message its controller prepared ([`Controller::prepare`]),
    /// to act on at `frame` of the next block it processes. Called on the
    /// audio thread: the device copies the bytes, and must not allocate.
    /// False when it cannot take it (it has no use for messages, or no
    /// room).
    fn message(&mut self, _frame: u32, _data: &[u8]) -> bool {
        false
    }
}

/// Whether a buffer holds only silence (zeros, either sign).
#[inline]
pub fn silent(samples: &[f32]) -> bool {
    // Or-ing the bits without the sign, eight lanes at a time, vectorises;
    // an early exit would not.
    let mut acc = [0u32; 8];
    let mut chunks = samples.chunks_exact(8);
    for chunk in &mut chunks {
        for i in 0..8 {
            acc[i] |= chunk[i].to_bits() & 0x7fff_ffff;
        }
    }
    let mut any = acc.iter().fold(0, |a, b| a | b);
    for x in chunks.remainder() {
        any |= x.to_bits() & 0x7fff_ffff;
    }
    any == 0
}

/// Whether a block of a device's input is silence: both channels, the
/// side-chain if it has one, and no events.
pub fn quiet(io: &Io) -> bool {
    io.events.is_empty()
        && silent(io.left)
        && silent(io.right)
        && io.sidechain.is_none_or(|[l, r]| silent(l) && silent(r))
}

/// The main-thread side of a device that has one, such as a hosted plugin:
/// everything about it that is not processing audio.
pub trait Controller {
    /// This instance's parameters, for devices that only know them once
    /// they exist.
    fn params(&self) -> Vec<ParamInfo>;
    /// The current value of a parameter, by position in [`params`](Self::params).
    fn value(&self, index: usize) -> Option<f64>;
    /// Told whenever the host sets a parameter, alongside the change sent to
    /// the audio thread, for formats that keep a main-thread copy of the value.
    fn set_value(&mut self, _index: usize, _value: f64) {}
    /// Everything needed to bring a new instance back to this one's state.
    fn save_state(&mut self) -> Result<Option<Vec<u8>>>;
    fn load_state(&mut self, state: &[u8]) -> Result<()>;
    /// Whether the project says what the device's state is, as for a kit of
    /// samples set from a script: then a new state in the project (an edit,
    /// an undo) is loaded into the running device. A plugin's state is only
    /// read back from it, and is loaded only when the plugin is made.
    fn follows_state(&self) -> bool {
        false
    }
    /// Called regularly, for whatever the device needs done on the main thread.
    fn idle(&mut self) {}
    /// A value of a parameter as the device itself writes it ("440 Hz",
    /// "Saw"), by position in [`params`](Self::params). None when the
    /// device has no text of its own for it.
    fn value_text(&mut self, _index: usize, _value: f64) -> Option<String> {
        None
    }
    /// The value that a text stands for, as the device itself reads it:
    /// the reverse of [`value_text`](Self::value_text). None when the
    /// device cannot read it.
    fn text_value(&mut self, _index: usize, _text: &str) -> Option<f64> {
        None
    }
    /// Parameters the device changed by itself since the last call, as
    /// (position in [`params`](Self::params), new value): what a user did in
    /// the device's own editor, or a preset it loaded.
    fn take_changes(&mut self) -> Vec<(usize, f64)> {
        Vec::new()
    }
    /// Whether the device has a window of its own to show.
    fn has_editor(&self) -> bool {
        false
    }
    fn editor_open(&self) -> bool {
        false
    }
    /// Show the device's own window, titled `title`.
    fn open_editor(&mut self, _title: &str) -> Result<()> {
        anyhow::bail!("this device has no editor")
    }
    fn close_editor(&mut self) {}
    /// Frames by which the device's output is behind its input, for devices
    /// that look ahead. The host holds everything else back to match. Asked
    /// again whenever the device is idled, since a setting can change it.
    fn latency(&self) -> u32 {
        0
    }
    /// Say that the device is about to render faster than real time, into
    /// a file: called once, on the main thread, before its first block. A
    /// plugin told this can do at once what it would otherwise leave to a
    /// background thread, and take its time over quality.
    fn set_offline(&mut self, _offline: bool) {}
    /// Why the device has stopped working, if it has: a plugin running in
    /// a process of its own that crashed, hung or was ended. Asked
    /// regularly; a device that is well says nothing.
    fn health(&mut self) -> Option<String> {
        None
    }
    /// Blocks the device did not deliver in time (a plugin in a helper
    /// process that was late), since it was made.
    fn late_blocks(&self) -> u64 {
        0
    }
    /// A request from a script, for devices that are fed from outside the
    /// timeline: `method` names it, `data` is whatever bytes it takes, and the
    /// answer is bytes too, so it can cross `paw.api` as plain strings.
    fn call(&mut self, method: &str, _data: &[u8]) -> Result<Vec<u8>> {
        anyhow::bail!("this device has no method `{method}`")
    }
    /// The same request as [`call`](Self::call), made into a message for
    /// the device's audio side ([`Device::message`]), so that it can act
    /// on an exact frame of the song: an LV2 property set with a
    /// `patch:Set`. None when the request can only be made on the main
    /// thread, as a call. Nothing changes in the device until the message
    /// is handed to it.
    fn prepare(&mut self, _method: &str, _data: &[u8]) -> Result<Option<Vec<u8>>> {
        Ok(None)
    }
    /// The processor time the device's own process has used, for a device
    /// that runs in one (a plugin in its helper): a render waits after a
    /// new state until this stops growing, which is when a plugin that
    /// loads in the background has finished. None in this process.
    fn busy_time(&mut self) -> Option<std::time::Duration> {
        None
    }
    /// What it takes and gives besides its main stereo pair, as this
    /// instance has it.
    fn ports(&self) -> Ports {
        Ports::default()
    }
}

/// A new device, with its controller if it has one.
pub struct Instance {
    pub device: Box<dyn Device>,
    pub controller: Option<Box<dyn Controller>>,
}

impl Instance {
    pub fn simple(device: impl Device + 'static) -> Self {
        Self {
            device: Box::new(device),
            controller: None,
        }
    }
}

/// One parameter of a device, described the same way for every kind of
/// device: built-in, CLAP, VST3, LV2 or a Lua device.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ParamInfo {
    /// The identifier used in projects and scripts. Unique within a device.
    pub key: String,
    /// The device's own id for the parameter, which stays the same in a new
    /// version of the device even when the parameters are put in another
    /// order or renamed: a CLAP parameter id or a VST3 `ParamID` (in
    /// decimal), an LV2 port symbol. Empty for a device whose parameters
    /// have no id other than their key (see [`stable_id`](Self::stable_id)).
    pub id: String,
    /// The name to show.
    pub name: String,
    /// The group the parameter is in, levels joined by `/` ("Osc 1/Pitch"),
    /// where the device says; else empty.
    pub group: String,
    pub min: f32,
    pub max: f32,
    pub default: f32,
    pub unit: String,
    /// Names for integer steps, for parameters that choose between options.
    pub choices: Vec<String>,
    /// For a parameter that takes only some values: how many equal steps
    /// there are from `min` to `max` (one less than the values it takes).
    /// 0 for a continuous parameter.
    pub steps: u32,
    /// The parameter is a switch: off at `min`, on at `max`.
    pub boolean: bool,
    /// Each step is a named option, as `choices` names them or else as
    /// the device writes them (see [`Controller::value_text`]).
    pub enumeration: bool,
    /// The host may automate it (most parameters).
    pub automatable: bool,
    /// The device shows it, but does not take values for it.
    pub read_only: bool,
    /// The format lets it take a different value for each note (CLAP's
    /// per-note automation or modulation).
    pub per_note: bool,
}

impl ParamInfo {
    pub fn new(name: &str, min: f32, max: f32, default: f32, unit: &str) -> Self {
        Self {
            key: name.into(),
            name: name.into(),
            min,
            max,
            default,
            unit: unit.into(),
            automatable: true,
            ..Self::default()
        }
    }

    pub fn choice(name: &str, choices: &[&str], default: usize) -> Self {
        Self {
            max: (choices.len() - 1) as f32,
            choices: choices.iter().map(|s| s.to_string()).collect(),
            steps: (choices.len() - 1) as u32,
            enumeration: true,
            ..Self::new(name, 0.0, 0.0, default as f32, "")
        }
    }

    /// The device's own id for the parameter: [`id`](Self::id), or the key
    /// for a device that gives none.
    pub fn stable_id(&self) -> &str {
        if self.id.is_empty() {
            &self.key
        } else {
            &self.id
        }
    }

    /// What kind of value it takes: `boolean`, `enum` (named steps),
    /// `stepped` (whole steps) or `continuous`.
    pub fn kind(&self) -> &'static str {
        if self.boolean {
            "boolean"
        } else if self.enumeration || !self.choices.is_empty() {
            "enum"
        } else if self.steps > 0 {
            "stepped"
        } else {
            "continuous"
        }
    }

    /// The number of the step nearest to `value`, for a parameter that
    /// takes steps (one with choices takes one step for each).
    pub fn step_of(&self, value: f64) -> Option<usize> {
        let steps = match self.steps {
            0 => self.choices.len().checked_sub(1).filter(|&n| n > 0)? as u32,
            n => n,
        };
        let span = self.max as f64 - self.min as f64;
        if span <= 0.0 {
            return Some(0);
        }
        let at = ((value - self.min as f64) / span * steps as f64).round();
        Some(at.clamp(0.0, steps as f64) as usize)
    }

    /// The value of step `step` (see [`step_of`](Self::step_of)).
    fn step_value(&self, step: usize) -> f64 {
        let steps = match self.steps {
            0 => self.choices.len().saturating_sub(1).max(1) as u32,
            n => n,
        };
        self.min as f64 + (self.max as f64 - self.min as f64) * step as f64 / steps as f64
    }

    /// A value as text, where the device has no text of its own for it: the
    /// name of a step, `on` or `off`, or the number in its unit, written as
    /// paw writes it everywhere (`2.5 kHz`, `-18.0 dB`, `120 ms`; the same
    /// rules as `paw.params.format`).
    pub fn format(&self, value: f64) -> String {
        if self.boolean && self.choices.is_empty() {
            let on = value > (self.min as f64 + self.max as f64) / 2.0;
            return if on { "on" } else { "off" }.into();
        }
        if let Some(choice) = self
            .step_of(value)
            .and_then(|at| self.choices.get(at))
        {
            return choice.clone();
        }
        let v = value;
        match self.unit.as_str() {
            "dB" => format!("{v:.1} dB"),
            "Hz" if v >= 1000.0 => format!("{} kHz", trim(v / 1000.0, if v >= 10000.0 { 1 } else { 2 })),
            "Hz" => format!("{} Hz", trim(v, if v < 100.0 { 1 } else { 0 })),
            "ms" if v >= 1000.0 => format!("{} s", trim(v / 1000.0, 2)),
            "ms" => format!("{} ms", trim(v, if v < 10.0 { 2 } else if v < 100.0 { 1 } else { 0 })),
            "s" if v < 1.0 => {
                let digits = if v < 0.01 { 2 } else if v < 0.1 { 1 } else { 0 };
                format!("{} ms", trim(v * 1000.0, digits))
            }
            "s" => format!("{} s", trim(v, if v < 10.0 { 2 } else { 1 })),
            ":1" if v >= self.max as f64 && self.max >= 50.0 => "∞:1".into(),
            ":1" => format!("{}:1", trim(v, if v < 10.0 { 1 } else { 0 })),
            "%" => format!("{} %", trim(v, 0)),
            "Q" => trim(v, if v < 10.0 { 2 } else { 1 }),
            "st" => format!("{} st", trim(v, 2)),
            "ct" => format!("{} ct", trim(v, 0)),
            unit => {
                let range = self.max as f64 - self.min as f64;
                let digits = if range >= 100.0 {
                    0
                } else if range >= 10.0 {
                    1
                } else if range > 2.0 {
                    2
                } else {
                    3
                };
                let number = format!("{v:.digits$}");
                if unit.is_empty() { number } else { format!("{number} {unit}") }
            }
        }
    }

    /// The value text stands for, where the device has no reading of its
    /// own: the name of a step, `on` or `off`, or a number, with the
    /// parameter's unit or a larger or smaller one after it ("2.5 kHz" for
    /// a parameter in Hz). None when the text is none of these.
    pub fn parse(&self, text: &str) -> Option<f64> {
        let text = text.trim();
        if let Some(at) = self.choices.iter().position(|c| c.eq_ignore_ascii_case(text)) {
            return Some(self.step_value(at));
        }
        if self.boolean {
            match text.to_ascii_lowercase().as_str() {
                "on" | "true" | "yes" => return Some(self.max as f64),
                "off" | "false" | "no" => return Some(self.min as f64),
                _ => {}
            }
        }
        let end = text
            .char_indices()
            .find(|&(i, c)| {
                let sign = i == 0 && (c == '-' || c == '+');
                !(c.is_ascii_digit() || c == '.' || sign || c == 'e' || c == 'E')
            })
            .map_or(text.len(), |(i, _)| i);
        let value: f64 = text[..end].parse().ok()?;
        // A unit of another size than the parameter's: "2.5 kHz", "1.2 s".
        let scale = match (text[end..].trim(), self.unit.as_str()) {
            ("kHz" | "khz", "Hz") | ("s", "ms") => 1000.0,
            ("Hz" | "hz", "kHz") | ("ms", "s") => 0.001,
            _ => 1.0,
        };
        let value = value * scale;
        value.is_finite().then_some(value)
    }
}

/// A number with at most `digits` decimals and no zeros at the end.
fn trim(value: f64, digits: usize) -> String {
    let mut text = format!("{value:.digits$}");
    if digits > 0 {
        text = text.trim_end_matches('0').trim_end_matches('.').to_string();
    }
    if text == "-0" { "0".into() } else { text }
}

/// Turn display names into keys: lower case, words joined by `_`, and a
/// number appended where two names would otherwise collide.
pub fn assign_keys(params: &mut [ParamInfo]) {
    let mut seen: BTreeMap<String, u32> = BTreeMap::new();
    for param in params {
        let mut key = String::new();
        for ch in param.name.chars() {
            if ch.is_alphanumeric() {
                key.extend(ch.to_lowercase());
            } else if !key.ends_with('_') && !key.is_empty() {
                key.push('_');
            }
        }
        let key = key.trim_end_matches('_').to_string();
        let key = if key.is_empty() {
            "param".to_string()
        } else {
            key
        };
        let count = seen.entry(key.clone()).or_insert(0);
        *count += 1;
        param.key = if *count == 1 {
            key
        } else {
            format!("{key}_{count}")
        };
    }
}

#[derive(Clone, Debug, Default)]
pub struct DeviceInfo {
    /// The identifier used in projects and scripts, such as `synth` or
    /// `clap:org.surge-synth-team.surge-xt`.
    pub kind: String,
    pub name: String,
    /// `instrument` or `effect`.
    pub category: String,
    /// `builtin`, `clap`, `lv2` or `vst3`.
    pub format: String,
    pub vendor: String,
    /// The plugin's own id, as its format names it: a CLAP plugin id, a
    /// VST3 class id (the 16 bytes as 32 hex digits), an LV2 URI. Empty for
    /// a device that is not a plugin.
    pub id: String,
    /// The version the plugin gives, where it gives one.
    pub version: String,
    /// Empty for devices whose parameters are only known per instance.
    pub params: Vec<ParamInfo>,
    /// What the plugin says it is, in its format's words: a CLAP plugin's
    /// features (`audio-effect`, `ara:supported`). Empty for others.
    pub features: Vec<String>,
}

/// Creates device instances. Lives on the main thread.
pub trait DeviceFactory {
    fn info(&self) -> &DeviceInfo;
    /// The new device starts with every parameter at its default.
    fn create(&self, sample_rate: f32, max_block: usize) -> Result<Instance>;
    /// Frames of latency of a device that has no [`Controller`] to ask.
    fn latency(&self, _sample_rate: f32) -> u32 {
        0
    }
    /// The ports of a device that has no [`Controller`] to ask.
    fn ports(&self) -> Ports {
        Ports::default()
    }
    /// Whether [`start`](Self::start) makes this device without the main
    /// thread waiting for it: a plugin in a process of its own, which may
    /// take long or hang while it is made.
    fn starts_apart(&self) -> bool {
        false
    }
    /// Begin making a device, with `state` (as its controller saved it)
    /// loaded into it, and return at once; [`Starting::poll`] gives the
    /// result. None for factories that only make devices in [`create`].
    ///
    /// [`create`]: Self::create
    fn start(
        &self,
        _sample_rate: f32,
        _max_block: usize,
        _state: Option<Vec<u8>>,
    ) -> Option<Box<dyn Starting>> {
        None
    }
}

/// A device that is being made apart from the main thread (see
/// [`DeviceFactory::start`]). Dropping it gives up on the device.
pub trait Starting {
    /// The device once it is made, with its state loaded; why it could not
    /// be made; or None while that is not known yet. Asked on the main
    /// thread, and never blocks.
    fn poll(&mut self) -> Option<Result<Instance>>;
}

/// A [`DeviceFactory`] made from a descriptor and a constructor function.
pub struct FnFactory {
    pub info: DeviceInfo,
    pub make: fn(f32) -> Box<dyn Device>,
    /// Seconds by which the device's output is behind its input.
    pub latency: f32,
    /// The names of its output pairs, for a device with more than one.
    pub outputs: &'static [&'static str],
}

impl DeviceFactory for FnFactory {
    fn info(&self) -> &DeviceInfo {
        &self.info
    }

    fn create(&self, sample_rate: f32, _max_block: usize) -> Result<Instance> {
        Ok(Instance {
            device: (self.make)(sample_rate),
            controller: None,
        })
    }

    fn latency(&self, sample_rate: f32) -> u32 {
        (self.latency * sample_rate).round() as u32
    }

    fn ports(&self) -> Ports {
        Ports {
            outputs: self.outputs.iter().map(|s| s.to_string()).collect(),
            ..Ports::default()
        }
    }
}

/// Every device kind the session can instantiate, by kind name. It stays on
/// the main thread, like the factories in it.
/// Looks for plugins again and registers what it finds: see [`Registry::rescan`].
pub type Rescan = Rc<dyn Fn(&mut Registry, Option<&str>) -> Vec<String>>;

/// Looks for plugins in one more directory and registers what it finds
/// there: see [`Registry::add_dir`].
pub type AddDir = Rc<dyn Fn(&mut Registry, &std::path::Path) -> (Vec<String>, Vec<String>)>;

/// Stops looking for plugins in a directory added before: see
/// [`Registry::remove_dir`].
pub type RemoveDir = Rc<dyn Fn(&std::path::Path)>;

/// Loads an attachment for plugins: see [`Registry::attach`].
pub type Attach = Rc<dyn Fn(&std::path::Path) -> Result<String>>;

#[derive(Default, Clone)]
pub struct Registry {
    factories: BTreeMap<String, Rc<dyn DeviceFactory>>,
    rescan: Option<Rescan>,
    add_dir: Option<AddDir>,
    remove_dir: Option<RemoveDir>,
    attach: Option<Attach>,
    /// What scripts posted to every device of a kind: by kind, each topic
    /// with its latest data, in the order the topics were first posted.
    posts: BTreeMap<String, Vec<(String, Arc<[u8]>)>>,
    /// Kinds that were renamed, and what they are called now.
    aliases: BTreeMap<String, String>,
}

impl Registry {
    pub fn with_builtins() -> Self {
        let mut registry = Self::default();
        crate::devices::register(&mut registry);
        registry
    }

    pub fn register(&mut self, factory: Rc<dyn DeviceFactory>) {
        self.factories.insert(factory.info().kind.clone(), factory);
    }

    /// Make no more devices of `kind` (an extension that brought it was
    /// taken away); devices already made go on. Returns whether it was there.
    pub fn unregister(&mut self, kind: &str) -> bool {
        self.factories.remove(kind).is_some()
    }

    /// Say how to stop looking in a directory added with [`Registry::add_dir`].
    pub fn set_remove_dir(&mut self, remove_dir: RemoveDir) {
        self.remove_dir = Some(remove_dir);
    }

    /// Look in `dir` no more (later rescans leave it out), and make no more
    /// devices of `kinds`, those found there.
    pub fn remove_dir(&mut self, dir: &std::path::Path, kinds: &[String]) {
        if let Some(remove_dir) = self.remove_dir.clone() {
            remove_dir(dir);
        }
        for kind in kinds {
            self.unregister(kind);
        }
    }

    /// Say how to look for plugins again (the program that found them knows).
    pub fn set_rescan(&mut self, rescan: Rescan) {
        self.rescan = Some(rescan);
    }

    /// Say how to look for plugins in a directory of one's choosing.
    pub fn set_add_dir(&mut self, add_dir: AddDir) {
        self.add_dir = Some(add_dir);
    }

    /// Look for plugins in `dir` too from now on, and register those in it:
    /// the device kinds found there, and notes on what could not be used.
    /// `None` when there is nothing to do it with.
    pub fn add_dir(&mut self, dir: &std::path::Path) -> Option<(Vec<String>, Vec<String>)> {
        let add_dir = self.add_dir.clone()?;
        Some(add_dir(self, dir))
    }

    /// Say how to load an attachment for plugins.
    pub fn set_attach(&mut self, attach: Attach) {
        self.attach = Some(attach);
    }

    /// Load the attachment in `path` (a native library an extension ships,
    /// offered every plugin made from now on). Its name; an error when
    /// there is nothing to load it with or it cannot be loaded.
    pub fn attach(&mut self, path: &std::path::Path) -> Result<String> {
        let attach = self
            .attach
            .clone()
            .ok_or_else(|| anyhow::anyhow!("this program hosts no plugins"))?;
        attach(path)
    }

    /// Look into plugin files again: all of them, or those `name` matches.
    /// `None` when there is nothing to do it with. The answer is notes on
    /// what could not be used.
    pub fn rescan(&mut self, name: Option<&str>) -> Option<Vec<String>> {
        let rescan = self.rescan.clone()?;
        Some(rescan(self, name))
    }

    pub fn get(&self, kind: &str) -> Option<&Rc<dyn DeviceFactory>> {
        self.factories.get(kind).or_else(|| {
            self.aliases
                .get(kind)
                .and_then(|now| self.factories.get(now))
        })
    }

    /// Make devices of `old`, a kind that was renamed, as `new`: projects
    /// saved before the rename keep working.
    pub fn alias(&mut self, old: &str, new: &str) {
        self.aliases.insert(old.to_string(), new.to_string());
    }

    /// What a kind is called now: itself, unless it was renamed.
    pub fn resolve<'a>(&'a self, kind: &'a str) -> &'a str {
        match self.aliases.get(kind) {
            Some(now) if !self.factories.contains_key(kind) => now,
            _ => kind,
        }
    }

    pub fn iter(&self) -> impl Iterator<Item = &Rc<dyn DeviceFactory>> {
        self.factories.values()
    }

    /// Keep `data` as the latest under `topic` for devices of `kind`, to be
    /// given to every one made from now on (a render's included) through
    /// [`Controller::call`] before its first block; `None` forgets the topic.
    pub fn post(&mut self, kind: &str, topic: &str, data: Option<Arc<[u8]>>) {
        let posts = self.posts.entry(kind.to_string()).or_default();
        match (posts.iter().position(|(t, _)| t == topic), data) {
            (Some(at), Some(data)) => posts[at].1 = data,
            (None, Some(data)) => posts.push((topic.to_string(), data)),
            (Some(at), None) => {
                posts.remove(at);
            }
            (None, None) => {}
        }
    }

    /// What is posted to devices of `kind`: each topic and its latest data.
    pub fn posts(&self, kind: &str) -> &[(String, Arc<[u8]>)] {
        self.posts
            .get(self.resolve(kind))
            .map_or(&[], Vec::as_slice)
    }
}

/// The files a device keeps beside its state ([`FILE_SAVE`]), packed into
/// one answer: for each, its name's length (4 bytes, little-endian), the
/// name, its length (8 bytes) and its bytes.
pub fn pack_files(files: &[(String, Vec<u8>)]) -> Vec<u8> {
    let mut out = Vec::new();
    for (name, bytes) in files {
        out.extend_from_slice(&(name.len() as u32).to_le_bytes());
        out.extend_from_slice(name.as_bytes());
        out.extend_from_slice(&(bytes.len() as u64).to_le_bytes());
        out.extend_from_slice(bytes);
    }
    out
}

/// The files that [`pack_files`] packed.
pub fn unpack_files(mut data: &[u8]) -> Result<Vec<(String, Vec<u8>)>> {
    fn take<'a>(data: &mut &'a [u8], n: usize) -> Result<&'a [u8]> {
        anyhow::ensure!(data.len() >= n, "the files end too early");
        let (head, rest) = data.split_at(n);
        *data = rest;
        Ok(head)
    }
    let mut files = Vec::new();
    while !data.is_empty() {
        let n = u32::from_le_bytes(take(&mut data, 4)?.try_into()?) as usize;
        let name = String::from_utf8(take(&mut data, n)?.to_vec())?;
        let n = u64::from_le_bytes(take(&mut data, 8)?.try_into()?) as usize;
        files.push((name, take(&mut data, n)?.to_vec()));
    }
    Ok(files)
}

/// The call that asks a device for the files it keeps beside its state in
/// the project, packed ([`pack_files`]); a device without such files does
/// not know the method.
pub const FILE_SAVE: &str = "paw.file.save";
/// The call that gives a device made again the files it kept, packed.
pub const FILE_LOAD: &str = "paw.file.load";
/// The call that gives a device the audio clips of its track, as JSON, each
/// time they or the tempo change; a device that does not take clips does
/// not know the method, and is not asked again.
pub const CLIPS: &str = "paw.clips";

#[cfg(test)]
mod tests {
    use super::*;


    #[test]
    fn a_parameter_says_what_kind_of_value_it_takes() {
        let gain = ParamInfo::new("Gain", -24.0, 24.0, 0.0, "dB");
        assert_eq!(gain.kind(), "continuous");
        assert_eq!(gain.stable_id(), "Gain", "a built-in parameter's id is its key");
        assert!(gain.automatable);
        let wave = ParamInfo::choice("Wave", &["Sine", "Saw", "Square"], 1);
        assert_eq!((wave.kind(), wave.steps), ("enum", 2));
        let switch = ParamInfo {
            boolean: true,
            steps: 1,
            ..ParamInfo::new("On", 0.0, 1.0, 0.0, "")
        };
        assert_eq!(switch.kind(), "boolean");
        let voices = ParamInfo {
            steps: 15,
            ..ParamInfo::new("Voices", 1.0, 16.0, 8.0, "")
        };
        assert_eq!(voices.kind(), "stepped");
    }

    #[test]
    fn values_read_as_text_and_back() {
        let freq = ParamInfo::new("Freq", 20.0, 20000.0, 1000.0, "Hz");
        assert_eq!(freq.format(2500.0), "2.5 kHz");
        assert_eq!(freq.format(80.0), "80 Hz");
        assert_eq!(freq.parse("2.5 kHz"), Some(2500.0));
        let gain = ParamInfo::new("Gain", -24.0, 24.0, 0.0, "dB");
        assert_eq!(gain.format(-18.0), "-18.0 dB");
        assert_eq!(gain.parse("-6 dB"), Some(-6.0));
        assert_eq!(gain.parse("loud"), None);
        let wave = ParamInfo::choice("Wave", &["Sine", "Saw", "Square"], 1);
        assert_eq!(wave.format(2.0), "Square");
        assert_eq!(wave.parse("saw"), Some(1.0));
        // Steps of a range that is not one apart, as a VST3 list is (0 to 1).
        let list = ParamInfo {
            choices: vec!["A".into(), "B".into(), "C".into()],
            steps: 2,
            enumeration: true,
            ..ParamInfo::new("List", 0.0, 1.0, 0.0, "")
        };
        assert_eq!(list.format(0.5), "B");
        assert_eq!(list.parse("C"), Some(1.0));
        let switch = ParamInfo {
            boolean: true,
            steps: 1,
            ..ParamInfo::new("On", 0.0, 1.0, 0.0, "")
        };
        assert_eq!(switch.format(1.0), "on");
        assert_eq!(switch.parse("off"), Some(0.0));
    }
}
