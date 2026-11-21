# Media speeds: stretch, decode, hash and stat

These numbers decide the limits of the media design. They show when a
stretch is live or baked and how long an import takes. They show how a
file is hashed and what a check of many files costs. All numbers come from one machine
on 2026-11-21: an AMD Ryzen AI 9 HX 370 (24 threads), a solid-state disk
and ext4.

## How the numbers were made

The harness is [media/](media). It runs each case 7 times. Each value is
the median, with the smallest and the largest value after it. Each run was
short. It ran under the shared lock (`flock`), on the processors 16 to 23
(`taskset`). The machine was busy with other work. The load average was
between 20 and 47 on 24 threads. These numbers were measured under
external load. They are lower than the speeds of a quiet machine, and a
difference smaller than the spread is no measurable difference.

```sh
CARGO_TARGET_DIR=/tmp/paw-media-bench nix develop -c cargo build --release --manifest-path bench/media/Cargo.toml
bench/media/run.sh /tmp/paw-media-bench/release/media-bench <data folder>
```

The data folder holds files that `ffmpeg` made. The source is one
synthetic stereo signal (chords and noise, 300 s, 44.1 kHz). The files are
`src.wav`, `t.flac`, `t.mp3` (192 kbit/s) and `t.m4a` (AAC, 192 kbit/s). `big8.wav` is 20 minutes
of pink noise, 8 channels, 24 bit, 48 kHz (1.4 GB). `small.wav` is the first
0.5 MB of `src.wav`. The `stat` folder holds 10 000 files of 64 bytes.
Synthetic sound is a fair test of speed, but a real recording can decode a
little faster or slower, most of all in FLAC.

## Stretch

The stretch is `stretch::render` on 60 s of stereo sound at 44.1 kHz, with
one thread. The value is the seconds of output for each second of wall
time ("x real time").

| Mode | Ratio | Pitch | Speed (x real time) |
| --- | ---: | ---: | ---: |
| tonal | 0.5 | 0 | 90.6 (88.9 to 91.9) |
| tonal | 1.25 | 0 | 91.4 (89.8 to 92.3) |
| tonal | 2 | 0 | 88.3 (57.0 to 92.9) |
| tonal | 1 | +3 | 44.3 (23.3 to 52.1) |
| tonal, formants kept | 1 | +3 | 45.2 (40.9 to 46.6) |
| percussive | 0.5 | 0 | 330.6 (303.8 to 331.8) |
| percussive | 1.25 | 0 | 305.9 (302.8 to 315.3) |
| percussive | 2 | 0 | 300.0 (298.2 to 303.4) |
| percussive | 1 | +3 | 96.9 (84.9 to 99.3) |
| auto (chose tonal) | 1.25 | 0 | 69.6 (61.6 to 73.3) |

What this means:

- The ratio does not change the speed. The mode and a pitch shift do.
- A pitch shift costs a resample on top of the stretch, so it runs at half
  the speed. The vocoder with formants costs the same as without.
- `auto` is slower than `tonal` because it first looks for onsets in the
  whole sound (about 30% more time on this sound).
- Tonal is the slow mode: a 4 minute song stretches in 2.7 s, a
  1 hour recording in 40 s. One 8 bar part of 16 s bakes in under
  0.2 s. A part bakes faster than a user can drag a marker, so baking by
  part is fast enough to keep the rough preview short. The percussive mode
  is 3 times faster.
- These are single-thread speeds. Parts of one clip are independent, so
  the scheduler can run several at once.

## Decode

The value is the seconds of sound for each second of wall time, from a
file in the page cache, to planes of `f32`. `symphonia` is the decoder
alone. `AudioData::load` is the loader of paw: it also keeps the sound in
a sink and copies it to stereo.

| File | symphonia | `AudioData::load` |
| --- | ---: | ---: |
| WAV (16 bit) | 2182 (1718 to 2290) | 1199 (866 to 1357) |
| FLAC | 1641 (1221 to 1649) | 945 (869 to 1270) |
| MP3, 192 kbit/s | 671 (466 to 719) | 513 (392 to 590) |
| AAC in MP4, 192 kbit/s | 502 (387 to 873) | not readable today |

