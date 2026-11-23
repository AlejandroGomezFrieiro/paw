//! The control socket from outside: calls, pushed events, TLS and the token
//! over TCP, the frontend's state pushed in parts, and a terminal attached
//! to a kernel that runs without one.

mod sealed;

use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

use paw_core::grid::Grid;
use paw_core::rpc::{Connection, Wire};
use serde_json::{Value, json};

/// A kernel without a UI, listening on a socket and on a TCP port of its
/// own, ended when the test is.
struct Instance {
    child: Child,
    socket: PathBuf,
    address: String,
    token: String,
    dir: PathBuf,
}

impl Drop for Instance {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

/// A scratch directory of the test's own, empty.
fn scratch(name: &str) -> PathBuf {
    // A short path: a Unix socket's must fit in 108 bytes.
    let dir = std::env::temp_dir().join(format!("paw-rt-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn start(name: &str) -> Instance {
    start_with(name, None, &[])
}

/// An instance with more options, and with its state (its token and
/// certificate) kept in `state` rather than in its own directory.
fn start_with(name: &str, state: Option<&std::path::Path>, more: &[&str]) -> Instance {
    let dir = scratch(name);
    let state = state.unwrap_or(&dir).to_path_buf();
    let socket = dir.join("paw.sock");
    let token_file = state.join("token");
    let mut child = sealed::seal(&mut Command::new(env!("CARGO_BIN_EXE_paw")), &dir)
        .args(["--headless", "--clean", "--no-plugins", "--audio", "null"])
        .arg("--listen")
        .arg(&socket)
        .args(["--listen-tcp", "127.0.0.1:0", "--token-file"])
        .arg(&token_file)
        .args(more)
        .env("XDG_CACHE_HOME", &dir)
        .env("XDG_STATE_HOME", &state)
        .env("XDG_DATA_HOME", &dir)
        .stdin(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .expect("starting paw");
    // It says where it listens once it does.
    let mut address = String::new();
    let stderr = child.stderr.take().unwrap();
    for line in BufReader::new(stderr).lines().map_while(Result::ok) {
        assert!(!line.starts_with("paw: listening on /"), "{line}");
        if let Some(rest) = line.split("listening on ").nth(1) {
            address = rest.split_whitespace().next().unwrap().to_string();
            break;
        }
    }
    assert!(!address.is_empty(), "the kernel said where it listens");
    let token = std::fs::read_to_string(&token_file).unwrap().trim().to_string();
    Instance {
        child,
        socket,
        address,
        token,
        dir,
    }
}

impl Instance {
    /// What this test's client remembers of the certificates it has seen.
    fn known(&self) -> PathBuf {
        self.dir.join("known_instances")
    }

    /// A connection over the network, in TLS.
    fn tcp(&self) -> anyhow::Result<Connection> {
        let wire = Wire::Tls { known: self.known(), accept_new: false };
        Connection::tcp_with(&self.address, &self.token, &wire)
    }
}

/// The next event called `name`, within a generous while.
fn event(connection: &Connection, name: &str) -> Value {
    let until = Instant::now() + Duration::from_secs(20);
    while let Ok((got, payload)) = connection
        .events
        .recv_timeout(until.saturating_duration_since(Instant::now()))
    {
        if got == name {
            return payload;
        }
    }
    panic!("no `{name}` event arrived");
}

/// Whether anything at all is pushed within `wait`.
fn quiet(connection: &Connection, wait: Duration) -> bool {
    connection.events.recv_timeout(wait).is_err()
}

#[test]
fn calls_and_subscribed_events_over_the_socket() {
    let instance = start("events");
    let mut c = Connection::unix(&instance.socket).unwrap();
    assert!(c.client > 0, "hello gave the connection a number");
    assert_eq!(c.call("eval", json!(["return 1 + 1"])).unwrap(), json!(2));
    // Nothing is pushed that was not asked for.
    c.call("cmd", json!(["track.add"])).unwrap();
    assert!(quiet(&c, Duration::from_millis(300)));
    c.call("subscribe", json!(["transport.*", "track.added"])).unwrap();
    c.call("cmd", json!(["track.add"])).unwrap();
    assert!(event(&c, "track.added")["id"].is_number());
    c.call("cmd", json!(["transport.play"])).unwrap();
    assert!(event(&c, "transport.play")["position"].is_number());
    c.call("cmd", json!(["transport.stop"])).unwrap();
    event(&c, "transport.stop");
    // Another connection hears none of it, and an error is an error.
    let mut other = Connection::unix(&instance.socket).unwrap();
    other.call("cmd", json!(["track.add"])).unwrap();
    assert!(quiet(&other, Duration::from_millis(200)));
    let err = other.call("no_such_method", json!([])).unwrap_err();
    assert!(err.to_string().contains("no method"), "{err}");
    c.call("unsubscribe", json!([])).unwrap();
    // What was on its way before that still arrives.
    while !quiet(&c, Duration::from_millis(300)) {}
    c.call("cmd", json!(["track.add"])).unwrap();
    assert!(quiet(&c, Duration::from_millis(300)));
}

#[test]
fn the_network_wants_tls_and_the_token() {
    let instance = start("token");
    let mut good = instance.tcp().unwrap();
    assert_eq!(good.call("eval", json!(["return 6 * 7"])).unwrap(), json!(42));
    let wire = Wire::Tls { known: instance.known(), accept_new: false };
    let refused = Connection::tcp_with(&instance.address, &"0".repeat(32), &wire);
    assert!(refused.is_err(), "a wrong token is refused");
    // Much both ways, in TLS.
    let big = good.call("eval", json!(["return string.rep('x', 3 * 2 ^ 20)"])).unwrap();
    assert_eq!(big.as_str().unwrap().len(), 3 << 20);
    let echoed = good.call("eval", json!(["return #(...)", "y".repeat(5 << 20)])).unwrap();
    assert_eq!(echoed, json!(5 << 20));
    // A client that speaks in the clear is told the port wants TLS.
    use std::io::Write;
    let mut raw = std::net::TcpStream::connect(&instance.address).unwrap();
    let mut lines = BufReader::new(raw.try_clone().unwrap()).lines();
    let hello: Value = serde_json::from_str(&lines.next().unwrap().unwrap()).unwrap();
    assert!(hello["payload"]["error"].as_str().unwrap().contains("TLS"), "{hello}");
    assert!(hello["payload"].get("nonce").is_none(), "nothing to prove the token with");
    writeln!(raw, "{}", json!({ "id": 1, "method": "eval", "params": ["return 1"] })).unwrap();
    let answer: Value = serde_json::from_str(&lines.next().unwrap().unwrap()).unwrap();
    assert!(answer["error"].as_str().unwrap().contains("--no-tls"), "{answer}");
    assert!(lines.next().is_none(), "and the connection is closed");
    // So is this program's own client, asked to connect in the clear.
    let plain = Connection::tcp_with(&instance.address, &instance.token, &Wire::Plain);
    let err = plain.err().expect("refused in the clear").to_string();
    assert!(err.contains("TLS only"), "{err}");
    // The first connection is none the worse.
    assert_eq!(good.call("eval", json!(["return 'still here'"])).unwrap(), json!("still here"));
}

#[test]
fn in_the_clear_only_when_asked_and_still_with_the_token() {
    let instance = start_with("plain", None, &["--no-tls"]);
    // A TLS client is told the instance speaks in the clear.
    let err = instance.tcp().err().expect("no TLS there").to_string();
    assert!(err.contains("without encryption") && err.contains("--no-tls"), "{err}");
    let mut good = Connection::tcp_with(&instance.address, &instance.token, &Wire::Plain).unwrap();
    assert_eq!(good.call("eval", json!(["return 6 * 7"])).unwrap(), json!(42));
    let wrong = Connection::tcp_with(&instance.address, &"0".repeat(32), &Wire::Plain);
    assert!(wrong.is_err(), "a wrong token is refused");
    // Without hello, nothing is answered but the refusal.
    use std::io::Write;
    let mut raw = std::net::TcpStream::connect(&instance.address).unwrap();
    let mut lines = BufReader::new(raw.try_clone().unwrap()).lines();
    let hello: Value = serde_json::from_str(&lines.next().unwrap().unwrap()).unwrap();
    assert_eq!(hello["event"], "hello");
    assert!(hello["payload"]["nonce"].as_str().unwrap().len() >= 16);
    writeln!(raw, "{}", json!({ "id": 1, "method": "eval", "params": ["return 1"] })).unwrap();
    let answer: Value = serde_json::from_str(&lines.next().unwrap().unwrap()).unwrap();
    assert!(answer["error"].as_str().unwrap().contains("hello"), "{answer}");
    assert!(lines.next().is_none(), "and the connection is closed");
    assert_eq!(good.call("eval", json!(["return 'still here'"])).unwrap(), json!("still here"));
}

#[test]
fn the_certificate_is_trusted_the_first_time_and_held_to_after() {
    let state = scratch("pin-state");
    let first = start_with("pin1", Some(&state), &[]);
    let known = first.known();
    let c = first.tcp().unwrap();
    let print = c.trusted_now.clone().expect("remembered the first time");
    assert_eq!(print.len(), 64 + 15, "{print}");
    let kept = std::fs::read_to_string(&known).unwrap();
    assert_eq!(kept.trim(), format!("{} {print}", first.address));
    assert!(first.tcp().unwrap().trusted_now.is_none(), "nothing new the second time");
    drop((c, first));
    // The same instance started again (on another port: what it is
    // remembered by is copied over) shows the same certificate.
    let again = start_with("pin2", Some(&state), &[]);
    let line = |address: &str, print: &str| format!("{address} {print}\n");
    std::fs::write(again.known(), line(&again.address, &print)).unwrap();
    let mut c = again.tcp().unwrap();
    assert!(c.trusted_now.is_none(), "the certificate was kept");
    assert_eq!(c.call("eval", json!(["return 1"])).unwrap(), json!(1));
    drop((c, again));
    // One that made a new certificate is refused, naming both.
    std::fs::remove_dir_all(state.join("paw/tls")).unwrap();
    let other = start_with("pin3", Some(&state), &[]);
    std::fs::write(other.known(), line(&other.address, &print)).unwrap();
    let err = format!("{:#}", other.tcp().err().expect("refused"));
    assert!(err.contains(&print) && err.contains("--accept-certificate"), "{err}");
    let shown = err.lines().find_map(|l| l.split("shown now:").nth(1)).unwrap().trim().to_string();
    assert_ne!(shown, print);
    // Unless the new one is accepted, which is remembered in its place.
    let wire = Wire::Tls { known: other.known(), accept_new: true };
    let mut c = Connection::tcp_with(&other.address, &other.token, &wire).unwrap();
    assert_eq!(c.trusted_now.as_deref(), Some(shown.as_str()));
    assert_eq!(c.call("eval", json!(["return 2"])).unwrap(), json!(2));
    assert_eq!(std::fs::read_to_string(other.known()).unwrap(), line(&other.address, &shown));
    assert!(other.tcp().is_ok());
    drop(other);
    let _ = std::fs::remove_dir_all(&state);
}

#[test]
fn a_watching_frontend_is_sent_what_changed_and_nothing_when_nothing_did() {
    let instance = start("watch");
    let mut c = Connection::unix(&instance.socket).unwrap();
    c.call("eval", json!(["paw.add_track({ name = 'one' })"])).unwrap();
    c.call("frontend.watch", json!([])).unwrap();
    let first = event(&c, "frontend.state");
    let sections = first["sections"].as_object().expect("the whole state at first");
    for name in ["project", "lines", "tracks", "clips", "devices", "view", "kinds"] {
        assert!(sections.contains_key(name), "the first state has `{name}`");
    }
    assert_eq!(sections["tracks"][0]["name"], "one");
    assert!(first["modal"].is_object() && first["levels"].is_array());
    assert!(quiet(&c, Duration::from_millis(400)), "an idle kernel sends nothing");
    // A change sends the parts it touched, and not the bar lines again.
    c.call("eval", json!(["paw.add_track({ name = 'two' })"])).unwrap();
    // A state with only the levels can come first: the engine wakes up
    // from its rest when the track is added.
    let next = loop {
        let state = event(&c, "frontend.state");
        if state["sections"].is_object() {
            break state;
        }
    };
    let changed = next["sections"].as_object().expect("something changed");
    assert_eq!(changed["tracks"][1]["name"], "two");
    assert!(!changed.contains_key("lines"), "the lines did not change: {:?}", changed.keys());
    assert!(!changed.contains_key("kinds"));
    // While playing, the position comes without being asked for.
    c.call("eval", json!(["paw.tracks()[1]:add_clip({ start = 0, length = 64 })"])).unwrap();
    c.call("cmd", json!(["transport.play"])).unwrap();
    let mut moved = false;
    for _ in 0..40 {
        let state = event(&c, "frontend.state");
        if state["playing"] == true && state["position"].as_f64().unwrap_or(0.0) > 0.0 {
            moved = true;
            break;
        }
    }
    assert!(moved, "the playhead's position is pushed while playing");
    c.call("cmd", json!(["transport.stop"])).unwrap();
    c.call("frontend.unwatch", json!([])).unwrap();
    while !quiet(&c, Duration::from_millis(300)) {}
    c.call("eval", json!(["paw.add_track({ name = 'three' })"])).unwrap();
    assert!(quiet(&c, Duration::from_millis(300)), "no longer watching");
}

#[test]
fn a_window_is_sent_what_moves_at_its_own_pace_and_an_edit_at_once() {
    let instance = start("pace");
    let mut c = Connection::unix(&instance.socket).unwrap();
    c.call("eval", json!(["paw.add_track({ name = 'one' }):add_clip({ start = 0, length = 64 })"])).unwrap();
    c.call("frontend.watch", json!([])).unwrap();
    c.call("scene.watch", json!([{ "cell": { "w": 8, "h": 16 }, "live": true }])).unwrap();
    // A window that draws ten frames a second while the song plays.
    c.notify("frontend.pace", json!([100])).unwrap();
    while !quiet(&c, Duration::from_millis(300)) {}
    c.call("cmd", json!(["transport.play"])).unwrap();
    event(&c, "scene.live");
    let (mut states, mut lives) = (0, 0);
    let until = Instant::now() + Duration::from_secs(2);
    while let Ok((name, _)) = c.events.recv_timeout(until.saturating_duration_since(Instant::now())) {
        match name.as_str() {
            "frontend.state" => states += 1,
            "scene.live" => lives += 1,
            _ => {}
        }
    }
    assert!((12..=26).contains(&states), "about ten states a second: {states} in 2 s");
    assert!((12..=26).contains(&lives), "and as many live values: {lives} in 2 s");
    // Stopped, a moment after the meters fell, the kernel sends nothing.
    c.call("cmd", json!(["transport.stop"])).unwrap();
    let until = Instant::now() + Duration::from_secs(10);
    while !quiet(&c, Duration::from_millis(1500)) {
        assert!(Instant::now() < until, "quiet once the song stopped");
    }
    // An edit is sent after its turn, without waiting for the next tick.
    let asked = Instant::now();
    c.call("eval", json!(["paw.add_track({ name = 'two' })"])).unwrap();
    loop {
        let state = event(&c, "frontend.state");
        if state["sections"]["tracks"][1]["name"] == "two" {
            break;
        }
    }
    assert!(asked.elapsed() < Duration::from_millis(500), "at once: {:?}", asked.elapsed());
}

/// A window's scene as a frontend keeps it, its patches applied, and what
/// it shows in cells as lines of text.
fn scene_lines(scene: &paw_scene::Scene) -> Vec<String> {
    let cells = scene.to_cells();
    cells.cells.chunks(cells.width.max(1) as usize).map(|row| row.iter().map(|c| c.ch).collect::<String>().trim_end().to_string()).collect()
}

/// The next patch of a scene, decoded.
fn patch(c: &Connection) -> paw_scene::Patch {
    serde_json::from_value(event(c, "scene.patch")).expect("a patch")
}

#[test]
fn a_frontend_is_pushed_each_windows_scene_and_then_only_what_changed() {
    let instance = start("scenes");
    let mut c = Connection::unix(&instance.socket).unwrap();
    // A view of the test's own, in a window of its own: it says a count,
    // and where the pointer went down in it.
    c.call(
        "eval",
        json!(["_G.count = 0
               paw.ui.view('probe', {
                 render = function(_, buf)
                   buf:text(0, 0, 'count ' .. _G.count, 'Normal')
                   buf:text(0, 1, 'second row', 'Comment')
                 end,
                 on_mouse = function(_, e) if e.kind == 'down' then _G.down = e.x .. ',' .. e.y end end,
               })
               paw.canvas.open_view('probe')"]),
    )
    .unwrap();
    c.call("scene.watch", json!([{ "cell": { "w": 8, "h": 16 } }])).unwrap();
    assert!(quiet(&c, Duration::from_millis(300)), "nothing is sent of a window whose size is not said");
    c.call("scene.area", json!(["view:probe", 20, 3])).unwrap();
    let first = patch(&c);
    assert_eq!((first.win.as_str(), first.full), ("view:probe", true), "the whole scene at first");
    let mut scene = paw_scene::Scene::default();
    scene.apply(&first);
    assert_eq!(scene.size, [20.0, 3.0]);
    assert_eq!(&scene_lines(&scene)[..2], ["count 0", "second row"]);
    assert!(quiet(&c, Duration::from_millis(400)), "an idle kernel sends nothing");
    // A change sends what it changed, and nothing else.
    c.call("eval", json!(["_G.count = 1 paw.api.ui_redraw()"])).unwrap();
    let next = patch(&c);
    assert!(!next.full);
    let keys: Vec<&str> = next.set.iter().map(|n| n.key.as_str()).collect();
    assert_eq!(keys, ["t0,0"], "only the count");
    scene.apply(&next);
    assert_eq!(scene_lines(&scene)[0], "count 1");
    // The pointer comes back in the same units, as the view takes it.
    c.call("scene.input", json!(["view:probe", { "kind": "down", "x": 3.5, "y": 1.2, "button": "left" }])).unwrap();
    let down = c.call("eval", json!(["return _G.down"])).unwrap();
    assert_eq!(down, json!("3,1"));
    // A window the frontend no longer shows is forgotten; shown again, it
    // is sent whole.
    c.call("scene.area", json!(["view:probe", 0, 0])).unwrap();
    while !quiet(&c, Duration::from_millis(300)) {}
    c.call("eval", json!(["_G.count = 2 paw.api.ui_redraw()"])).unwrap();
    assert!(quiet(&c, Duration::from_millis(300)), "nothing for a window not shown");
    c.call("scene.area", json!(["view:probe", 20, 3])).unwrap();
    let again = patch(&c);
    assert!(again.full);
    let mut scene = paw_scene::Scene::default();
    scene.apply(&again);
    assert_eq!(scene_lines(&scene)[0], "count 2");
}

#[test]
fn a_big_drawing_is_fetched_once_by_its_key_and_live_values_are_pushed() {
    let instance = start("blobs");
    let mut c = Connection::unix(&instance.socket).unwrap();
    // A view that paints thousands of rectangles, in a window of its own.
    c.call(
        "eval",
        json!(["paw.ui.view('many', { paint = function(_, g, ctx)
                 for i = 0, 2999 do g:rect(i % 100, math.floor(i / 100), 1, 1, { fill = '#ffffff' }) end
               end })
               paw.canvas.open('many', { window = true })
               local t = paw.add_track({ name = 'Lead' })
               t:add_clip({ start = 0, length = 64 })"]),
    )
    .unwrap();
    c.call("scene.watch", json!([{ "cell": { "w": 8, "h": 16 }, "live": true }])).unwrap();
    c.call("scene.area", json!(["view:many", 30, 10])).unwrap();
    let first = patch(&c);
    let paw_scene::Kind::Picture(picture) = &first.set[0].kind else { panic!("a picture: {:?}", first.set[0]) };
    assert_eq!(picture.px, [240.0, 160.0], "painted at the window's size in pixels");
    let key = picture.blob.clone().expect("too big to send each time: sent by its key");
    let ops = c.call("scene.blob", json!([key])).unwrap();
    assert_eq!(ops.as_array().map(Vec::len), Some(3000));
    // The playhead and the meters come as live values, not as scenes.
    c.call("cmd", json!(["transport.play"])).unwrap();
    let mut moved = false;
    for _ in 0..40 {
        let live = event(&c, "scene.live");
        if live["playing"] == true && live["position"].as_f64().unwrap_or(0.0) > 0.0 {
            assert!(live["meters"].as_object().is_some_and(|m| !m.is_empty()), "a meter for the track: {live}");
            moved = true;
            break;
        }
    }
    assert!(moved, "the position is pushed while playing");
    c.call("cmd", json!(["transport.stop"])).unwrap();
    c.call("scene.unwatch", json!([])).unwrap();
    while !quiet(&c, Duration::from_millis(300)) {}
    c.call("eval", json!(["paw.api.ui_redraw()"])).unwrap();
    assert!(quiet(&c, Duration::from_millis(300)), "no longer watching");
}

/// The screen a terminal attached over `c` shows, as lines of text, once
/// `ready` says it holds what is waited for.
fn screen(c: &Connection, grid: &mut Grid, ready: impl Fn(&str) -> bool) -> String {
    let until = Instant::now() + Duration::from_secs(20);
    loop {
        let text: String = grid
            .cells
            .chunks(grid.width.max(1) as usize)
            .map(|row| row.iter().filter(|c| c.ch != '\0').map(|c| c.ch).collect::<String>() + "\n")
            .collect();
        if ready(&text) {
            return text;
        }
        let wait = until.saturating_duration_since(Instant::now());
        match c.events.recv_timeout(wait) {
            Ok((name, payload)) if name == "ui.grid" => {
                paw_core::remote::apply(grid, &payload).unwrap();
            }
            Ok(_) => {}
            Err(_) => panic!("the screen never showed what was waited for:\n{text}"),
        }
    }
}

#[test]
fn a_terminal_attaches_to_a_kernel_without_one_types_and_leaves() {
    let instance = start("attach");
    let mut c = instance.tcp().unwrap();
    c.call("eval", json!(["paw.add_track({ name = 'Remote bass' })"])).unwrap();
    assert!(c.call("ui.input", json!([{ "key": "j" }])).is_err(), "not before attaching");
    c.call("ui.attach", json!([100, 30])).unwrap();
    let mut grid = Grid::new(1, 1);
    let text = screen(&c, &mut grid, |t| t.contains("Remote bass") && t.contains("NORMAL"));
    assert_eq!((grid.width, grid.height), (100, 30));
    assert_eq!(text.lines().count(), 30);
    // Typing goes to the kernel's keys: a command line, and what it does.
    for key in [":", "t", "r", "a", "c", "k", ".", "a", "d", "d", "<CR>"] {
        c.notify("ui.input", json!([{ "key": key }])).unwrap();
    }
    screen(&c, &mut grid, |t| t.contains("Track 2"));
    assert_eq!(c.call("eval", json!(["return #paw.tracks()"])).unwrap(), json!(2));
    // A smaller terminal: the screen is sent whole again at the new size.
    c.notify("ui.input", json!([{ "resize": [60, 20] }])).unwrap();
    screen(&c, &mut grid, |t| t.lines().count() == 20 && t.contains("Track 2"));
    // `:detach` lets this terminal go; the kernel runs on.
    for key in [":", "d", "e", "t", "a", "c", "h", "<CR>"] {
        c.notify("ui.input", json!([{ "key": key }])).unwrap();
    }
    event(&c, "ui.detached");
    assert_eq!(c.call("eval", json!(["return paw.api.ui_attached()"])).unwrap(), json!(false));
    assert_eq!(c.call("eval", json!(["return #paw.tracks()"])).unwrap(), json!(2));
}

#[test]
fn connections_that_misbehave_are_closed_and_the_kernel_goes_on() {
    use std::io::{Read, Write};
    use std::net::TcpStream;
    use std::os::unix::net::UnixStream;
    // What is checked here happens before the token is shown, the same
    // with TLS or without; in the clear it can be done by hand.
    let instance = start_with("rude", None, &["--no-tls"]);
    let mut good = Connection::unix(&instance.socket).unwrap();
    let open = |good: &mut Connection| {
        good.call("eval", json!(["return #paw.api.rpc_clients()"])).unwrap().as_u64().unwrap()
    };
    assert_eq!(open(&mut good), 1);

    // One that says more than a greeting may hold before showing the token.
    let mut long = TcpStream::connect(&instance.address).unwrap();
    long.set_read_timeout(Some(Duration::from_secs(20))).unwrap();
    // (Just past the limit: all of it is taken in, so the answer is not
    // lost to a connection reset.)
    let _ = long.write_all(&vec![b'x'; 4097]);
    let mut said = String::new();
    let _ = long.read_to_string(&mut said);
    assert!(said.contains("too long"), "it is told why and closed: {said}");

    // One that connects and says nothing is not kept.
    let mut silent = TcpStream::connect(&instance.address).unwrap();
    silent.set_read_timeout(Some(Duration::from_secs(30))).unwrap();
    let mut said = String::new();
    // The end of the stream, not the read timeout: the instance closed it.
    let read = silent.read_to_string(&mut said);
    assert!(said.contains("nonce"), "it was greeted: {said}");
    assert!(read.is_ok(), "and then let go: {read:?}");

    // One that asks for a great deal and reads none of it.
    let mut deaf = UnixStream::connect(&instance.socket).unwrap();
    for _ in 0..80 {
        let request = json!({ "id": 1, "method": "eval", "params": ["return string.rep('x', 2 ^ 20)"] });
        if writeln!(deaf, "{request}").is_err() {
            break;
        }
    }
    let until = Instant::now() + Duration::from_secs(30);
    while open(&mut good) != 1 && Instant::now() < until {
        std::thread::sleep(Duration::from_millis(50));
    }
    assert_eq!(open(&mut good), 1, "only the well-behaved connection is left");
    assert_eq!(good.call("eval", json!(["return 2 + 2"])).unwrap(), json!(4));
}

#[test]
fn lua_that_runs_away_over_the_socket_is_stopped_and_errors_are_plain() {
    let instance = start("runaway");
    let mut c = Connection::unix(&instance.socket).unwrap();
    c.call("eval", json!(["paw.opt.lua_limit = 300"])).unwrap();
    c.call("eval", json!(["paw.command('zz_spin', function() while true do end end)"])).unwrap();
    c.call(
        "eval",
        json!(["paw.keymap.set('gZ', function() while true do end end, { view = 'arrange' })"]),
    )
    .unwrap();
    // Each way in: code, a command, keys. Each is stopped, and the instance
    // answers again afterwards.
    for (method, params) in [
        ("eval", json!(["while true do end"])),
        ("cmd", json!(["zz_spin"])),
        ("keys", json!(["gZ"])),
    ] {
        let outcome = c.call(method, params);
        if let Err(err) = outcome {
            assert!(err.to_string().contains("ran for more than"), "{method}: {err}");
        }
        assert_eq!(c.call("eval", json!(["return 2 + 2"])).unwrap(), json!(4), "after {method}");
    }
    // Errors are their message, as docs/reference/protocol.md shows them.
    let mut error = |method: &str, params: Value| c.call(method, params).unwrap_err().to_string();
    let told = [
        (error("no_such_method", json!([])), "no method `no_such_method`"),
        (error("eval", json!(["error('boom')"])), "boom"),
        (error("clip_notes", json!([999])), "no clip 999"),
        (error("eval", json!(["paw.tracks("])), "rpc:1: unexpected symbol near '<eof>'"),
        (error("eval", json!([7])), "`eval` takes the code to run, as a string"),
    ];
    for (got, want) in told {
        assert!(got.ends_with(want), "{got}");
        assert!(!got.contains("stack traceback") && !got.contains("runtime error"), "{got}");
    }
}

fn type_keys(c: &mut Connection, keys: &[&str]) {
    for key in keys {
        c.notify("ui.input", json!([{ "key": key }])).unwrap();
    }
}

#[test]
fn two_terminals_attached_have_a_seat_each_in_one_project() {
    let instance = start("seats");
    let mut a = instance.tcp().unwrap();
    let mut b = Connection::unix(&instance.socket).unwrap();
    a.call("eval", json!(["paw.add_track({ name = 'Drums' }); paw.add_track({ name = 'Bass' })"])).unwrap();
    a.call("ui.attach", json!([100, 30])).unwrap();
    b.call("ui.attach", json!([90, 24])).unwrap();
    let (mut ga, mut gb) = (Grid::new(1, 1), Grid::new(1, 1));
    screen(&a, &mut ga, |t| t.contains("Bass") && t.contains("NORMAL"));
    screen(&b, &mut gb, |t| t.contains("Bass") && t.contains("NORMAL"));
    assert_eq!((ga.width, gb.width), (100, 90), "each at its own size");
    // A selection opened in one terminal is that terminal's alone.
    type_keys(&mut a, &["j", "V"]);
    screen(&a, &mut ga, |t| t.contains("V-LINE"));
    let mode = |c: &mut Connection| c.call("eval", json!(["return paw.keymap.mode"])).unwrap();
    assert_eq!(mode(&mut a), json!("x"), "a call over a terminal's connection is in its seat");
    assert_eq!(mode(&mut b), json!("n"));
    let at = |c: &mut Connection| c.call("eval", json!(["return paw.cursor.track().name"])).unwrap();
    assert_eq!(at(&mut a), json!("Bass"));
    assert_eq!(at(&mut b), json!("Drums"), "the other cursor did not move");
    // What one adds, the other sees, and can take back: one history.
    type_keys(&mut a, &["<Esc>", ":", "t", "r", "a", "c", "k", ".", "a", "d", "d", "<CR>"]);
    screen(&b, &mut gb, |t| t.contains("Track 3"));
    type_keys(&mut b, &["u"]);
    screen(&a, &mut ga, |t| !t.contains("Track 3"));
    // The instance's own seat (as `paw ctl` sees it) is neither.
    let mut ctl = Connection::unix(&instance.socket).unwrap();
    assert_eq!(mode(&mut ctl), json!("n"));
    assert_eq!(at(&mut ctl), json!("Drums"));
    // A terminal that leaves takes its seat with it.
    let seats = |c: &mut Connection| c.call("eval", json!(["return #paw.seats.list()"])).unwrap();
    assert_eq!(seats(&mut ctl), json!(3));
    drop(a);
    let until = Instant::now() + Duration::from_secs(20);
    while seats(&mut ctl) != json!(2) && Instant::now() < until {
        std::thread::sleep(Duration::from_millis(50));
    }
    assert_eq!(seats(&mut ctl), json!(2));
}

#[test]
fn while_the_song_plays_terminals_are_sent_only_what_moves() {
    let instance = start("live");
    let mut a = instance.tcp().unwrap();
    let mut b = Connection::unix(&instance.socket).unwrap();
    a.call("eval", json!(["local t = paw.add_track({ name = 'Lead' }) t:add_clip({ start = 0, length = 64 })"])).unwrap();
    // Two terminals of two sizes: each keeps its own last frame.
    a.call("ui.attach", json!([100, 30])).unwrap();
    b.call("ui.attach", json!([90, 24])).unwrap();
    let (mut ga, mut gb) = (Grid::new(1, 1), Grid::new(1, 1));
    screen(&a, &mut ga, |t| t.contains("Lead") && t.contains("NORMAL"));
    screen(&b, &mut gb, |t| t.contains("Lead") && t.contains("NORMAL"));
    let frames = |c: &mut Connection| c.call("eval", json!(["return paw.api.ui_frames()"])).unwrap();
    let count = |v: &Value, k: &str| v[k].as_u64().unwrap();
    // The playhead and the position in the status line move on both.
    a.call("cmd", json!(["transport.play"])).unwrap();
    let before = frames(&mut a);
    screen(&a, &mut ga, |t| t.contains(" 1.3."));
    screen(&b, &mut gb, |t| t.contains(" 1.3."));
    screen(&a, &mut ga, |t| t.contains(" 2.1."));
    screen(&b, &mut gb, |t| t.contains(" 2.1."));
    let after = frames(&mut a);
    assert!(count(&after, "live") >= count(&before, "live") + 10, "frames of the live parts: {before} {after}");
    assert!(count(&after, "full") <= count(&before, "full") + 4, "few whole frames: {before} {after}");
    // A key still draws the whole screen at once.
    type_keys(&mut a, &[":", "t", "r", "a", "c", "k", ".", "a", "d", "d", "<CR>"]);
    screen(&a, &mut ga, |t| t.contains("Track 2"));
    screen(&b, &mut gb, |t| t.contains("Track 2"));
    a.call("cmd", json!(["transport.stop"])).unwrap();
}

/// A WAV file of `seconds` of a 440 Hz tone, 16-bit stereo at 48 kHz.
fn tone_file(path: &std::path::Path, seconds: f64) {
    let frames = (48000.0 * seconds) as u32;
    let mut data = Vec::new();
    data.extend_from_slice(b"RIFF");
    data.extend_from_slice(&(36 + frames * 4).to_le_bytes());
    data.extend_from_slice(b"WAVEfmt ");
    for word in [16u32, 1 | 2 << 16, 48000, 48000 * 4, 4 | 16 << 16] {
        data.extend_from_slice(&word.to_le_bytes());
    }
    data.extend_from_slice(b"data");
    data.extend_from_slice(&(frames * 4).to_le_bytes());
    for i in 0..frames {
        let v = ((i as f32 * 440.0 * std::f32::consts::TAU / 48000.0).sin() * 16000.0) as i16;
        data.extend_from_slice(&v.to_le_bytes());
        data.extend_from_slice(&v.to_le_bytes());
    }
    std::fs::write(path, data).unwrap();
}

#[test]
fn a_file_from_the_clients_disk_is_sent_and_imported() {
    let instance = start("upload");
    let mut c = instance.tcp().unwrap();
    let here = instance.dir.join("client take.wav");
    tone_file(&here, 3.0);
    let there = c.send_and_import(&here).unwrap();
    let media = c.call("eval", json!(["return paw.api.media_dir()"])).unwrap();
    assert!(there.starts_with(media.as_str().unwrap()), "{there} is in the project's media folder");
    assert_eq!(std::fs::read(&there).unwrap(), std::fs::read(&here).unwrap(), "every byte arrived");
    let clips = c.call("eval", json!(["local t = paw.tracks()[1]; return t and #t:clips()"])).unwrap();
    assert_eq!(clips, json!(1), "imported on a track of its own");
    // The same name again does not overwrite it.
    let again = c.send_file(&here).unwrap();
    assert_ne!(again, there);
    // A larger file goes in many pieces.
    let big = instance.dir.join("long.wav");
    tone_file(&big, 20.0);
    let there = c.send_file(&big).unwrap();
    assert_eq!(std::fs::metadata(&there).unwrap().len(), std::fs::metadata(&big).unwrap().len());
}

#[test]
fn the_instances_sound_is_heard_where_the_client_is() {
    let instance = start("listen");
    let mut c = instance.tcp().unwrap();
    // A long note on a synth, playing, on the null device.
    c.call(
        "eval",
        json!(["local t = paw.add_track({ name = 'Lead' }); t:add_device('synth', { attack = 0.001 })
               t:add_clip({ start = 0, length = 64, notes = { { pitch = 'A4', start = 0, length = 64 } } })
               paw.transport.play()"]),
    )
    .unwrap();
    let heard = instance.dir.join("heard.wav");
    let player = paw_listen::Player::file(&heard, 48000).unwrap();
    let answer = c.call("monitor.listen", json!([])).unwrap();
    assert_eq!(answer["format"], "s16le");
    assert_eq!(answer["rate"], json!(24000));
    let until = Instant::now() + Duration::from_secs(3);
    let mut frames = 0;
    let mut last = 0;
    while Instant::now() < until {
        if let Ok((name, payload)) = c.events.recv_timeout(Duration::from_millis(100))
            && name == "audio.frame"
        {
            let seq = payload["seq"].as_u64().unwrap();
            assert!(last == 0 || seq == last + 1, "frames in order: {last} then {seq}");
            last = seq;
            frames += 1;
            player.push(&payload).unwrap();
        }
    }
    assert!(frames >= 100, "about fifty frames a second: {frames} in three seconds");
    drop(player);
    let data = std::fs::read(&heard).unwrap();
    let samples: Vec<i16> = data[44..].chunks_exact(2).map(|b| i16::from_le_bytes([b[0], b[1]])).collect();
    let loud = samples.iter().filter(|s| s.abs() > 1000).count();
    assert!(loud > 48000 / 2, "the note was played here: {loud} loud samples");
    // Rising zero crossings of the left side over a stretch: A4 is 440 Hz.
    let left: Vec<i16> = samples.iter().step_by(2).copied().skip(48000).take(48000).collect();
    let rising = left.windows(2).filter(|w| w[0] < 0 && w[1] >= 0).count();
    assert!((400..=480).contains(&rising), "{rising} crossings in a second");
    // Stopping stops the frames.
    c.call("monitor.unlisten", json!([])).unwrap();
    while c.events.recv_timeout(Duration::from_millis(300)).is_ok() {}
    assert!(quiet(&c, Duration::from_millis(500)), "no more frames");
}

/// `paw ctl --json`: one line of JSON for an answer, and for an error, with
/// the exit status saying which.
#[test]
fn ctl_json_answers_in_one_line_of_json() {
    let instance = start("ctljson");
    let ctl = |args: &[&str]| {
        let out = sealed::seal(&mut Command::new(env!("CARGO_BIN_EXE_paw")), &instance.dir)
            .arg("ctl")
            .arg("--json")
            .arg("--socket")
            .arg(&instance.socket)
            .args(args)
            .output()
            .unwrap();
        let text = String::from_utf8(out.stdout).unwrap();
        assert_eq!(text.lines().count(), 1, "one line: {text}");
        (serde_json::from_str::<Value>(&text).unwrap(), out.status.success())
    };
    let (answer, ok) = ctl(&["eval", "return { tempo = paw.project.tempo, tracks = {} }"]);
    assert!(ok);
    assert_eq!(answer["ok"], true);
    assert_eq!(answer["result"]["tempo"], 120);
    let (answer, ok) = ctl(&["eval", "error('no good')"]);
    assert!(!ok);
    assert_eq!(answer["ok"], false);
    assert!(answer["error"].as_str().unwrap().contains("no good"), "{answer}");
    let (answer, ok) = ctl(&["no_such_method"]);
    assert!(!ok && answer["ok"] == false, "{answer}");
    // Without a kernel to talk to the error is JSON as well.
    let out = sealed::seal(&mut Command::new(env!("CARGO_BIN_EXE_paw")), &instance.dir)
        .args(["ctl", "--json", "--socket", "/nonexistent/paw.sock", "eval", "return 1"])
        .output()
        .unwrap();
    assert!(!out.status.success());
    let answer: Value = serde_json::from_slice(&out.stdout).unwrap();
    assert_eq!(answer["ok"], false);
}
