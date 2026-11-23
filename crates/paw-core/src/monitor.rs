//! What the instance plays, sent to the connections that listen
//! (`monitor.listen`, `monitor.unlisten`): see `paw_proto::monitor` for the
//! frames. A thread of its own reads the engine's copy of its output and
//! sends it on, so that the kernel's turns do not hold it up; the engine
//! only copies while someone listens.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{Receiver, RecvTimeoutError, Sender, channel};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use anyhow::{Result, bail};
use paw_proto::monitor::Encoder;
use rtrb::Consumer;
use serde_json::{Value, json};

use crate::rpc::{ClientId, Clients};
use crate::session::Session;

/// How much the engine's copy holds before what does not fit is dropped.
const QUEUE_SECONDS: f64 = 1.0;

pub struct Monitor {
    clients: Clients,
    listeners: Arc<Mutex<Vec<ClientId>>>,
    /// A new copy of the output for the thread, with the engine's rate.
    feed: Option<Sender<(Consumer<f32>, f64)>>,
    /// The engine the thread reads from has gone (it was restarted).
    starved: Arc<AtomicBool>,
}

impl Monitor {
    pub fn new(clients: Clients) -> Self {
        Self {
            clients,
            listeners: Arc::default(),
            feed: None,
            starved: Arc::default(),
        }
    }

    /// Answer `monitor.listen` and `monitor.unlisten`.
    pub fn call(&mut self, client: ClientId, method: &str, session: &mut Session) -> Result<Value> {
        match method {
            "monitor.listen" => {
                {
                    let mut listeners = self.listeners.lock().unwrap();
                    if !listeners.contains(&client) {
                        listeners.push(client);
                    }
                }
                let rate = self.start(session);
                Ok(json!({
                    "rate": Encoder::new(rate).rate,
                    "channels": 2,
                    "format": "s16le",
                    "frame_ms": paw_proto::monitor::FRAME_MS,
                }))
            }
            "monitor.unlisten" => {
                self.closed(client, session);
                Ok(Value::Bool(true))
            }
            _ => bail!("no method `{method}`"),
        }
    }

    /// A connection stopped listening, or closed.
    pub fn closed(&mut self, client: ClientId, session: &mut Session) {
        let mut listeners = self.listeners.lock().unwrap();
        let before = listeners.len();
        listeners.retain(|id| *id != client);
        if before > 0 && listeners.is_empty() {
            session.stop_monitor();
        }
    }

    /// Whether anyone listens.
    pub fn listening(&self) -> bool {
        !self.listeners.lock().unwrap().is_empty()
    }

    /// After a turn: a restarted engine is asked for a copy again.
    pub fn keep_fed(&mut self, session: &mut Session) {
        if self.listening() && self.starved.swap(false, Ordering::Relaxed) {
            self.start(session);
        }
    }

    /// Give the thread (started the first time) a fresh copy of the output.
    fn start(&mut self, session: &mut Session) -> f64 {
        let (queue, rate) = session.monitor_output(QUEUE_SECONDS);
        let feed = self.feed.get_or_insert_with(|| {
            let (tx, rx) = channel();
            let (clients, listeners, starved) =
                (self.clients.clone(), self.listeners.clone(), self.starved.clone());
            std::thread::Builder::new()
                .name("monitor".into())
                .spawn(move || send_on(rx, clients, listeners, starved))
                .expect("starting the monitor thread");
            tx
        });
        let _ = feed.send((queue, rate));
        rate
    }
}

/// The thread: read the engine's copy, make frames, push them to whoever
/// listens.
fn send_on(
    feed: Receiver<(Consumer<f32>, f64)>,
    clients: Clients,
    listeners: Arc<Mutex<Vec<ClientId>>>,
    starved: Arc<AtomicBool>,
) {
    let mut source: Option<(Consumer<f32>, Encoder)> = None;
    let mut buf = Vec::new();
    loop {
        // A newer copy replaces the one being read.
        let wait = if source.is_some() { Duration::from_millis(5) } else { Duration::from_secs(3600) };
        match feed.recv_timeout(wait) {
            Ok((queue, rate)) => source = Some((queue, Encoder::new(rate))),
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => return,
        }
        let Some((queue, encoder)) = source.as_mut() else { continue };
        let ready = queue.slots();
        if ready == 0 {
            if queue.is_abandoned() {
                source = None;
                starved.store(true, Ordering::Relaxed);
            }
            continue;
        }
        let Ok(chunk) = queue.read_chunk(ready - ready % 2) else { continue };
        buf.clear();
        buf.extend(chunk);
        let frames = encoder.push(&buf);
        // The lock stays held while the frames are queued: so a connection
        // that `monitor.unlisten` removed gets no frame after its reply.
        let ids = listeners.lock().unwrap();
        for frame in &frames {
            for id in ids.iter() {
                clients.push(*id, "audio.frame", frame);
            }
        }
    }
}
