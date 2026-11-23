//! Plugins and the helper processes that hold them (paw-plugins), and the
//! registry of devices with them. A BrowserPod pod has no plugins: there
//! the registry has the built-in devices only (web/browserpod/README.md).

use paw_engine::Registry;

use crate::args;

/// The registry of devices, with the plugin scan. Returns the scan's notes
/// and how many of them come from the scan itself.
#[cfg(not(target_vendor = "browserpod"))]
pub fn registry(args: &args::Run, display_note: Option<String>) -> (Registry, Vec<String>, usize) {
    let mut registry = Registry::with_builtins();
    // Devices written in Lua always run in helpers: Lua must not run on
    // the audio thread.
    if let Ok(exe) = std::env::current_exe() {
        paw_luadev::set_helper(exe, paw_plugins::sandbox::remote);
    }
    // The folders to search are resolved once, here at the start, from
    // this program's environment. The scan, the rescans and the folders
    // that extensions add share the one value.
    let dirs = std::rc::Rc::new(std::cell::RefCell::new(paw_plugins::PluginDirs::from_env(
        |name| std::env::var_os(name),
    )));
    // Directories an extension adds are looked in even without the
    // plugins installed on the machine.
    let cache = crate::cache_dir().join("plugins.json");
    registry.set_add_dir(std::rc::Rc::new({
        let (cache, dirs) = (cache.clone(), dirs.clone());
        move |registry, dir| {
            paw_plugins::add_dir(registry, Some(&cache), &mut dirs.borrow_mut(), dir)
        }
    }));
    registry.set_remove_dir(std::rc::Rc::new({
        let dirs = dirs.clone();
        move |dir| dirs.borrow_mut().remove(dir)
    }));
    registry.set_plugin_dirs(std::rc::Rc::new({
        let dirs = dirs.clone();
        move || dirs.borrow().by_format()
    }));
    registry.set_attach(std::rc::Rc::new(paw_plugins::attach::add));
    let mut plugin_notes = if args.no_plugins {
        Vec::new()
    } else {
        // Each plugin gets a process of its own, started from this program.
        if !args.plugins_in_process
            && let Ok(exe) = std::env::current_exe()
        {
            paw_plugins::sandbox::set_host_command(
                vec![exe.to_string_lossy().into_owned(), "plugin-host".into()],
                Some(&cache),
            );
        }
        let notes = paw_plugins::register(&mut registry, Some(&cache), &dirs.borrow());
        paw_plugins::sandbox::wrap(&mut registry, &dirs.borrow());
        registry.set_rescan(std::rc::Rc::new(move |registry, name| {
            paw_plugins::rescan(registry, Some(&cache), name, &dirs.borrow())
        }));
        notes
    };
    // What the scan said, apart from the note about the display.
    let scanned = plugin_notes.len();
    plugin_notes.extend(display_note);
    (registry, plugin_notes, scanned)
}

/// In a pod: the built-in devices only, and no notes.
#[cfg(target_vendor = "browserpod")]
pub fn registry(_args: &args::Run, display_note: Option<String>) -> (Registry, Vec<String>, usize) {
    (
        Registry::with_builtins(),
        display_note.into_iter().collect(),
        0,
    )
}

/// A terminal older than the display it names cannot open a plugin's
/// window: put that right. Returns a note for the user, if any.
///
/// # Safety
///
/// It changes the environment: call it while no other thread runs.
pub unsafe fn repair_display_env() -> Option<String> {
    #[cfg(not(target_vendor = "browserpod"))]
    {
        let home = crate::home_dir();
        // SAFETY: The caller promises that no other thread runs.
        unsafe { paw_plugins::repair_display_env(home.as_deref()) }
    }
    #[cfg(target_vendor = "browserpod")]
    None
}

/// `paw plugin-host`: hold one plugin, or one Lua device, in this process.
/// Returns the exit code.
///
/// # Safety
///
/// Only the helper that a running paw started calls it: the socket and the
/// memory named in `args` are descriptors it inherited, and no thread has
/// started yet.
pub unsafe fn host(args: &[String]) -> i32 {
    #[cfg(not(target_vendor = "browserpod"))]
    {
        // A device written in Lua is held the way a plugin is.
        if args.first().is_some_and(|kind| kind.starts_with("lua:")) {
            // SAFETY: As the caller promises.
            return unsafe {
                paw_plugins::sandbox::serve_with(args, |_, rate, block| {
                    paw_luadev::serve_make(rate, block)
                })
            };
        }
        // The helper looks for the plugin where the program that started it
        // did: the same environment, and the folders that it added.
        let dirs = paw_plugins::PluginDirs::for_helper(|name| std::env::var_os(name));
        // SAFETY: As the caller promises.
        unsafe { paw_plugins::sandbox::serve(args, &dirs) }
    }
    #[cfg(target_vendor = "browserpod")]
    {
        let _ = args;
        eprintln!("paw: this build of paw holds no plugins");
        1
    }
}

/// `paw plugin-scan`: look into plugin files. Returns the exit code.
pub fn scan(args: &[String]) -> i32 {
    #[cfg(not(target_vendor = "browserpod"))]
    return paw_plugins::scan_main(
        args,
        &paw_plugins::PluginDirs::from_env(|name| std::env::var_os(name)),
    );
    #[cfg(target_vendor = "browserpod")]
    {
        let _ = args;
        eprintln!("paw: this build of paw holds no plugins");
        1
    }
}
