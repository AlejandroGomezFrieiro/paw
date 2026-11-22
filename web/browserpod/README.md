# paw in a BrowserPod pod

The files in this folder build a pod image of paw, so that a page of the docs
can run the real terminal paw in the visitor's browser. BrowserPod, by
Leaning Technologies, runs Linux programs compiled to WebAssembly inside a
browser tab. The image holds paw built for BrowserPod, the demo song as a
project, the bundled extensions with the course, and a small JavaScript API
that opens paw at a project, a lesson or a scope and types keys into it.

## Try it

The steps below build the image, serve it on your machine and open the demo page
in Chromium.

1. Build the image with `nix build .#paw-pod`. The `result` link then points
   at a folder with `demo.html`, `paw-pod.js` and `home.ext2`.
2. Serve the folder with `python3 web/browserpod/serve.py result 8000`.
3. Open `http://127.0.0.1:8000/demo.html` in Chromium and press Start. After
   about three seconds, the arrange view of the demo song shows in the page.
4. Press "Show me: play and stop", and the song plays for three seconds.
5. Stop the server with `Ctrl-c`.

## How to

### How to build the image

Run `nix build .#paw-pod`. The build downloads BrowserPod's Rust pack and
the Rust nightly that it needs, each with a fixed hash, and builds paw for
the target `wasm32-browserpod-linux-musl` without a network. The build only
works on x86_64 Linux, because the pack is made for it. To build paw for the
pod alone, run `nix build .#paw-pod-bin`.

The image is reproducible. To check it, run
`nix build .#paw-pod --rebuild`, which builds it again and fails if a byte
differs.

### How to test the image

Run `web/browserpod/test.sh result`. The script serves the image, opens the
demo page in headless Chromium, and checks the terminal size, the keys, a
scope, a lesson and the sound. It writes the screens and the times to
`target/browserpod/test.json`. With `--no-headers` as the third argument,
the server sends no isolation headers, as GitHub Pages does, and `coi.js`
isolates the page.

The test loads BrowserPod's runtime and base disk from BrowserPod's servers,
as each visitor of the page does. At the end, the script prints the bytes
that the local server sent for each file. The pod reads only the parts of
`home.ext2` that it needs, about 26 MB of its 100 MB.

### How to update the lock of the pod build

BrowserPod's pack patches the crates `libc`, `rustix` and `linux-raw-sys`
at fixed versions, so the pod build uses its own lock,
`web/browserpod/Cargo.lock`. After a change to `Cargo.lock`, run
`nix develop .#browserpod -c web/browserpod/lock.sh`. The pod build fails
with `--locked` until you do.

### How to embed paw in a page

1. Copy the image folder next to the page, or give its URL as `base`.
2. Make the page cross-origin isolated. Either the server sends the headers
   `Cross-Origin-Opener-Policy: same-origin` and
   `Cross-Origin-Embedder-Policy: require-corp`, or the page loads
   `coi.js` first, which reloads the page once through a service worker.
3. Show the credit "Powered by BrowserPod" with a link to
   `https://browserpod.io` on the page, because BrowserPod's Community
   License asks for it.
4. Boot the pod from a click, so that nothing loads before the visitor asks
   for it:

   ```js
   import { PawPod } from "./paw-pod.js";

   button.onclick = async () => {
     const pod = await PawPod.boot({ element: document.getElementById("paw") });
     await pod.audio.start();
     await pod.open({ project: "demo-song", scope: "Melody" });
     await pod.sendKeys("<Space><Space>");
   };
   ```

`demo.html` is a complete example.

## Reference

### The API for pages

`paw-pod.js` is an ES module.

| Name | What it does |
| --- | --- |
| `PawPod.boot({ element, base, cols, rows })` | Loads BrowserPod's runtime, boots a pod with the home image and makes a terminal of `cols` by `rows` cells (100 by 30 by default) in `element`. `base` is the URL of the image folder, by default the folder of `paw-pod.js`. |
| `pod.open(state)` | Quits paw if it runs, without saving, and starts it at `state`. It resolves when paw has drawn its first screen. |
| `pod.sendKeys(keys, { delay })` | Types keys in Vim notation, one key each `delay` milliseconds (40 by default). |
| `pod.waitFor(text, timeout)` | Waits until the terminal shows `text`, a string or a regular expression. |
| `pod.screen()` | The text of the terminal, one string for each row. |
| `pod.size()` | The size of the terminal in cells, and the size of a cell in pixels. |
| `pod.quit()` | Quits paw without saving. |
| `pod.audio.start()`, `pod.audio.stop()` | Plays the sound of paw in the page, or stops it. Call `start` from a click, because a browser plays sound only after a gesture of the user. |
| `pod.audio.stats()` | The frames that came from paw, the frames dropped, the frames played, the underruns and the peak level. |
| `pod.manifest` | The paw version, the git revision, the BrowserPod version and the SHA-256 of each file. |
| `parseKeys(keys)`, `pawArgs(state)` | The bytes of each key, and the command line of paw for a state. |

