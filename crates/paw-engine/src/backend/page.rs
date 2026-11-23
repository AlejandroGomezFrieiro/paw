//! The sound device of a BrowserPod pod: the web page that runs the pod
//! (web/browserpod/README.md). It stands in for `cpal.rs` there, with the
//! same names.
//!
//! A pod has no sound device. Its network goes out through the page's own
//! `fetch`, so the page sees each HTTP request of the pod and answers it.
//! The page answers the host `audio.paw`:
//!
//! - `GET /open`: the sample rate that the page plays at, as text.
//! - `POST /pcm`: a body of stereo frames, interleaved little-endian `f32`,
//!   that the page puts into a ring that an AudioWorklet plays. The answer
//!   has no body.
//!
//! The engine renders on a clock thread, as the null backend does, and
//! hands each block to an rtrb ring. A second thread takes the frames from
//! the ring and posts them, on one connection that stays open. The audio
//! thread never waits on the network: when the ring is full, the block is
//! dropped and counted.
//!
//! The client is a few lines of HTTP/1.1 over a `TcpStream`: one host that
//! the page answers, no TLS, no redirect. An HTTP crate would add TLS and a
//! resolver that the pod's network does not need.

use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpStream;
use std::sync::atomic::{AtomicBool, Ordering::Relaxed};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::Duration;

use anyhow::{Context, Result, bail};

#[cfg(target_vendor = "browserpod")]
use super::Opened;
use super::{AudioDevice, BackendChoice, BackendOptions, DeviceList, Lost, StreamInfo};
use crate::engine::Engine;

/// The host and port that the page answers.
pub(super) const PAGE: (&str, u16) = ("audio.paw", 80);

/// The backend's name: `--audio page`.
pub(super) const NAME: &str = "page";

/// Frames that one request carries at most.
const FRAMES_PER_POST: usize = 2048;

/// The page to send to, and the block size, once it answered.
pub(super) struct Devices {
    addr: (String, u16),
    block: usize,
    rate: u32,
}

/// The two threads: the clock that renders, and the sender.
pub(super) struct Running {
    stop: Arc<AtomicBool>,
    render: Option<JoinHandle<Engine>>,
    send: Option<JoinHandle<()>>,
    parked: Arc<Mutex<Option<Engine>>>,
}

impl Drop for Running {
    fn drop(&mut self) {
        self.stop.store(true, Relaxed);
        if let Some(render) = self.render.take()
            && let Ok(engine) = render.join()
            && let Ok(mut parked) = self.parked.lock()
        {
            // The stream frees the engine on its own thread.
            *parked = Some(engine);
        }
        if let Some(send) = self.send.take() {
            drop(send.join());
        }
    }
}

/// The text of the warning when `auto` falls back to the null backend.
pub(super) fn fallback_warning(err: &anyhow::Error) -> String {
    format!("no sound from the page ({err:#}): playing silently")
}

pub(super) fn backends() -> Vec<String> {
    vec![NAME.to_string()]
}

pub(super) fn list_devices(opts: &BackendOptions) -> Result<DeviceList> {
    let mut list = super::null_devices(opts);
    list.backend = BackendChoice::Host(NAME.into());
    list.outputs.push(AudioDevice {
        name: "the page".into(),
        id: NAME.into(),
        channels: 2,
        sample_rate: opts.sample_rate.unwrap_or(48000),
        min_block: 0,
        max_block: 0,
    });
    Ok(list)
}

#[cfg(target_vendor = "browserpod")]
pub fn open(opts: &BackendOptions) -> Result<Opened> {
    let (info, devices) = open_at(opts, (PAGE.0.to_string(), PAGE.1))?;
    Ok(Opened {
        info,
        test_input: None,
        cpal: Some(devices),
    })
}

/// Ask the page at `addr` whether it plays sound, and at what rate.
fn open_at(opts: &BackendOptions, addr: (String, u16)) -> Result<(StreamInfo, Devices)> {
    match &opts.backend {
        BackendChoice::Auto => {}
        BackendChoice::Host(name) if name == NAME => {}
        other => bail!("unknown audio backend `{other}`: this build has only `{NAME}`"),
    }
    let mut page = Page::connect(&addr)?;
    let answer = page
        .request("GET", "/open", &[])
        .context("the page does not play sound")?;
    let rate: u32 = String::from_utf8_lossy(&answer)
        .trim()
        .parse()
        .context("the page gave no sample rate")?;
    let block = opts.buffer_size.unwrap_or(512).max(64) as usize;
    let info = StreamInfo {
        backend: BackendChoice::Host(NAME.into()),
        device: "the page".into(),
        device_id: NAME.into(),
        sample_rate: rate,
        buffer_size: block as u32,
        input_device: "none".into(),
        input_device_id: String::new(),
        input_channels: 0,
        warning: None,
    };
    Ok((info, Devices { addr, block, rate }))
}

