//! paw's sample player: SFZ and Decent Sampler instruments read into one
//! model (`model`), played by a real-time voice engine (`engine`), as a
//! CLAP plugin (`plugin`) with articulations chosen per note by MIDI 2.0
//! attribute (`m2`) or by keyswitch.

pub mod audio;
pub mod describe;
pub mod engine;
pub mod error;
pub mod fixtures;
pub mod formats;
pub mod interp;
pub mod m2;
pub mod model;
pub mod params;
pub mod plugin;
