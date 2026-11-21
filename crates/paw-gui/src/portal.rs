//! The desktop's own file dialogs, asked for through the XDG desktop portal
//! (`org.freedesktop.portal.FileChooser`) over D-Bus. No toolkit is linked:
//! the desktop draws the dialog. Where there is no portal (no session bus,
//! a bare window manager) the answer is `Unavailable`, and the caller uses
//! the kernel's own list picker instead.

use std::future::Future;
use std::path::{Path, PathBuf};
use std::pin::pin;
use std::sync::Arc;
use std::task::{Context, Poll, Wake, Waker};
use std::thread::{self, Thread};

use ashpd::Error;
use ashpd::desktop::ResponseError;
use ashpd::desktop::file_chooser::{FileFilter, OpenFileRequest, SaveFileRequest};
use ashpd::url::Url;

/// What a dialog is for.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Kind {
    /// An existing file.
    Open,
    /// A file to be written, perhaps not there yet.
    Save,
}

/// A dialog to show: where it starts, what it offers to choose.
pub struct Ask {
    pub kind: Kind,
    pub title: String,
    /// Kinds of file offered, by the names `filters` knows.
    pub files: String,
    pub dir: String,
    /// For `Save`, the name suggested.
    pub name: String,
}

/// How a dialog ended.
#[derive(Debug, PartialEq)]
pub enum Outcome {
    Chosen(PathBuf),
    Cancelled,
    /// No portal to ask: not the user's doing, and not worth a message.
    Unavailable,
}

const SOUNDS: &[&str] = &["wav", "wave", "aif", "aiff", "flac", "mp3", "ogg", "oga"];
const MIDI: &[&str] = &["mid", "midi", "smf", "kar"];

/// The filters a dialog offers for a kind of file, as (label, patterns).
/// Both cases of each ending are listed, for patterns are case-sensitive.
/// The first is the one shown at first; the last is every file.
/// `render:wav,flac,mp3` offers just those endings.
pub fn filters(files: &str) -> Vec<(&'static str, Vec<String>)> {
    let both = |endings: &[&str]| -> Vec<String> {
        endings
            .iter()
            .flat_map(|e| [format!("*.{e}"), format!("*.{}", e.to_uppercase())])
            .collect()
    };
    let mut out = match files {
        "project" => vec![("Projects", both(&["json"]))],
        // What `open` takes: a project, a MIDI file as a new project, or a
        // sound file on a new track.
        "open" => vec![
            ("Projects", both(&["json"])),
            ("MIDI files", both(MIDI)),
            ("Sound files", both(SOUNDS)),
        ],
        // What `import` takes: a sound file, or a MIDI file's tracks.
        "sound" => vec![("Sound and MIDI files", both(&[SOUNDS, MIDI].concat())), ("MIDI files", both(MIDI))],
        _ if files.starts_with("render:") => {
            let endings: Vec<&str> = files["render:".len()..].split(',').collect();
            vec![("Sound files", both(&endings))]
        }
        _ => vec![],
    };
    out.push(("All files", vec!["*".to_string()]));
    out
}

/// The local path a chosen `file://` address names, percent-escapes undone.
fn path_of(uri: &Url) -> Option<PathBuf> {
    uri.to_file_path().ok()
}

struct Unpark(Thread);

impl Wake for Unpark {
    fn wake(self: Arc<Self>) {
        self.0.unpark();
    }
}

/// Wait for a future on this thread. The D-Bus connection runs on threads
/// of its own, so nothing else is needed to make progress.
fn block_on<T>(future: impl Future<Output = T>) -> T {
    let mut future = pin!(future);
    let waker = Waker::from(Arc::new(Unpark(thread::current())));
    let mut cx = Context::from_waker(&waker);
    loop {
        if let Poll::Ready(value) = future.as_mut().poll(&mut cx) {
            return value;
        }
        thread::park();
    }
}