What this means:

- The slowest codec decodes 500 seconds of sound each second. An import
  of a 4 minute song takes under 0.6 s, and a 1 hour file takes 7 s.
  Decoding is not what makes a part wait. The stretch is.
- paw builds `symphonia` without the `aac` and `isomp4` features, so it
  cannot read AAC today. The numbers show that adding them is cheap, in
  speed. The features add two small pure Rust crates.
- The loader of paw runs at 60 to 75% of the decoder alone. The rest is
  the copy into the sink. This is no reason to change it.

## BLAKE3

The value is the megabytes of file for each second. A warm file is in the
page cache. A cold file was dropped from it with `posix_fadvise` first,
so the read comes from the disk. "1 thread" reads through
`Hasher::update_reader`, "rayon" is `update_mmap_rayon`, a memory map
on the 8 processors.

| File | Warm, 1 thread | Warm, rayon | Cold, 1 thread | Cold, rayon |
| --- | ---: | ---: | ---: | ---: |
| 0.5 MB | 2368 (350 to 2740) | 2824 (161 to 2959) | 470 (46 to 980) | 535 (200 to 999) |
| 53 MB | 2231 (1558 to 2264) | 1630 (801 to 2391) | 568 (475 to 898) | 680 (575 to 876) |
| 1.4 GB | 3178 (3002 to 3426) | 11136 (9881 to 12229) | 908 (569 to 1076) | 3663 (3073 to 4273) |

Start to finish, cold, the 0.5 MB file takes 0.5 ms. The 53 MB file takes
88 ms (70 to 115). The 1.4 GB file takes 321 ms (310 to 331).

What this means:

- One thread hashes 2.2 to 3.2 GB/s from memory. A 50 MB sample set
  takes 25 ms, so a hash is no cost for a sample or a song.
- On a cold solid-state disk, one thread reads at 0.5 to 0.9 GB/s, and a memory map with
  rayon reads at 0.7 to 3.7 GB/s, because it keeps many reads in flight.
  Only a big file gains much. The gain at 53 MB is inside the spread, and
  warm, 8 threads were slower than one at that size. So
  `media::hash::PARALLEL_MIN` is 64 MiB: below it, one thread; from it,
  a memory map and rayon.
- A project of 40 GB hashes in 11 s on this disk, with rayon, and in
  about 45 s with one thread. A spinning disk is the slow case (the
  design counts 5 minutes). There the disk limits the speed, not the
  hash.
- Reading the file into a `Vec` first and hashing after is about 4 times
  slower than `update_reader` on a big file. Do not do it.

## stat

The folder had 10 000 files, with warm kernel caches of their names and
attributes. A cold cache cannot be measured without the privilege to drop
it, so it is not in the table.

| Work | Time (ms) |
| --- | ---: |
| `read_dir` of the names | 2.2 (2.2 to 2.4) |
| `fs::metadata` of each file (size and change time) | 8.7 (8.3 to 9.4) |
| `read_dir` and the metadata of each entry | 9.2 (8.3 to 9.7) |

The check of the local index at project open is one `stat` of each source
(0.9 microsecond each when warm). 10 000 sources cost 9 ms. A check at
each open is cheap, and the index needs no watcher.

## What the numbers decide

- **Hash while the bytes pass, and with one thread** for the files of an
  import. The hash is not slower than the disk.
- **Hash a whole big file on all cores** (`media::hash::file` does it from
  64 MiB). A worker thread that hashes in the background can still use
  fewer threads. That is a choice of the scheduler, not of the hash.
- **Bake stretched parts, not whole files.** A part is under 0.2 s of
  work. The whole recording is a few seconds. Both are short. A part per
  warp section keeps the rough preview short and a moved marker cheap.
- **Check the index with `stat` at open**, not with a hash.
- **Add the AAC decoder** when an import of AAC and MP4 audio is wanted.
  It costs no speed that matters.
