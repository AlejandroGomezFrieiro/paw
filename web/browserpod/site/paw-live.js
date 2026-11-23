// A live paw in a page of the docs: a panel with a start button, and
// buttons in the text that open paw at a state or type keys into it.
//
//   <div class="paw-live" data-paw-live></div>
//   <span data-paw-open='{"lesson":3,"keys":"<Esc>"}' data-paw-label="Open lesson 3 in paw"></span>
//   <span data-paw-keys='["<Space><Space>",2000,"<Space><Space>"]' data-paw-state='{"lesson":3}'></span>
//   <script type="module" src="pod/paw-live.js"></script>
//
// The module loads nothing from BrowserPod's servers until the reader
// presses "Start paw": then it imports paw-pod.js (beside this file),
// which boots the pod. The panel shows the "Powered by BrowserPod" credit
// that BrowserPod's Community License asks for.
//
// Attributes:
// - data-paw-live: the panel. data-paw-state is the state that Start
//   opens (by default the demo song). data-paw-worker is the URL of
//   coi-sw.js, relative to the page; a page whose server cannot send
//   the isolation headers needs it at the root of the site.
// - data-paw-open: a button that opens paw at a state (PawPod.open).
// - data-paw-keys: a button that types keys, in Vim notation. The value is
//   a key string, or a JSON list of key strings and waits in milliseconds.
//   data-paw-state is the state where the keys belong: when paw shows
//   another state, the button opens that state first.
// - data-paw-label: the text of a button, or of the Start button on the panel.
//
// web/browserpod/README.md describes the component for authors of pages.

const here = new URL(".", import.meta.url);
/** A reload for isolation remembers here that the reader pressed Start. */
const START_KEY = "paw-live-start";
const RELOAD_KEY = "paw-live-reloaded";

const STYLE = `
.paw-live-panel { border: 1px solid var(--table-border-color, #8888); border-radius: 6px; padding: 0.75em; }
.paw-live-panel p { margin: 0 0 0.5em; }
.paw-live-screen { background: #000; overflow: hidden; border-radius: 4px; }
.paw-live-screen:empty { display: none; }
.paw-live-screen > div { transform-origin: 0 0; }
.paw-live-status { min-height: 1.5em; }
.paw-live-credit { font-size: 0.85em; margin-top: 0.5em; }
.paw-live-button { font: inherit; font-size: 0.85em; margin: 0 0.25em; padding: 0.1em 0.6em; cursor: pointer;
  border: 1px solid var(--links, #0645ad); border-radius: 4px; background: transparent; color: var(--links, #0645ad); }
.paw-live-button:disabled { opacity: 0.5; cursor: default; }
.paw-live-start { font-size: 1em; padding: 0.4em 1em; background: var(--links, #0645ad); color: var(--bg, #fff); }
.paw-live-attention { animation: paw-live-pulse 0.6s 3; }
@keyframes paw-live-pulse { 50% { box-shadow: 0 0 0 4px var(--links, #0645ad); } }
`;

/** The live paw of the page: one pod for every button. */
class Live {
  constructor(panel) {
    this.panel = panel;
    this.pod = null;
    /** The state that paw shows now, as the JSON text of the button that opened it. */
    this.state = null;
    /** The one action at a time: a button waits for the one before it. */
    this.queue = Promise.resolve();
    panel.replaceChildren();
    const box = el("div", "paw-live-panel");
    this.start = button(panel.dataset.pawLabel || "Start paw", "paw-live-button paw-live-start");
    this.status = el("p", "paw-live-status");
    this.screen = el("div", "paw-live-screen");
    const credit = el("p", "paw-live-credit");
    credit.append("Powered by ", link("BrowserPod", "https://browserpod.io"), ". paw runs in your browser.");
    const intro = el("p");
    this.intro = intro;
    intro.textContent =
      `Press ${this.start.textContent} to run paw in this page. Your browser then loads BrowserPod from browserpod.io, and paw from this site.`;
    box.append(intro, this.start, this.status, this.screen, credit);
    panel.append(box);
    this.start.addEventListener("click", () => this.run(() => this.boot()));
    new ResizeObserver(() => this.fit()).observe(panel);
  }

  say(text) {
    this.status.textContent = text;
  }

  /** Run one action after the others, and say what went wrong. */
  run(action) {
    this.queue = this.queue.then(action).catch((err) => this.say(`paw stopped: ${err.message}`));
    return this.queue;
  }

  /** Boot the pod and open the panel's state. Starts from a click. */
  async boot() {
    if (this.pod) return;
    this.start.disabled = true;
    try {
      if (!(await fetch(new URL("manifest.json", here), { method: "HEAD" })).ok) {
        throw new Error("paw for the browser is not on this copy of the pages. Install paw to do the steps.");
      }
      if (!self.crossOriginIsolated) {
        await this.isolate();
        return;
      }
      this.say("Starting the pod...");
      const { PawPod } = await import(new URL("paw-pod.js", here));
      this.pod = await PawPod.boot({ element: this.screen, base: here.href });
      window.pawPod = this.pod;
      this.fit();
      // A click is the gesture that lets a page play sound. After the
      // reload for isolation, the next click starts it (see `sound`).
      if (!window.AudioContext || !window.AudioWorkletNode) this.silent = true;
      else if (navigator.userActivation?.isActive !== false) await this.pod.audio.start();
      await this.open(this.panel.dataset.pawState || '{"project":"demo-song"}');
      // paw shows now: the terminal takes the room of the button and its text.
      this.start.hidden = this.intro.hidden = true;
    } catch (err) {
      this.start.disabled = false;
      throw err;
    }
  }

