//! The parts of the terminal frontend that code outside the `paw` binary
//! drives: the fuzz targets in `fuzz/` feed [`keys::Joiner`] the events of
//! a terminal, as the program does.

pub mod keys;