/// Start the clock thread on the engine in `parked`, and the sender.
pub(super) fn start(
    devices: Devices,
    parked: Arc<Mutex<Option<Engine>>>,
    lost: Arc<Lost>,
) -> Result<Running> {
    let engine = parked
        .lock()
        .ok()
        .and_then(|mut parked| parked.take())
        .context("no engine to start")?;
    // Half a second of stereo frames between the two threads.
    let (mut producer, consumer) = rtrb::RingBuffer::<f32>::new(devices.rate as usize);
    let stop = Arc::new(AtomicBool::new(false));
    let page = Page::connect(&devices.addr)?;
    let send = {
        let stop = stop.clone();
        std::thread::Builder::new()
            .name("paw page audio".into())
            .spawn(move || send(page, consumer, &stop, &lost))?
    };
    let render = super::spawn_clock(
        engine,
        devices.block,
        stop.clone(),
        None,
        None,
        move |left: &[f32], right: &[f32]| {
            // A full ring: the page is behind, and the block is lost.
            let Ok(mut chunk) = producer.write_chunk_uninit(left.len() * 2) else {
                return;
            };
            let (a, b) = chunk.as_mut_slices();
            let frames = left.iter().zip(right).flat_map(|(l, r)| [*l, *r]);
            for (slot, sample) in a.iter_mut().chain(b.iter_mut()).zip(frames) {
                slot.write(sample);
            }
            // SAFETY: The loop wrote every slot of the chunk: it has
            // `left.len() * 2` slots and the iterator as many samples.
            unsafe { chunk.commit_all() };
        },
    );
    Ok(Running {
        stop,
        render: Some(render),
        send: Some(send),
        parked,
    })
}

/// The sender thread: post what the ring holds until told to stop. A page
/// that stops answering is a device that is gone.
fn send(mut page: Page, mut ring: rtrb::Consumer<f32>, stop: &AtomicBool, lost: &Lost) {
    let mut body = Vec::with_capacity(FRAMES_PER_POST * 8);
    while !stop.load(Relaxed) {
        let samples = ring.slots().min(FRAMES_PER_POST * 2) & !1;
        if samples == 0 {
            std::thread::sleep(Duration::from_millis(2));
            continue;
        }
        body.clear();
        if let Ok(chunk) = ring.read_chunk(samples) {
            body.extend(chunk.into_iter().flat_map(f32::to_le_bytes));
        }
        if let Err(err) = page.request("POST", "/pcm", &body) {
            lost.report(format!("the page stopped playing sound: {err}"));
            break;
        }
    }
}

/// One connection to the page, kept open between requests.
struct Page {
    host: String,
    writer: TcpStream,
    reader: BufReader<TcpStream>,
}

impl Page {
    fn connect((host, port): &(String, u16)) -> Result<Self> {
        let writer = TcpStream::connect((host.as_str(), *port))
            .with_context(|| format!("no page at {host}"))?;
        let reader = BufReader::new(writer.try_clone()?);
        Ok(Self {
            host: host.clone(),
            writer,
            reader,
        })
    }

    /// Send one request and read the answer's body.
    fn request(&mut self, method: &str, path: &str, body: &[u8]) -> std::io::Result<Vec<u8>> {
        let head = format!(
            "{method} {path} HTTP/1.1\r\nHost: {}\r\nContent-Type: application/octet-stream\r\nContent-Length: {}\r\n\r\n",
            self.host,
            body.len()
        );
        self.writer.write_all(head.as_bytes())?;
        self.writer.write_all(body)?;
        self.read_answer()
    }