async fn request(ask: &Ask) -> Result<Option<PathBuf>, Error> {
    let dir = (!ask.dir.is_empty()).then(|| Path::new(&ask.dir));
    let filters: Vec<FileFilter> = filters(&ask.files)
        .iter()
        .map(|(label, patterns)| {
            patterns
                .iter()
                .fold(FileFilter::new(label), |f, pattern| f.glob(pattern))
        })
        .collect();
    let selected = match ask.kind {
        Kind::Save => {
            SaveFileRequest::default()
                .title(ask.title.as_str())
                .modal(true)
                .filters(filters)
                .current_name(ask.name.as_str())
                .current_folder::<&Path>(dir)?
                .send()
                .await?
                .response()?
        }
        Kind::Open => {
            OpenFileRequest::default()
                .title(ask.title.as_str())
                .modal(true)
                .filters(filters)
                .current_folder::<&Path>(dir)?
                .send()
                .await?
                .response()?
        }
    };
    Ok(selected.uris().first().and_then(path_of))
}

/// Show the dialog and wait for it to end. Blocks: run it on a thread.
pub fn choose(ask: &Ask) -> Outcome {
    match block_on(request(ask)) {
        Ok(Some(path)) => Outcome::Chosen(path),
        Ok(None) | Err(Error::Response(ResponseError::Cancelled)) => Outcome::Cancelled,
        Err(_) => Outcome::Unavailable,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn filters_end_with_every_file_and_cover_both_cases() {
        for kind in ["project", "open", "sound", "render:wav,mp3", "anything"] {
            assert_eq!(filters(kind).last().unwrap().0, "All files", "{kind}");
        }
        assert_eq!(filters("project")[0].1, ["*.json", "*.JSON"]);
        assert_eq!(filters("render:wav,mp3")[0].1, ["*.wav", "*.WAV", "*.mp3", "*.MP3"]);
        let sounds = &filters("sound")[0].1;
        for ending in ["wav", "aiff", "aif", "flac", "mp3", "ogg", "mid", "midi"] {
            assert!(sounds.contains(&format!("*.{ending}")), "{ending}");
            assert!(sounds.contains(&format!("*.{}", ending.to_uppercase())), "{ending}");
        }
    }

    #[test]
    fn a_chosen_address_becomes_a_path_with_its_spaces() {
        let uri = Url::parse("file:///home/me/my%20songs/take%20%231.wav").unwrap();
        assert_eq!(path_of(&uri), Some(PathBuf::from("/home/me/my songs/take #1.wav")));
        let elsewhere = Url::parse("https://example.org/a.wav").unwrap();
        assert_eq!(path_of(&elsewhere), None);
    }

    /// The check itself; it runs only in the child process of the test below.
    #[test]
    fn child_asks_a_portal_without_a_session_bus() {
        if std::env::var_os("PAW_PORTAL_CHILD").is_none() {
            return;
        }
        let ask = Ask {
            kind: Kind::Open,
            title: "Open".into(),
            files: "open".into(),
            dir: "/".into(),
            name: String::new(),
        };
        assert_eq!(choose(&ask), Outcome::Unavailable);
    }

    #[test]
    fn without_a_session_bus_the_answer_is_that_there_is_no_portal() {
        // A child process gets the variables, so no test thread changes the environment.
        let out = std::process::Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "portal::tests::child_asks_a_portal_without_a_session_bus", "--test-threads=1"])
            .env("PAW_PORTAL_CHILD", "1")
            .env("DBUS_SESSION_BUS_ADDRESS", "unix:path=/nonexistent/bus")
            .env("XDG_RUNTIME_DIR", "/nonexistent")
            .output()
            .unwrap();
        assert!(out.status.success(), "{}{}", String::from_utf8_lossy(&out.stdout), String::from_utf8_lossy(&out.stderr));
        assert!(String::from_utf8_lossy(&out.stdout).contains("1 passed"));
    }

    #[test]
    fn a_future_that_is_ready_later_is_waited_for() {
        let mut polls = 0;
        let value = block_on(std::future::poll_fn(|cx| {
            polls += 1;
            if polls < 3 {
                let waker = cx.waker().clone();
                thread::spawn(move || waker.wake());
                Poll::Pending
            } else {
                Poll::Ready(7)
            }
        }));
        assert_eq!(value, 7);
    }
}
