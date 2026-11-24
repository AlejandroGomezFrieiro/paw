---
type: C4 Component
title: State
status: stable
groma:
  id: frontend-state
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/frontend/state.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/frontend/state.tl](../../../../../../runtime/lua/paw/frontend/state.tl) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callbacks: paw.api.lane_list, paw.api.lane_points | teal |
| [runtime/lua/paw/frontend/state.tl](../../../../../../runtime/lua/paw/frontend/state.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_get, paw.api.clip_list, paw.api.clip_notes, paw.api.clip_peaks, paw.api.media_peaks | teal |
| [runtime/lua/paw/frontend/state.tl](../../../../../../runtime/lua/paw/frontend/state.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_get, paw.api.device_types | teal |
| [runtime/lua/paw/frontend/state.tl](../../../../../../runtime/lua/paw/frontend/state.tl) | [crates/paw-core/src/api/engine.rs](../../../../../../crates/paw-core/src/api/engine.rs) | Invokes supplied callbacks: paw.api.engine_get, paw.api.render_status | teal |
| [runtime/lua/paw/frontend/state.tl](../../../../../../runtime/lua/paw/frontend/state.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/frontend/state.tl](../../../../../../runtime/lua/paw/frontend/state.tl) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callback: paw.api.project_get | teal |
| [runtime/lua/paw/frontend/state.tl](../../../../../../runtime/lua/paw/frontend/state.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.ui_redraw, paw.api.ui_redraws, paw.api.ui_snapshot | teal |
| [runtime/lua/paw/frontend/state.tl](../../../../../../runtime/lua/paw/frontend/state.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [runtime/lua/paw/frontend/state.tl](../../../../../../runtime/lua/paw/frontend/state.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_meter | teal |
| [runtime/lua/paw/frontend/state.tl](../../../../../../runtime/lua/paw/frontend/state.tl) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_get | teal |
| [runtime/lua/paw/frontend/state.tl](../../../../../../runtime/lua/paw/frontend/state.tl) | [runtime/lua/paw/frontend/core.tl](../../../../../../runtime/lua/paw/frontend/core.tl) | Invokes supplied callbacks: paw.frontend.core.band_state, paw.frontend.core.bands, paw.frontend.core.chosen_clips, paw.frontend.core.completions, paw.frontend.core.content_key, paw.frontend.core.lane_name, paw.frontend.core.lane_span, paw.frontend.core.max_params, paw.frontend.core.menus, paw.frontend.core.peak_points, paw.frontend.core.preview_notes, paw.frontend.core.revision, paw.frontend.core.routing, paw.frontend.core.send_list, paw.frontend.core.take_rows, paw.frontend.core.vca_words, require("paw.frontend.core") | teal |
| [runtime/lua/paw/frontend/state.tl](../../../../../../runtime/lua/paw/frontend/state.tl) | [runtime/lua/paw/frontend/host.tl](../../../../../../runtime/lua/paw/frontend/host.tl) | Invokes supplied callbacks: paw.frontend.host.devices, paw.frontend.host.paw, require("paw.frontend.host") | teal |
| [runtime/lua/paw/frontend/state.tl](../../../../../../runtime/lua/paw/frontend/state.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/frontend/state.tl](../../../../../../runtime/lua/paw/frontend/state.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callbacks: paw.seats.current, require("paw.seats") | teal |
| [runtime/lua/paw/frontend/state.tl](../../../../../../runtime/lua/paw/frontend/state.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, require("paw.util") | teal |