    fn read_answer(&mut self) -> std::io::Result<Vec<u8>> {
        let bad =
            |what: &str| std::io::Error::new(std::io::ErrorKind::InvalidData, what.to_string());
        let mut line = String::new();
        self.reader.read_line(&mut line)?;
        let status = line
            .split_whitespace()
            .nth(1)
            .ok_or_else(|| bad("no answer"))?
            .to_string();
        let (mut length, mut chunked) = (None, false);
        loop {
            line.clear();
            if self.reader.read_line(&mut line)? == 0 {
                return Err(bad("the answer ended in its head"));
            }
            let header = line.trim_end();
            if header.is_empty() {
                break;
            }
            let (name, value) = header.split_once(':').unwrap_or((header, ""));
            if name.eq_ignore_ascii_case("content-length") {
                length = value.trim().parse::<usize>().ok();
            } else if name.eq_ignore_ascii_case("transfer-encoding") {
                chunked = value.to_ascii_lowercase().contains("chunked");
            }
        }
        let mut out = Vec::new();
        if chunked {
            loop {
                line.clear();
                self.reader.read_line(&mut line)?;
                let size =
                    usize::from_str_radix(line.trim(), 16).map_err(|_| bad("a bad chunk"))?;
                let start = out.len();
                out.resize(start + size + 2, 0);
                self.reader.read_exact(&mut out[start..])?;
                out.truncate(start + size);
                if size == 0 {
                    break;
                }
            }
        } else if let Some(length) = length {
            out.resize(length, 0);
            self.reader.read_exact(&mut out)?;
        }
        if !status.starts_with('2') {
            return Err(bad(&format!("the page answered {status}")));
        }
        Ok(out)
    }
}

#[cfg(test)]
mod tests {
    use std::net::TcpListener;
    use std::sync::atomic::AtomicU64;

    use super::*;

    /// A page that plays at 48 kHz and counts the bytes of sound it gets,
    /// answering the one way, then the other (chunked).
    fn fake_page() -> ((String, u16), Arc<AtomicU64>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let got = Arc::new(AtomicU64::new(0));
        let counted = got.clone();
        std::thread::spawn(move || {
            for stream in listener.incoming().flatten() {
                let counted = counted.clone();
                std::thread::spawn(move || {
                    let mut reader = BufReader::new(stream.try_clone().unwrap());
                    let mut writer = stream;
                    let mut n = 0;
                    loop {
                        let mut line = String::new();
                        if reader.read_line(&mut line).unwrap_or(0) == 0 {
                            return;
                        }
                        let mut length = 0;
                        loop {
                            let mut header = String::new();
                            reader.read_line(&mut header).unwrap();
                            if header == "\r\n" {
                                break;
                            }
                            if let Some(v) =
                                header.to_ascii_lowercase().strip_prefix("content-length:")
                            {
                                length = v.trim().parse().unwrap();
                            }
                        }
                        let mut body = vec![0; length];
                        reader.read_exact(&mut body).unwrap();
                        let answer = if line.starts_with("GET /open") {
                            "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\n48000".to_string()
                        } else {
                            counted.fetch_add(length as u64, Relaxed);
                            n += 1;
                            if n % 2 == 0 {
                                "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nok\r\n0\r\n\r\n".to_string()
                            } else {
                                "HTTP/1.1 204 No Content\r\n\r\n".to_string()
                            }
                        };
                        writer.write_all(answer.as_bytes()).unwrap();
                    }
                });
            }
        });
        (("127.0.0.1".to_string(), port), got)
    }

    #[test]
    fn the_engine_plays_through_the_page() {
        let (addr, got) = fake_page();
        let opts = BackendOptions {
            backend: NAME.into(),
            ..Default::default()
        };
        let (info, devices) = open_at(&opts, addr).unwrap();
        assert_eq!(info.sample_rate, 48000);
        let (engine, _handle) = Engine::new(48000.0);
        let parked = Arc::new(Mutex::new(Some(engine)));
        let running = start(devices, parked.clone(), Arc::new(Lost::default())).unwrap();
        std::thread::sleep(Duration::from_millis(300));
        let sent = got.load(Relaxed);
        drop(running);
        assert!(
            parked.lock().unwrap().is_some(),
            "the engine comes back to free"
        );
        // About 0.3 s of stereo f32 frames: 8 bytes each.
        assert!(sent >= 48000 / 10 * 8, "only {sent} bytes reached the page");
        assert_eq!(sent % 8, 0);
    }

    #[test]
    fn no_page_is_an_error() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        drop(listener);
        let opts = BackendOptions {
            backend: NAME.into(),
            ..Default::default()
        };
        assert!(open_at(&opts, ("127.0.0.1".into(), port)).is_err());
    }
}
