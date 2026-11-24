//! The plugin's editor window: the window system to show it with, its
//! opening and closing, and what the window and the plugin ask for while it
//! is open. Main thread.
#![expect(clippy::cast_lossless, reason = "debt: pay down")]

use std::ffi::CString;
use std::sync::atomic::Ordering::Relaxed;

use anyhow::{Context, Result, bail};
use clack_extensions::gui::{GuiApiType, GuiConfiguration, GuiSize, Window};
use clack_extensions::posix_fd::FdFlags;
use clack_extensions::timer::TimerId;
use paw_engine::Controller;

use super::controller::ClapController;
use crate::window::{HostWindow, WindowEvent, ui_scale};

impl ClapController {
    /// The window system to open the editor with, and whether the plugin
    /// floats it in a window of its own. Embedding in an X11 window comes
    /// first, since that is what nearly every plugin offers and it lets the
    /// host own the window. A plugin that can only float is still shown, as a
    /// native Wayland window if it can make one.
    pub(super) fn editor_api(&self) -> Option<GuiConfiguration<'static>> {
        let gui = self.shared.ext.gui?;
        let wayland = std::env::var_os("WAYLAND_DISPLAY").is_some();
        let configuration = |api_type, is_floating| GuiConfiguration {
            api_type,
            is_floating,
        };
        self.shared.on_main(|plugin| {
            [
                configuration(GuiApiType::X11, false),
                configuration(GuiApiType::WAYLAND, true),
                configuration(GuiApiType::X11, true),
            ]
            .into_iter()
            .filter(|c| wayland || c.api_type != GuiApiType::WAYLAND)
            .find(|c| gui.is_api_supported(plugin, *c))
        })
    }

    /// React to what happened to the editor window and what the plugin asked for.
    pub(super) fn run_editor(&mut self) {
        let shared = &self.shared;
        let Some(editor) = self.editor.as_mut() else {
            return;
        };
        let mut close = shared.flags.closed.swap(false, Relaxed);
        let Some(gui) = shared.ext.gui else {
            return;
        };
        let resize = shared.flags.resize.lock().expect("a thread panicked while it held the lock").take();
        if let (Some(window), Some((width, height))) = (editor.as_mut(), resize) {
            window.resize(width, height);
        }
        let events = editor.as_mut().map(HostWindow::events).unwrap_or_default();
        let mut resized = None;
        for event in events {
            match event {
                WindowEvent::Closed => close = true,
                WindowEvent::Resized(width, height) => {
                    // Let the plugin round the size to one it can draw, then
                    // make the window agree with what it settled on.
                    let asked = GuiSize { width, height };
                    let size = shared.on_main(|plugin| {
                        if gui.can_resize(plugin) {
                            let size = gui.adjust_size(plugin, asked).unwrap_or(asked);
                            let _ = gui.set_size(plugin, size);
                            size
                        } else {
                            gui.get_size(plugin).unwrap_or(asked)
                        }
                    });
                    resized = Some((size.width, size.height));
                }
            }
        }
        if let (Some(window), Some((width, height))) = (editor.as_mut(), resized) {
            window.resize(width, height);
        }
        // Timers and file descriptors drive the plugin's own event handling.
        let (due, ready) = {
            let mut watches = shared.flags.watches.lock().expect("a thread panicked while it held the lock");
            (watches.due_timers(), watches.ready_fds())
        };
        shared.on_main(|plugin| {
            if let Some(timers) = shared.ext.timers {
                for id in due {
                    timers.on_timer(plugin, TimerId(id));
                }
            }
            if let Some(fds) = shared.ext.fds {
                for (fd, ()) in ready {
                    fds.on_fd(plugin, fd, FdFlags::READ);
                }
            }
        });
        if close {
            self.close_window();
        }
    }

    /// Open the plugin's editor, in one of our windows or in its own.
    pub(super) fn open_window(&mut self, title: &str) -> Result<()> {
        if self.editor.is_some() {
            return Ok(());
        }
        let configuration = self
            .editor_api()
            .context("this plugin has no editor this host can show")?;
        let gui = self.shared.ext.gui.context("no gui")?;
        // The calls go in the order the ABI requires: create, set_scale,
        // set_parent, show.
        let window = self.shared.on_main(|plugin| -> Result<Option<HostWindow>> {
            if gui.create(plugin, configuration).is_err() {
                bail!("the plugin could not create its editor");
            }
            // Before asking for the size, which depends on it. Wayland windows
            // are scaled by the compositor instead.
            if configuration.api_type == GuiApiType::X11 {
                let _ = gui.set_scale(plugin, ui_scale());
            }
            let window = if configuration.is_floating {
                // The plugin makes and manages the window; all it gets is a name.
                if let Ok(title) = CString::new(title) {
                    gui.suggest_title(plugin, &title);
                }
                None
            } else {
                let (width, height) = gui
                    .get_size(plugin)
                    .map_or((640, 480), |size| (size.width, size.height));
                let mut window = match HostWindow::new(title, width, height) {
                    Ok(window) => window,
                    Err(err) => {
                        gui.destroy(plugin);
                        return Err(err);
                    }
                };
                // SAFETY: The X11 window lives in `self.editor` until `close_window`, which
                // destroys the plugin's editor before it drops the window.
                let parent = unsafe {
                    gui.set_parent(plugin, Window::from_x11_handle(window.id() as _))
                };
                if parent.is_err() {
                    gui.destroy(plugin);
                    bail!("the plugin refused the editor window");
                }
                window.set_fixed(!gui.can_resize(plugin));
                Some(window)
            };
            let _ = gui.show(plugin);
            Ok(window)
        })?;
        // Remember where every parameter stands, to notice what the editor changes.
        self.shared.flags.rescan.store(true, Relaxed);
        self.editor = Some(window);
        self.take_changes();
        Ok(())
    }

    /// Close the editor: the plugin's window first, then ours.
    pub(super) fn close_window(&mut self) {
        if self.editor.is_none() {
            return;
        }
        if let Some(gui) = self.shared.ext.gui {
            self.shared.on_main(|plugin| {
                let _ = gui.hide(plugin);
                gui.destroy(plugin);
            });
        }
        // The plugin's window is gone; now ours can go.
        self.editor = None;
    }
}
