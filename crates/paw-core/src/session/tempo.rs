//! Editing the tempo map: tempo and signature points along the song.

use anyhow::{Result, bail};
use paw_engine::tempo::EPS;
use paw_engine::{SigPoint, TempoMap, TempoPoint};

use super::Session;

fn check_bpm(bpm: f64) -> Result<()> {
    if !(1.0..=999.0).contains(&bpm) {
        bail!("a tempo is between 1 and 999 BPM, not {bpm}");
    }
    Ok(())
}

fn check_beat(beat: f64) -> Result<()> {
    if !beat.is_finite() || !(0.0..=1e9).contains(&beat) {
        bail!("a tempo or signature change goes at a beat from 0 up, not {beat}");
    }
    Ok(())
}

fn check_sig(num: u32, den: u32) -> Result<()> {
    if !(1..=64).contains(&num) || !(1..=64).contains(&den) {
        bail!("a time signature is from 1/1 to 64/64, not {num}/{den}");
    }
    Ok(())
}

impl Session {
    /// Replace every tempo and signature point at once. Audio clips keep
    /// to time as their timebase says.
    pub fn tempo_set_points(&mut self, tempos: Vec<TempoPoint>, sigs: Vec<SigPoint>) -> Result<()> {
        for p in &tempos {
            check_beat(p.beat)?;
            check_bpm(p.bpm)?;
        }
        for p in &sigs {
            check_beat(p.beat)?;
            check_sig(p.num, p.den)?;
        }
        if tempos.is_empty() || sigs.is_empty() {
            bail!("a tempo map needs at least one tempo and one signature");
        }
        // The same map again changes nothing, and makes no undo step.
        if tempos == self.doc.project.tempo_points() && sigs == self.doc.project.sig_points() {
            return Ok(());
        }
        self.edit(|p| {
            p.retime(TempoMap::new(&tempos, &sigs));
            Ok(())
        })
    }

    /// Set the tempo from `beat` on, adding a point there or changing the
    /// one that is there. `ramp` left out keeps what the point had, or holds.
    pub fn tempo_set(&mut self, beat: f64, bpm: f64, ramp: Option<bool>) -> Result<()> {
        check_beat(beat)?;
        check_bpm(bpm)?;
        let mut tempos = self.doc.project.tempo_points();
        let sigs = self.doc.project.sig_points();
        match tempos.iter_mut().find(|p| (p.beat - beat).abs() < EPS) {
            Some(p) => {
                p.bpm = bpm;
                p.ramp = ramp.unwrap_or(p.ramp);
            }
            None => tempos.push(TempoPoint {
                beat,
                bpm,
                ramp: ramp.unwrap_or(false),
            }),
        }
        self.tempo_set_points(tempos, sigs)
    }

    /// Remove the tempo point at `beat`. The one at the start stays.
    pub fn tempo_remove(&mut self, beat: f64) -> Result<()> {
        let mut tempos = self.doc.project.tempo_points();
        let Some(i) = tempos.iter().position(|p| (p.beat - beat).abs() < 1e-6) else {
            bail!("there is no tempo change at beat {beat}");
        };
        if i == 0 {
            bail!("the tempo at the start stays: set it instead");
        }
        tempos.remove(i);
        let sigs = self.doc.project.sig_points();
        self.tempo_set_points(tempos, sigs)
    }

    /// Start a bar of `num`/`den` at `beat`, or change the signature that
    /// starts there.
    pub fn signature_set(&mut self, beat: f64, num: u32, den: u32) -> Result<()> {
        check_beat(beat)?;
        check_sig(num, den)?;
        let tempos = self.doc.project.tempo_points();
        let mut sigs = self.doc.project.sig_points();
        match sigs.iter_mut().find(|p| (p.beat - beat).abs() < 1e-6) {
            Some(p) => (p.num, p.den) = (num, den),
            None => sigs.push(SigPoint { beat, num, den }),
        }
        self.tempo_set_points(tempos, sigs)
    }

    /// Remove the signature change at `beat`. The one at the start stays.
    pub fn signature_remove(&mut self, beat: f64) -> Result<()> {
        let mut sigs = self.doc.project.sig_points();
        let Some(i) = sigs.iter().position(|p| (p.beat - beat).abs() < 1e-6) else {
            bail!("there is no signature change at beat {beat}");
        };
        if i == 0 {
            bail!("the signature at the start stays: set it instead");
        }
        sigs.remove(i);
        let tempos = self.doc.project.tempo_points();
        self.tempo_set_points(tempos, sigs)
    }
}
