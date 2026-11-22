// paw in a BrowserPod pod, for the pages of the docs.
//
//   import { PawPod } from "./paw-pod.js";
//   const pod = await PawPod.boot({ element: document.getElementById("paw") });
//   await pod.open({ project: "demo-song", scope: "Chords" });
//   await pod.sendKeys("jj<Space>");
//
// The page must be cross-origin isolated (coi.js does it on a host that
// cannot set headers). BrowserPod's runtime loads from its CDN when
// `boot` runs, and not before. The page that hosts the pod shows a
// "Powered by BrowserPod" credit that links to https://browserpod.io (the
// BrowserPod Community Licence). web/browserpod/README.md has the rest.

/** The BrowserPod release that this image is built and tested with. */
export const BROWSERPOD_VERSION = "4.1.0";
const RUNTIME = `https://rt.browserpod.io/${BROWSERPOD_VERSION}/browserpod.js`;

/** The host that the pod's paw sends its sound to (crates/paw-engine/src/backend/page.rs). */
const AUDIO_HOST = "audio.paw";
const RATE = 48000;
/** The ring holds one second; the page keeps at most a quarter of it filled. */
const RING_FRAMES = RATE;
const MAX_FILL_FRAMES = RATE / 4;
/** The frames that the worklet waits for before it plays. */
const PREFILL_FRAMES = 4096;

/** Keys in Vim notation, as bytes for the terminal. */
const NAMED = {
  esc: "\x1b",
  cr: "\r",
  enter: "\r",
  return: "\r",
  space: " ",
  leader: " ",
  tab: "\t",
  bs: "\x7f",
  del: "\x1b[3~",
  lt: "<",
  bar: "|",
  bslash: "\\",
  up: "\x1b[A",
  down: "\x1b[B",
  right: "\x1b[C",
  left: "\x1b[D",
  home: "\x1b[H",
  end: "\x1b[F",
  pageup: "\x1b[5~",
  pagedown: "\x1b[6~",
};

/**
 * Split keys in Vim notation into the bytes of each key:
 * `"jj<Space><C-o>:w<CR>"` gives `["j", "j", " ", "\x0f", ":", "w", "\r"]`.
 * @param {string} keys
 * @returns {string[]}
 */
export function parseKeys(keys) {
  const out = [];
  for (let i = 0; i < keys.length; ) {
    const m = keys[i] === "<" ? /^<([^<>]+)>/.exec(keys.slice(i)) : null;
    if (m) {
      const name = m[1].toLowerCase();
      const ctrl = /^c-(.)$/.exec(name);
      const alt = /^[am]-(.+)$/.exec(m[1]);
      if (NAMED[name] !== undefined) out.push(NAMED[name]);
      else if (ctrl) out.push(String.fromCharCode(ctrl[1].toUpperCase().charCodeAt(0) & 0x1f));
      else if (alt) out.push("\x1b" + (NAMED[alt[1].toLowerCase()] ?? alt[1]));
      else throw new Error(`unknown key <${m[1]}>`);
      i += m[0].length;
    } else {
      out.push(keys[i]);
      i += 1;
    }
  }
  return out;
}

/** The command line of paw for a state (see `PawPod.open`). */
export function pawArgs(state = {}) {
  const args = ["--no-plugins", "--clean"];
  const lua = [];
  if (state.project) args.push(`projects/${state.project}`);
  else if (state.lesson === undefined) args.push("projects/demo-song");
  if (state.lesson !== undefined) {
    lua.push(`paw.ext.load_bundled("tutor")`, `paw.ex.exec("tutor! ${String(state.lesson).replace(/"/g, "")}")`);
  }
  if (state.scope) lua.push(`paw.ex.exec(${JSON.stringify("narrow " + state.scope)})`);
  if (state.lua) lua.push(state.lua);
  if (lua.length) args.push("-e", lua.join("\n"));
  if (state.keys) args.push("--keys", state.keys);
  return args;
}