  /**
   * Make the page cross-origin isolated, as BrowserPod needs: a service
   * worker adds the headers, and the page loads once more through it.
   * The reload remembers the press, and the panel starts by itself.
   */
  async isolate() {
    if (sessionStorage.getItem(RELOAD_KEY)) {
      sessionStorage.removeItem(RELOAD_KEY);
      throw new Error("this browser does not isolate the page, and BrowserPod needs it. Try Chromium.");
    }
    if (!("serviceWorker" in navigator) || !window.isSecureContext) {
      throw new Error("this browser cannot isolate the page, and BrowserPod needs it. Try Chromium.");
    }
    this.say("Preparing the page...");
    const worker = new URL(this.panel.dataset.pawWorker || "coi-sw.js", this.panel.dataset.pawWorker ? location.href : here);
    await navigator.serviceWorker.register(worker);
    await navigator.serviceWorker.ready;
    sessionStorage.setItem(START_KEY, "1");
    sessionStorage.setItem(RELOAD_KEY, "1");
    location.reload();
  }

  /** Open paw at a state (JSON text), unless it shows that state already. */
  async open(state, again = false) {
    if (!again && this.state === state && this.pod.process) return;
    this.say("Opening...");
    // The paw that quits for the new state is not a paw that quit by itself.
    this.state = null;
    await this.pod.open(JSON.parse(state));
    this.state = state;
    this.say(`paw ${this.pod.manifest.version} runs here. Click it to type in it.`);
    if (this.silent) this.say(`${this.status.textContent} Your browser can't play sound from this page, so paw is silent.`);
    const running = this.pod.process;
    this.pod.exited?.then(() => {
      // paw quit by itself (`:q`): no other state opened since.
      if (this.pod.process === null && this.state === state && running) {
        this.state = null;
        this.say("paw has quit. Press a button to start it again.");
      }
    });
  }

  /** Type keys: a key string, or a list of key strings and waits in ms. */
  async type(keys) {
    const list = keys.trim().startsWith("[") ? JSON.parse(keys) : [keys];
    for (const item of list) {
      if (typeof item === "number") await new Promise((r) => setTimeout(r, item));
      else await this.pod.sendKeys(item);
    }
  }

  /** Start the sound from a click, if the boot could not. */
  async sound() {
    if (this.pod && !this.silent) await this.pod.audio.start();
  }

  /** Scale the terminal to the width of the panel, never above its own size. */
  fit() {
    const host = this.screen.firstElementChild;
    if (!host) return;
    host.style.transform = "";
    const scale = Math.min(1, this.screen.clientWidth / host.offsetWidth);
    host.style.transform = scale < 1 ? `scale(${scale})` : "";
    this.screen.style.height = `${Math.ceil(host.offsetHeight * scale)}px`;
  }

  /** A button in the text: before Start, it shows the reader the Start button. */
  wire(target) {
    const keys = target.dataset.pawKeys;
    const label = target.dataset.pawLabel || (keys !== undefined ? "Type it" : "Open in paw");
    const b = button(label, "paw-live-button");
    if (keys !== undefined) b.title = `Types ${keysText(keys)} into paw`;
    target.replaceChildren(b);
    b.addEventListener("click", () => {
      if (!this.pod) {
        this.panel.scrollIntoView({ behavior: "smooth", block: "nearest" });
        this.start.classList.remove("paw-live-attention");
        void this.start.offsetWidth;
        this.start.classList.add("paw-live-attention");
        this.start.focus({ preventScroll: true });
        return;
      }
      b.disabled = true;
      this.run(async () => {
        await this.sound();
        const state = target.dataset.pawState ?? target.dataset.pawOpen;
        if (state) await this.open(state, keys === undefined);
        if (keys !== undefined) await this.type(keys);
        this.screen.querySelector("textarea")?.focus({ preventScroll: true });
      }).finally(() => (b.disabled = false));
    });
  }
}

/** The keys of a data-paw-keys value, for a tooltip. */
function keysText(keys) {
  if (!keys.trim().startsWith("[")) return keys;
  return JSON.parse(keys)
    .filter((item) => typeof item === "string")
    .join(" ");
}

function el(tag, className) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  return node;
}

function button(text, className) {
  const b = el("button", className);
  b.type = "button";
  b.textContent = text;
  return b;
}

function link(text, href) {
  const a = el("a");
  a.href = href;
  a.textContent = text;
  return a;
}

const panel = document.querySelector("[data-paw-live]");
if (panel) {
  const style = el("style");
  style.textContent = STYLE;
  document.head.append(style);
  const live = new Live(panel);
  for (const target of document.querySelectorAll("[data-paw-open], [data-paw-keys]")) live.wire(target);
  if (sessionStorage.getItem(START_KEY)) {
    // The reader pressed Start before the reload for isolation.
    sessionStorage.removeItem(START_KEY);
    // The terminal draws only while it shows: bring the panel back into view.
    panel.scrollIntoView({ block: "start" });
    live.run(() => live.boot());
  }
  if (self.crossOriginIsolated) sessionStorage.removeItem(RELOAD_KEY);
}
