//! The plugin's state, which Clack streams, and its presets. Main thread.

use std::ffi::CStr;
use std::ptr;

use anyhow::{Context, Result, bail};
use clack_extensions::preset_discovery::PluginPresetLoad;
use clack_extensions::preset_discovery::preset_data::Location;
use clack_host::extensions::{Extension, PluginExtensionSide, RawExtension};
use clack_host::prelude::PluginMainThreadHandle;
use clap_sys::ext::preset_load::{CLAP_EXT_PRESET_LOAD_COMPAT, clap_plugin_preset_load};

use super::controller::ClapController;
use crate::presets::PresetLocation;

impl ClapController {
    /// The plugin's state as it saves it, or `None` when it has no state.
    pub(super) fn save_plugin_state(&mut self) -> Result<Option<Vec<u8>>> {
        let Some(state) = self.shared.ext.state else {
            return Ok(None);
        };
        let mut out = Vec::new();
        self.shared
            .on_main(|plugin| state.save(plugin, &mut out))
            .map_err(|_| anyhow::anyhow!("the plugin could not save its state"))?;
        Ok(Some(out))
    }

    /// Give the plugin a state it saved.
    pub(super) fn load_plugin_state(&mut self, state: &[u8]) -> Result<()> {
        let Some(ext) = self.shared.ext.state else {
            return Ok(());
        };
        let mut rest = state;
        self.shared
            .on_main(|plugin| ext.load(plugin, &mut rest))
            .map_err(|_| anyhow::anyhow!("the plugin rejected the saved state"))?;
        // Some plugins take a state on only in their next block. The mark
        // comes first: a block that the wake starts counts.
        self.given_state();
        self.shared.flags.wake();
        Ok(())
    }
}

/// Load one of the plugin's presets, by the id paw gave it: through the
/// preset-load extension, or its draft (compatible) id.
pub(super) fn load_preset(plugin: &PluginMainThreadHandle, id: &[u8]) -> Result<()> {
    let standard = plugin.get_extension::<PluginPresetLoad>();
    let compat = match standard {
        Some(_) => None,
        None => Some(
            plugin
                .get_extension::<PresetLoadCompat>()
                .context("the plugin cannot load presets")?,
        ),
    };
    let id = String::from_utf8_lossy(id);
    let (location, key) = crate::presets::clap_preset_parts(&id)?;
    let location = location.as_ref().map(PresetLocation::as_location);
    let key = key.as_deref();
    let loaded = location.is_some_and(|location| match (standard, compat) {
        (Some(ext), _) => ext.load_from_location(plugin, location, key).is_ok(),
        (None, Some(ext)) => ext.load_from_location(plugin, location, key),
        (None, None) => false,
    });
    if !loaded {
        bail!("the plugin could not load the preset");
    }
    Ok(())
}

/// The preset-load extension under its draft id, which Clack does not ask
/// for: [`PluginPresetLoad`] asks only for the final one.
#[derive(Clone, Copy)]
struct PresetLoadCompat(RawExtension<PluginExtensionSide, clap_plugin_preset_load>);

// SAFETY: The draft id names the same table as the final one, `clap_plugin_preset_load`.
unsafe impl Extension for PresetLoadCompat {
    const IDENTIFIERS: &'static [&'static CStr] = &[CLAP_EXT_PRESET_LOAD_COMPAT];
    type ExtensionSide = PluginExtensionSide;

    unsafe fn from_raw(raw: RawExtension<PluginExtensionSide>) -> Self {
        // SAFETY: The caller gives the table that the id names.
        Self(unsafe { raw.cast() })
    }
}

impl PresetLoadCompat {
    /// As [`PluginPresetLoad::load_from_location`]: whether the plugin loaded it.
    fn load_from_location(
        &self,
        plugin: &PluginMainThreadHandle,
        location: Location,
        key: Option<&CStr>,
    ) -> bool {
        let Some(from_location) = plugin.use_extension(&self.0).from_location else {
            return false;
        };
        let (kind, path) = location.to_raw();
        let key = key.map_or(ptr::null(), CStr::as_ptr);
        // SAFETY: The function is the plugin's own, called on the main thread with its own
        // plugin; `path` and `key` are null or strings that live through the call.
        unsafe { from_location(plugin.as_raw_ptr(), kind, path, key) }
    }
}