/** paw in a pod, in an element of the page. */
export class PawPod {
  /**
   * Boot a pod with paw's home image, and make its terminal in `element`,
   * `cols` by `rows` cells whatever the size of the page. Nothing runs in
   * it yet: `open` starts paw.
   * @param {{ element: HTMLElement, base?: string, cols?: number, rows?: number }} options
   *   `base` is where manifest.json and the image are (by default, beside this file).
   */
  static async boot({ element, base = new URL(".", import.meta.url).href, cols = 100, rows = 30 }) {
    if (!self.crossOriginIsolated) {
      throw new Error("the page is not cross-origin isolated: serve it with COOP and COEP headers, or load coi.js");
    }
    const manifest = await (await fetch(new URL("manifest.json", base))).json();
    const pod = new PawPod(element, manifest, cols, rows);
    const image = new URL(`${manifest.image}?v=${manifest.files[manifest.image]}`, base).href;
    const { BrowserPod } = await import(RUNTIME);
    const network = await BrowserPod.createFetchNetwork({ fetch: (url, init) => pod.#fetch(url, init) });
    pod.#pod = await BrowserPod.boot({ network, userImage: image });
    pod.terminal = await pod.#makeTerminal();
    return pod;
  }

  /** @private Use `PawPod.boot`. */
  constructor(element, manifest, cols, rows) {
    this.element = element;
    /** The paw version, BrowserPod version and file hashes of the image. */
    this.manifest = manifest;
    this.cols = cols;
    this.rows = rows;
    this.audio = new PodAudio();
    this.process = null;
  }

  /** @type {any} */
  #pod = null;

  /** The pod's network: the sound goes to the worklet, the rest to the page's fetch. */
  async #fetch(url, init) {
    const u = new URL(url);
    if (u.hostname !== AUDIO_HOST) return init.defaultFetch(url, init);
    if (u.pathname === "/open") return new Response(String(RATE), { headers: { "Content-Type": "text/plain" } });
    if (u.pathname === "/pcm") {
      this.audio.write(new Float32Array(await new Response(init.body).arrayBuffer()));
      return new Response(null, { status: 204 });
    }
    return new Response("not found", { status: 404 });
  }

  /**
   * Make a terminal of `cols` by `rows` cells. BrowserPod's terminal fits
   * itself to its element, and the pod's tty keeps the size that it had
   * when it was made: later fits change only the page's side. So the
   * element gets its size first, from the size of a cell of the font that
   * BrowserPod uses (`monospace` at the size of the body's font). Where
   * the guess is wrong (the terminal keeps room for a scroll bar), a new
   * terminal is made at the corrected size.
   */
  async #makeTerminal() {
    const fontSize = parseInt(getComputedStyle(document.body).fontSize, 10);
    const probe = document.createElement("span");
    probe.style.cssText = `position:absolute;visibility:hidden;white-space:pre;font-family:monospace;font-size:${fontSize}px`;
    probe.textContent = "W".repeat(50);
    document.body.append(probe);
    const box = probe.getBoundingClientRect();
    probe.remove();
    let width = (this.cols * box.width) / 50 + 16;
    let height = this.rows * Math.ceil(box.height);
    for (let attempt = 0; attempt < 4; attempt++) {
      const host = document.createElement("div");
      host.style.width = `${Math.ceil(width)}px`;
      host.style.height = `${Math.ceil(height)}px`;
      this.element.replaceChildren(host);
      const terminal = await this.#pod.createDefaultTerminal(host);
      this.terminal = terminal;
      const { cols, rows, cellWidth, cellHeight } = this.size();
      if (cols === this.cols && rows === this.rows) return terminal;
      width += (this.cols - cols) * cellWidth;
      height += (this.rows - rows) * cellHeight;
    }
    const { cols, rows } = this.size();
    throw new Error(`the terminal is ${cols}x${rows}, not ${this.cols}x${this.rows}`);
  }

  /** The terminal's size in cells, and the size of one cell in pixels. */
  size() {
    const lines = this.element.querySelectorAll(".xterm-rows > div");
    const measure = this.element.querySelector(".xterm-char-measure-element");
    const box = measure?.getBoundingClientRect();
    const cellWidth = box && measure.textContent.length ? box.width / measure.textContent.length : 0;
    const cellHeight = lines.length ? lines[0].getBoundingClientRect().height : 0;
    // The xterm.js of BrowserPod's terminal knows its size; the rows of
    // its screen tell it too.
    const xterm = this.terminal?.xterm;
    return { cols: xterm?.cols ?? 0, rows: xterm?.rows ?? lines.length, cellWidth, cellHeight };
  }

  /** The text on the terminal, one string for each row. */
  screen() {
    return [...this.element.querySelectorAll(".xterm-rows > div")].map((row) => row.textContent.replace(/ /g, " "));
  }

  /** Wait until the terminal shows `text` (a string or a RegExp). */
  async waitFor(text, timeout = 30000) {
    const found = () => {
      const all = this.screen().join("\n");
      return typeof text === "string" ? all.includes(text) : text.test(all);
    };
    const until = performance.now() + timeout;
    while (!found()) {
      if (performance.now() > until) throw new Error(`the terminal did not show ${text} in ${timeout} ms`);
      await new Promise((r) => setTimeout(r, 50));
    }
  }