The states that `open` takes:

| State | paw starts with |
| --- | --- |
| `{ project: "demo-song" }` | A project of the image, from `/home/user/projects`. It's the default. |
| `{ lesson: 3 }`, `{ lesson: "visual" }` | A lesson of the course, from its start (`:tutor!`). |
| `{ scope: "Melody" }` | With a project, the window narrowed to a region or a group (`:narrow`). The demo song has the regions `Chords` and `Melody`. |
| `{ keys: "jj" }` | Keys typed after startup (`--keys`). |
| `{ lua: "..." }` | Lua run after startup (`-e`). |

`sendKeys` knows `<Esc>`, `<CR>`, `<Space>`, `<Tab>`, `<BS>`, `<Del>`,
`<Up>`, `<Down>`, `<Left>`, `<Right>`, `<Home>`, `<End>`, `<PageUp>`,
`<PageDown>`, `<lt>`, `<C-x>` and `<A-x>`. After a lone `<Esc>` it waits
60 milliseconds, so that paw doesn't read the next key as Alt and that key.

### The files of the image

| File | What it is |
| --- | --- |
| `home.ext2` | The home folder of the pod, an ext2 file system that BrowserPod mounts on `/home`. `user/bin/paw` is paw, `user/paw` is `PAW_HOME` with the bundled extensions and the examples, and `user/projects/demo-song` is the demo song. |
| `files.txt` | The list of what `home.ext2` holds. |
| `manifest.json` | The paw version, the revision, the BrowserPod version and the SHA-256 of each file. |
| `paw-pod.js`, `audio-worklet.js` | The JavaScript API, and the AudioWorklet that plays the sound. |
| `coi.js`, `coi-sw.js` | Cross-origin isolation on a host that can't set headers. |
| `demo.html` | The demo page. |

### The sound

paw in the pod plays through its audio backend `page`, which `--audio auto`
chooses there. The pod has no sound device, but each HTTP request of the
pod goes through the page's `fetch`, so the page answers the host
`audio.paw`:

| Request | Answer |
| --- | --- |
| `GET /open` | The sample rate of the page, 48000, as text. |
| `POST /pcm` | The body is stereo frames, little-endian 32-bit floats with left and right in turn. The page puts them into a ring in a `SharedArrayBuffer`, and the AudioWorklet plays them. The answer has no body. |

The worklet waits for 4096 frames before it plays, and again after an
underrun. The page keeps at most a quarter second in the ring, so the sound
comes about 0.1 to 0.25 seconds after the key.

### Limits

- paw in the pod has no plugins, no devices written in Lua, no MIDI ports
  and no sound input.
- paw runs its Lua on PUC Lua 5.2, because LuaJIT can't run in WebAssembly.
  Lua code runs about five times slower than with LuaJIT.
- The terminal has a fixed size. BrowserPod's terminal tells the pod its
  size only once, when the pod makes it.
- The page works best in Chromium. BrowserPod lists limits for Firefox and
  Safari.
- The runtime and the base disk of BrowserPod load from BrowserPod's
  servers. The license doesn't allow a copy on another server, so the page
  doesn't work offline.

## About the pod image

The browser plan of paw has two paths. The full app is to be one WebAssembly
module built with Emscripten, which runs offline and plays sound on the
audio thread of the page. BrowserPod is the second path, for a demo in the
docs, because it runs the same terminal program with few changes. The
changes are part of the source and depend on the target: `cfg(target_vendor
= "browserpod")` in the code, and dependencies for that target in the
`Cargo.toml` files.

BrowserPod is free under its Community License, which asks for a visible
credit that links to `https://browserpod.io`. It doesn't allow a copy of
its runtime on another server, so the page loads the runtime from
BrowserPod's servers, and only after the visitor presses a button. A page
that embeds the pod should say in its privacy note that the browser then
loads files from BrowserPod's servers.
