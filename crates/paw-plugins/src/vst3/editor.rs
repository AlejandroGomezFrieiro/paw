//! The plugin's editor: its view, embedded in one of our X11 windows, and
//! what the window and the plugin ask for while it is open. Main thread.
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::cast_possible_wrap, reason = "debt: pay down")]
#![expect(clippy::cast_sign_loss, reason = "debt: pay down")]

use std::cell::Cell;
use std::ffi::c_void;
use std::ptr;

use anyhow::{Context, Result, bail};
use paw_engine::Controller;
use vst3::Steinberg::Vst::*;
use vst3::Steinberg::*;
use vst3::{ComPtr, ComWrapper};

use super::OK;
use super::controller::Vst3Controller;
use super::host::Frame;
use crate::window::{HostWindow, WindowEvent, ui_scale};

const X11_EMBED: &std::ffi::CStr = c"X11EmbedWindowID";

/// An open editor: the plugin's view inside one of our windows.
pub(super) struct Editor {
    view: ComPtr<IPlugView>,
    frame: ComWrapper<Frame>,
    window: HostWindow,
}

impl Vst3Controller {
    /// React to what happened to the editor window and what the plugin asked for.
    pub(super) fn run_editor(&mut self) {
        let Some(editor) = self.editor.as_mut() else {
            return;
        };
        let mut close = false;
        // SAFETY: The editor's view is a live COM object and its window is ours; the calls are on the
        // main thread, and `rect` is a live local the plugin reads or writes.
        unsafe {
            let fit = |editor: &mut Editor, width: u32, height: u32| {
                let mut rect = ViewRect {
                    left: 0,
                    top: 0,
                    right: width as i32,
                    bottom: height as i32,
                };
                editor.view.onSize(&raw mut rect);
                editor.window.resize(width, height);
            };
            if let Some((width, height)) = editor.frame.resize.take() {
                fit(editor, width, height);
            }
            for event in editor.window.events() {
                match event {
                    WindowEvent::Closed => close = true,
                    WindowEvent::Resized(width, height) => {
                        let mut rect = ViewRect {
                            left: 0,
                            top: 0,
                            right: width as i32,
                            bottom: height as i32,
                        };
                        if editor.view.canResize() == OK {
                            // The plugin may round the size to one it can draw.
                            editor.view.checkSizeConstraint(&raw mut rect);
                        } else {
                            editor.view.getSize(&raw mut rect);
                        }
                        fit(
                            editor,
                            (rect.right - rect.left).max(1) as u32,
                            (rect.bottom - rect.top).max(1) as u32,
                        );
                    }
                }
            }
        }
        if close {
            self.close_window();
        }
    }

    /// Open the plugin's editor in one of our windows.
    pub(super) fn open_window(&mut self, title: &str) -> Result<()> {
        if self.editor.is_some() {
            return Ok(());
        }
        let controller = self
            .shared
            .controller
            .as_ref()
            .context("this plugin has no editor")?;
        // SAFETY: `controller` is live; the view is checked for null by `from_raw`; the frame and the
        // window outlive the view (they are stored in `Editor`, and dropped after `removed`); the
        // X11 window id is ours; the calls are made in the order of the ABI, on the main thread.
        unsafe {
            let view: ComPtr<IPlugView> =
                ComPtr::from_raw(controller.createView(c"editor".as_ptr()))
                    .context("this plugin has no editor")?;
            if view.isPlatformTypeSupported(X11_EMBED.as_ptr()) != OK {
                bail!("the plugin's editor cannot be embedded in an X11 window");
            }
            let frame = ComWrapper::new(Frame {
                resize: Cell::new(None),
                watches: self.shared.host.watches.clone(),
            });
            view.setFrame(
                frame
                    .as_com_ref::<IPlugFrame>()
                    .expect("the object implements IPlugFrame")
                    .as_ptr(),
            );
            // Before asking for the size, which depends on it.
            if let Some(scaling) = view.cast::<IPlugViewContentScaleSupport>() {
                scaling.setContentScaleFactor(ui_scale() as f32);
            }
            let mut rect = ViewRect {
                left: 0,
                top: 0,
                right: 640,
                bottom: 480,
            };
            view.getSize(&raw mut rect);
            let (width, height) = (
                (rect.right - rect.left).max(1) as u32,
                (rect.bottom - rect.top).max(1) as u32,
            );
            let mut window = HostWindow::new(title, width, height)?;
            window.set_fixed(view.canResize() != OK);
            if view.attached(window.id() as usize as *mut c_void, X11_EMBED.as_ptr()) != OK {
                view.setFrame(ptr::null_mut());
                bail!("the plugin refused the editor window");
            }
            self.shared.host.rescan.set(true);
            self.editor = Some(Editor {
                view,
                frame,
                window,
            });
        }
        self.take_changes();
        Ok(())
    }

    /// Close the editor: the plugin's view first, then our window.
    pub(super) fn close_window(&mut self) {
        if let Some(editor) = self.editor.take() {
            // SAFETY: `editor.view` is the live view that `open_window` attached; `removed` and `setFrame(null)`
            // are called once, before the view and the window are dropped.
            unsafe {
                editor.view.removed();
                editor.view.setFrame(ptr::null_mut());
            }
            // The view goes first, then the window it was drawn in.
            drop(editor.view);
            drop(editor.window);
        }
    }
}