  /**
   * Start paw at a state. paw that runs already quits first, without
   * saving. The states:
   * - `{ project: "demo-song" }`: a project of the image (the default).
   * - `{ lesson: 3 }`, `{ lesson: "visual" }`: a lesson of the course, from its start.
   * - `{ scope: "Chords" }`: with a project, narrowed to a region or a group (`:narrow`).
   * - `{ keys: "jj" }`: keys typed after startup; `{ lua: "..." }`: Lua run after startup.
   * Resolves when paw has drawn its first screen.
   */
  async open(state = {}) {
    await this.quit();
    const args = pawArgs(state);
    this.process = this.#pod.run("/home/user/bin/paw", args, {
      terminal: this.terminal,
      cwd: "/home/user",
      env: ["PAW_HOME=/home/user/paw"],
    });
    const running = this.process;
    // A Process is a thenable, not a Promise: its `then` returns nothing.
    this.exited = Promise.resolve(running).then(
      (code) => code,
      (err) => String(err),
    );
    this.exited.then(() => {
      if (this.process === running) this.process = null;
    });
    await this.waitFor(/NORMAL|INSERT|VISUAL|lesson|Lesson/i, 60000);
  }

  /** Quit paw without saving, if it runs. */
  async quit() {
    if (!this.process) return;
    // `:q!` closes one window at a time: again until paw ends.
    for (let tries = 0; tries < 8; tries++) {
      await this.sendKeys("<Esc><Esc>:q!<CR>");
      const late = new Promise((r) => setTimeout(() => r("late"), 2000));
      if ((await Promise.race([this.exited, late])) !== "late") {
        this.process = null;
        return;
      }
    }
    throw new Error(`paw did not quit; the last row says: ${this.screen().at(-1)}`);
  }

  /**
   * Type keys in Vim notation (`"jj<Space>"`, `"<C-o>"`, `":w<CR>"`, `"<Up>"`),
   * one key each `delay` milliseconds, as a person would for "show me".
   * After a lone `<Esc>`, it waits longer than paw's `PAW_TTIMEOUTLEN`
   * (15 ms), so that the next key does not read as Alt and a key.
   */
  async sendKeys(keys, { delay = 40 } = {}) {
    const input = this.element.querySelector("textarea");
    if (!input) throw new Error("no terminal to type into");
    for (const key of parseKeys(keys)) {
      input.dispatchEvent(new InputEvent("input", { data: key, inputType: "insertText", bubbles: true }));
      await new Promise((r) => setTimeout(r, key === "\x1b" ? Math.max(delay, 60) : delay));
    }
  }
}

/** The sound of the pod: a ring in a SharedArrayBuffer, and an AudioWorklet that plays it. */
class PodAudio {
  constructor() {
    this.sab = new SharedArrayBuffer(8 + RING_FRAMES * 2 * 4);
    this.index = new Int32Array(this.sab, 0, 2);
    this.ring = new Float32Array(this.sab, 8, RING_FRAMES * 2);
    /** Frames that came from the pod, and frames dropped because the page did not play them in time. */
    this.received = 0;
    this.dropped = 0;
    this.context = null;
    this.node = null;
  }

  /** Put frames from the pod into the ring: dropped when a quarter second waits already. */
  write(samples) {
    const capacity = this.ring.length;
    let w = Atomics.load(this.index, 0);
    const r = Atomics.load(this.index, 1);
    const filled = (w - r + capacity) % capacity;
    this.received += samples.length / 2;
    if (filled + samples.length > MAX_FILL_FRAMES * 2) {
      this.dropped += samples.length / 2;
      return;
    }
    for (let i = 0; i < samples.length; i++) {
      this.ring[w] = samples[i];
      w = (w + 1) % capacity;
    }
    Atomics.store(this.index, 0, w);
  }

  /**
   * Play the sound. Call it from a click or a key press: a browser starts
   * sound only after a gesture of the user.
   */
  async start() {
    if (!this.context) {
      this.context = new AudioContext({ sampleRate: RATE, latencyHint: "interactive" });
      await this.context.audioWorklet.addModule(new URL("audio-worklet.js", import.meta.url));
      // Drop what waited while nothing played.
      Atomics.store(this.index, 1, Atomics.load(this.index, 0));
      this.node = new AudioWorkletNode(this.context, "paw-pod-player", {
        outputChannelCount: [2],
        processorOptions: { sab: this.sab, capacity: this.ring.length, prefill: PREFILL_FRAMES },
      });
      this.node.connect(this.context.destination);
    }
    await this.context.resume();
  }

  /** Stop the sound; paw goes on. */
  async stop() {
    await this.context?.suspend();
  }

  /** What the worklet played: frames, underruns, the peak level, and what came and was dropped. */
  async stats() {
    const base = { received: this.received, dropped: this.dropped };
    if (!this.node) return { ...base, played: 0, underruns: 0, peak: 0, playing: false };
    const answer = new Promise((resolve) => {
      this.node.port.onmessage = (e) => resolve(e.data);
    });
    this.node.port.postMessage(0);
    return { ...base, ...(await answer), state: this.context.state };
  }
}
