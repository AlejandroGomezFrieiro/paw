//! URIDs: the host's map of URIs to numbers, and the ones paw uses.

use std::ffi::{CStr, CString, c_char, c_void};
use std::ptr;
use std::sync::{Mutex, OnceLock};


use crate::lv2_patch::PatchUrids;

// --- URIDs -------------------------------------------------------------------

/// Every URI any plugin or the host has asked a number for. Numbers start at 1.
pub(super) static URIDS: Mutex<Vec<CString>> = Mutex::new(Vec::new());

pub(super) fn urid(uri: &CStr) -> u32 {
    let mut uris = URIDS.lock().unwrap();
    match uris.iter().position(|known| known.as_c_str() == uri) {
        Some(index) => index as u32 + 1,
        None => {
            uris.push(uri.to_owned());
            uris.len() as u32
        }
    }
}

pub(super) unsafe extern "C" fn urid_map(_: *mut c_void, uri: *const c_char) -> u32 {
    urid(unsafe { CStr::from_ptr(uri) })
}

pub(super) unsafe extern "C" fn urid_unmap(_: *mut c_void, id: u32) -> *const c_char {
    let uris = URIDS.lock().unwrap();
    // The string's buffer stays where it is for the life of the program.
    uris.get(id.wrapping_sub(1) as usize)
        .map_or(ptr::null(), |uri| uri.as_ptr())
}

pub(super) struct Urids {
    pub(super) sequence: u32,
    pub(super) chunk: u32,
    pub(super) midi_event: u32,
    pub(super) float: u32,
    pub(super) int: u32,
    pub(super) max_block: u32,
    pub(super) min_block: u32,
    pub(super) sample_rate: u32,
    pub(super) event_transfer: u32,
    pub(super) scale_factor: u32,
    pub(super) window_title: u32,
    pub(super) string: u32,
    pub(super) object: u32,
    pub(super) long: u32,
    pub(super) time_position: u32,
    pub(super) time_frame: u32,
    pub(super) time_speed: u32,
    pub(super) time_bar: u32,
    pub(super) time_bar_beat: u32,
    pub(super) time_beat_unit: u32,
    pub(super) time_beats_per_bar: u32,
    pub(super) time_beats_per_minute: u32,
    pub(super) patch: PatchUrids,
}

pub(super) fn urids() -> &'static Urids {
    static KNOWN: OnceLock<Urids> = OnceLock::new();
    KNOWN.get_or_init(|| Urids {
        sequence: urid(c"http://lv2plug.in/ns/ext/atom#Sequence"),
        chunk: urid(c"http://lv2plug.in/ns/ext/atom#Chunk"),
        midi_event: urid(c"http://lv2plug.in/ns/ext/midi#MidiEvent"),
        float: urid(c"http://lv2plug.in/ns/ext/atom#Float"),
        int: urid(c"http://lv2plug.in/ns/ext/atom#Int"),
        max_block: urid(c"http://lv2plug.in/ns/ext/buf-size#maxBlockLength"),
        min_block: urid(c"http://lv2plug.in/ns/ext/buf-size#minBlockLength"),
        sample_rate: urid(c"http://lv2plug.in/ns/ext/parameters#sampleRate"),
        event_transfer: urid(c"http://lv2plug.in/ns/ext/atom#eventTransfer"),
        scale_factor: urid(c"http://lv2plug.in/ns/extensions/ui#scaleFactor"),
        window_title: urid(c"http://lv2plug.in/ns/extensions/ui#windowTitle"),
        string: urid(c"http://lv2plug.in/ns/ext/atom#String"),
        object: urid(c"http://lv2plug.in/ns/ext/atom#Object"),
        long: urid(c"http://lv2plug.in/ns/ext/atom#Long"),
        time_position: urid(c"http://lv2plug.in/ns/ext/time#Position"),
        time_frame: urid(c"http://lv2plug.in/ns/ext/time#frame"),
        time_speed: urid(c"http://lv2plug.in/ns/ext/time#speed"),
        time_bar: urid(c"http://lv2plug.in/ns/ext/time#bar"),
        time_bar_beat: urid(c"http://lv2plug.in/ns/ext/time#barBeat"),
        time_beat_unit: urid(c"http://lv2plug.in/ns/ext/time#beatUnit"),
        time_beats_per_bar: urid(c"http://lv2plug.in/ns/ext/time#beatsPerBar"),
        time_beats_per_minute: urid(c"http://lv2plug.in/ns/ext/time#beatsPerMinute"),
        patch: PatchUrids {
            object: urid(c"http://lv2plug.in/ns/ext/atom#Object"),
            urid: urid(c"http://lv2plug.in/ns/ext/atom#URID"),
            path: urid(c"http://lv2plug.in/ns/ext/atom#Path"),
            string: urid(c"http://lv2plug.in/ns/ext/atom#String"),
            float: urid(c"http://lv2plug.in/ns/ext/atom#Float"),
            double: urid(c"http://lv2plug.in/ns/ext/atom#Double"),
            int: urid(c"http://lv2plug.in/ns/ext/atom#Int"),
            long: urid(c"http://lv2plug.in/ns/ext/atom#Long"),
            bool_: urid(c"http://lv2plug.in/ns/ext/atom#Bool"),
            set: urid(c"http://lv2plug.in/ns/ext/patch#Set"),
            get: urid(c"http://lv2plug.in/ns/ext/patch#Get"),
            property: urid(c"http://lv2plug.in/ns/ext/patch#property"),
            value: urid(c"http://lv2plug.in/ns/ext/patch#value"),
        },
    })
}


