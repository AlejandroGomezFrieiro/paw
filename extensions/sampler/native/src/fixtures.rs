//! Small instruments made of generated sine waves of known pitches, in
//! SFZ and Decent Sampler form, each exercising a feature: what the tests
//! play (here and through paw) and check by pitch and level.
//!
//! Every sample is a sine whose frequency tells it apart: at key 69 the
//! plain one plays 440 Hz, the staccato 660, the round robins 440, 550
//! and 660, the release trigger 880.

use crate::audio::write_wav;
use std::path::Path;

const RATE: u32 = 48000;

fn sine(freq: f64, seconds: f64, level: f32) -> Vec<f32> {
    let n = (seconds * RATE as f64) as usize;
    (0..n)
        .map(|i| (i as f64 / RATE as f64 * freq * std::f64::consts::TAU).sin() as f32 * level)
        .collect()
}

/// The instruments, by file name.
pub const INSTRUMENTS: &[(&str, &str)] = &[
    ("basic.sfz", "<region> sample=a440.wav pitch_keycenter=69 ampeg_release=0.05\n"),
    (
        "rr.sfz",
        "<group> key=69 seq_length=3 ampeg_release=0.02\n\
         <region> sample=rr1.wav seq_position=1\n\
         <region> sample=rr2.wav seq_position=2\n\
         <region> sample=rr3.wav seq_position=3\n",
    ),
    (
        "ks.sfz",
        "// Two articulations on keyswitches C1 and C#1; D1 chooses none.\n\
         <global> sw_lokey=24 sw_hikey=26 sw_default=24 lokey=48 hikey=96 pitch_keycenter=69 ampeg_release=0.02\n\
         <group> sw_last=24 sw_label=Sustain <region> sample=a440.wav\n\
         <group> sw_last=25 sw_label=Staccato <region> sample=e660.wav\n",
    ),
    (
        "vel.sfz",
        "<global> key=69 ampeg_release=0.02 amp_veltrack=0\n\
         <region> sample=a440.wav lovel=1 hivel=63\n\
         <region> sample=e660.wav lovel=64 hivel=127\n",
    ),
    (
        "release.sfz",
        "<region> sample=a440.wav key=69 ampeg_release=0.01\n\
         <region> sample=r880.wav key=69 trigger=release ampeg_release=0.05\n",
    ),
    (
        "loop.sfz",
        "<region> sample=loop.wav key=69 loop_mode=loop_continuous loop_start=4800 loop_end=14399 ampeg_release=0.01\n",
    ),
    ("smpl.sfz", "<region> sample=smpl.wav pitch_keycenter=sample ampeg_release=0.01\n"),
    (
        "delay.sfz",
        "// Staccato's sample starts 30 ms late; pizzicato skips 10 ms of it.\n\
         <global> sw_default=24 key=69\n\
         <group> sw_last=24 sw_label=Sustain <region> sample=a440.wav\n\
         <group> sw_last=25 sw_label=Staccato <region> sample=late.wav\n\
         <group> sw_last=26 sw_label=Pizzicato <region> sample=late.wav offset=480\n",
    ),
    ("envelope.sfz", "<region> sample=*sine ampeg_attack=0.5 ampeg_release=0.3\n"),
    (
        "choke.sfz",
        "<region> sample=a440.wav key=69 group=1 off_by=2 loop_mode=loop_continuous loop_start=0 loop_end=47999\n\
         <region> sample=e660.wav key=71 pitch_keycenter=71 group=2\n",
    ),
    (
        "ks.dspreset",
        r#"<?xml version="1.0" encoding="UTF-8"?>
<DecentSampler minVersion="1.4.0">
  <groups release="0.02">
    <group name="Sustain">
      <sample path="a440.wav" rootNote="69" loNote="48" hiNote="96"/>
    </group>
    <group name="Staccato" enabled="false">
      <sample path="e660.wav" rootNote="69" loNote="48" hiNote="96"/>
    </group>
  </groups>
  <midi>
    <note note="24">
      <binding type="general" level="group" position="0" parameter="ENABLED" translation="fixed_value" translationValue="true"/>
      <binding type="general" level="group" position="1" parameter="ENABLED" translation="fixed_value" translationValue="false"/>
    </note>
    <note note="25">
      <binding type="general" level="group" position="0" parameter="ENABLED" translation="fixed_value" translationValue="false"/>
      <binding type="general" level="group" position="1" parameter="ENABLED" translation="fixed_value" translationValue="true"/>
    </note>
  </midi>
</DecentSampler>
"#,
    ),
    (
        "rr.dspreset",
        r#"<DecentSampler>
  <groups release="0.02" seqMode="round_robin">
    <group>
      <sample path="rr1.wav" rootNote="69" loNote="69" hiNote="69" seqPosition="1"/>
      <sample path="rr2.wav" rootNote="69" loNote="69" hiNote="69" seqPosition="2"/>
      <sample path="rr3.wav" rootNote="69" loNote="69" hiNote="69" seqPosition="3"/>
    </group>
  </groups>
</DecentSampler>
"#,
    ),
];

/// Writes the samples and the instruments into `dir`.
pub fn write(dir: &Path) -> hound::Result<()> {
    std::fs::create_dir_all(dir)?;
    let wav = |name: &str, data: Vec<f32>, key: Option<u8>, l: Option<(u32, u32)>| {
        write_wav(&dir.join(name), RATE, 1, &data, key, l)
    };
    wav("a440.wav", sine(440.0, 1.0, 0.5), Some(69), None)?;
    wav("e660.wav", sine(660.0, 1.0, 0.5), Some(69), None)?;
    wav("rr1.wav", sine(440.0, 0.5, 0.5), Some(69), None)?;
    wav("rr2.wav", sine(550.0, 0.5, 0.5), Some(69), None)?;
    wav("rr3.wav", sine(660.0, 0.5, 0.5), Some(69), None)?;
    wav("r880.wav", sine(880.0, 0.3, 0.5), Some(69), None)?;
    // 480 Hz: a period of exactly 100 frames, so a loop of whole periods
    // joins without a step.
    wav("loop.wav", sine(480.0, 0.4, 0.5), Some(69), None)?;
    // 30 ms of silence before the sound.
    let mut late = vec![0.0f32; 1440];
    late.extend(sine(660.0, 0.5, 0.5));
    wav("late.wav", late, Some(69), None)?;
    // Its own key (A3) and loop in the file's `smpl` chunk.
    wav("smpl.wav", sine(220.0, 0.25, 0.5), Some(57), Some((2400, 7199)))?;
    for (name, text) in INSTRUMENTS {
        std::fs::write(dir.join(name), text)?;
    }
    Ok(())
}
