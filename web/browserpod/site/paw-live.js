// <paw-live>: a live paw in a page of the docs, behind a button.
//
// The one component that the pages use to embed the pod: the landing page,
// the how-to guides and the course. It shows a note on what loads, a
// button, the terminal and the "Powered by BrowserPod" credit. Nothing of
// BrowserPod loads before the button is pressed.
//
//   <script type="module" src="pod/paw-live.js"></script>
//   <paw-live state='{"project":"demo-song","scope":"Melody"}'
//             label="Try the steps in your browser"
//             show='[{"label":"Play or stop","keys":"<Space><Space>"}]'
//             sw="coi-sw.js">
//     Text for a browser with no script, or a copy of the site with no pod.
//   </paw-live>
//
// Attributes, all optional:
//   state  the state that paw opens at (`PawPod.open`), JSON; the demo song by default.
//   label  the text of the button.
//   show   buttons that type keys into paw ("show me"), JSON: [{ label, keys }].
//   sw     the URL of coi-sw.js, for a page that is not cross-origin isolated.
//          It must be at the top of the site, so that its scope holds the page.
//
// Any element of the page with `data-paw-keys` (keys in Vim notation) or
// `data-paw-state` (JSON) drives the first <paw-live> of the page when it
// is clicked: it starts paw first if it does not run. A page has one
// <paw-live>, because each one is a pod of its own.
//
// The element fires `paw-live-ready` (detail: { pod }) when paw runs, and
// keeps the PawPod in its `pod` property. web/browserpod/README.md has the
// rest.
import { PawPod } from "./paw-pod.js";

const RESUME_KEY = "paw-live-start";
const STYLE_ID = "paw-live-style";

const TEXT = {
  note:
    "You can run paw in this page. When you press the button, your browser loads BrowserPod " +
    "(about 6 MB) from browserpod.io and paw (about 26 MB) from this site, and nothing loads " +
    "before you press it. paw runs inside your browser, so the keys that you type stay on your computer.",
  label: "Try paw in your browser",
  loading: "Loading BrowserPod and paw...",
  reloading: "The page loads again once, so that paw can start.",
  running: "paw is running. Click the terminal to type in it.",
  audioWaits: "Click the terminal to hear the sound.",
  silent: "Your browser can't play sound from this page, so paw is silent.",
  stopped: "paw stopped. Press Start again to run it once more.",
  again: "Start again",
  isolated:
    "paw can't run in this browser, because the browser doesn't give this page the shared memory " +
    "that paw needs. Install paw to try it.",
  failed: "paw could not start: ",
};

/** The styles of the element, once for each page. They follow the colours of mdBook's theme. */
function addStyle() {
  if (document.getElementById(STYLE_ID)) return;
  const style = document.createElement("style");
  style.id = STYLE_ID;
  style.textContent = `
paw-live { display: block; margin: 1em 0; }
.paw-live { padding: 0.25em 1em; border: 1px solid var(--table-border-color, #8888); border-radius: 6px; }
.paw-live-actions button { font: inherit; margin: 0 0.5em 0.5em 0; padding: 0.4em 0.9em; border-radius: 6px;
  border: 1px solid var(--links, #0645ad); background: transparent; color: var(--fg, inherit); cursor: pointer; }
.paw-live-actions button.paw-live-start { background: var(--links, #0645ad); color: var(--bg, #fff); }
.paw-live-actions button:disabled { opacity: 0.5; cursor: default; }
.paw-live-status:empty { display: none; }
.paw-live-terminal { background: #000; overflow-x: auto; max-width: 100%; }
.paw-live-terminal:empty { display: none; }
.paw-live-credit { font-size: 0.9em; }
`;
  document.head.append(style);
}

/** Parse a JSON attribute; a wrong one is an error on the page's console, and the default. */
function jsonAttribute(element, name, fallback) {
  const text = element.getAttribute(name);
  if (!text) return fallback;
  try {
    return JSON.parse(text);
  } catch (err) {
    console.error(`<paw-live ${name}>: ${err.message}`);
    return fallback;
  }
}

function button(text, className = "") {
  const b = document.createElement("button");
  b.type = "button";
  b.textContent = text;
  if (className) b.className = className;
  return b;
}

class PawLive extends HTMLElement {
  /** The PawPod when paw runs, else null. */
  pod = null;
  /** The promise of a start that runs, so that two clicks start one pod. */
  #starting = null;

  connectedCallback() {
    if (this.ui) return;
    addStyle();
    this.state = jsonAttribute(this, "state", { project: "demo-song" });
    const show = jsonAttribute(this, "show", []);

    this.ui = document.createElement("div");
    this.ui.className = "paw-live";
    const note = document.createElement("p");
    note.className = "paw-live-note";
    note.textContent = TEXT.note;
    const actions = document.createElement("p");
    actions.className = "paw-live-actions";
    this.startButton = button(this.getAttribute("label") || TEXT.label, "paw-live-start");
    this.startButton.addEventListener("click", () => this.start().catch(() => {}));
    this.showButtons = show.map(({ label, keys }) => {
      const b = button(label);
      b.disabled = true;
      b.dataset.pawKeys = keys;
      return b;
    });
    // "Start again" opens the state again, without the changes.
    this.againButton = button(TEXT.again);
    this.againButton.hidden = true;
    this.againButton.addEventListener("click", () => this.#run(() => this.pod.open(this.state)));
    actions.append(this.startButton, ...this.showButtons, this.againButton);
    this.status = document.createElement("p");
    this.status.className = "paw-live-status";
    this.status.setAttribute("role", "status");
    this.terminal = document.createElement("div");
    this.terminal.className = "paw-live-terminal";
    const credit = document.createElement("p");
    credit.className = "paw-live-credit";
    const link = document.createElement("a");
    link.href = "https://browserpod.io";
    link.textContent = "BrowserPod";
    credit.append("Powered by ", link, ".");
    this.ui.append(note, actions, this.status, this.terminal, credit);
    // The text inside the element is for a page with no script: the
    // element shows its own parts instead.
    this.replaceChildren(this.ui);

    // A press before the reload that made the page isolated starts paw now.
    if (this.#resumeAsked()) {
      this.scrollIntoView({ block: "center" });
      this.start().catch(() => {});
    }
  }

  #say(text) {
    this.status.textContent = text;
  }

  /** The index of this element among the <paw-live> of the page, for the resume after a reload. */
  #where() {
    return `${location.pathname}#${[...document.querySelectorAll("paw-live")].indexOf(this)}`;
  }

  #resumeAsked() {
    let asked = false;
    try {
      asked = sessionStorage.getItem(RESUME_KEY) === this.#where();
      if (asked) sessionStorage.removeItem(RESUME_KEY);
    } catch {
      // No session storage (a private window, for example): no resume.
    }
    return asked;
  }

  /**
   * Start paw at the element's state. Resolves with the PawPod, or
   * rejects after the element says why. A page that is not cross-origin
   * isolated gets the service worker of coi-sw.js and loads again once;
   * paw then starts by itself.
   */
  start() {
    if (this.pod) return Promise.resolve(this.pod);
    if (!this.#starting) this.#starting = this.#start().finally(() => (this.#starting = null));
    return this.#starting;
  }

  async #start() {
    this.startButton.disabled = true;
    try {
      if (!self.crossOriginIsolated) {
        await this.#isolate();
        // The page loads again: nothing more to do in this one.
        return new Promise(() => {});
      }
      this.#say(TEXT.loading);
      const pod = await PawPod.boot({ element: this.terminal });
      const sound = await this.#startAudio(pod);
      await pod.open(this.state);
      this.pod = pod;
      this.#watch();
      this.running = { true: TEXT.running, waits: `${TEXT.running} ${TEXT.audioWaits}`, false: `${TEXT.running} ${TEXT.silent}` }[sound];
      this.#say(this.running);
      this.showButtons.forEach((b) => (b.disabled = false));
      this.startButton.hidden = true;
      this.againButton.hidden = false;
      this.dispatchEvent(new CustomEvent("paw-live-ready", { bubbles: true, detail: { pod } }));
      return pod;
    } catch (err) {
      this.#say(err.isolation ? TEXT.isolated : TEXT.failed + err.message);
      this.startButton.disabled = !!err.isolation;
      throw err;
    }
  }

  /**
   * Register coi-sw.js, and load the page again through it, once. A
   * browser that does not isolate the page after that gets a message, not
   * a loop.
   */
  async #isolate() {
    const sw = this.getAttribute("sw") || new URL("coi-sw.js", import.meta.url).href;
    const fail = () => Object.assign(new Error("not cross-origin isolated"), { isolation: true });
    if (!("serviceWorker" in navigator) || !window.isSecureContext || navigator.serviceWorker.controller) throw fail();
    try {
      sessionStorage.setItem(RESUME_KEY, this.#where());
    } catch {
      throw fail();
    }
    this.#say(TEXT.reloading);
    await navigator.serviceWorker.register(sw);
    await navigator.serviceWorker.ready;
    location.reload();
  }

  /**
   * Play paw's sound in the page. Returns true when it plays, "waits"
   * when the browser waits for a click (after the reload, the press is
   * no longer a gesture of this page), and false when the browser has no
   * Web Audio.
   */
  async #startAudio(pod) {
    if (!window.AudioContext || !window.AudioWorkletNode) return false;
    try {
      const started = pod.audio.start();
      const late = new Promise((resolve) => setTimeout(() => resolve("late"), 1000));
      if ((await Promise.race([started, late])) !== "late") return true;
    } catch {
      return false;
    }
    const resume = () => pod.audio.start().catch(() => {});
    this.terminal.addEventListener("pointerdown", resume, { once: true });
    return "waits";
  }

  /**
   * Say when paw quits (`:q`). `open` quits paw too and starts it again
   * at once: the check waits for that, so that only a paw that stays
   * stopped is reported.
   */
  #watch() {
    this.pod.exited.then(() =>
      setTimeout(() => {
        if (!this.pod.process) this.#say(TEXT.stopped);
      }, 0),
    );
  }

  /** Run an action on the running pod; a failure goes to the status line. */
  async #run(action) {
    try {
      await action();
      this.#watch();
      this.#say(this.running);
    } catch (err) {
      this.#say(TEXT.failed + err.message);
    }
  }

  /** What a `data-paw-keys` or `data-paw-state` element asks: start if needed, then do it. */
  async drive({ keys, state }) {
    const pod = await this.start();
    if (state) await this.#run(() => pod.open(state));
    if (keys) {
      // A paw that quit starts again at the element's state first.
      if (!pod.process) await this.#run(() => pod.open(this.state));
      await pod.sendKeys(keys);
    }
  }
}

customElements.define("paw-live", PawLive);

// The "show me" elements of the page: buttons of a <paw-live>, or any
// element with data-paw-keys or data-paw-state.
document.addEventListener("click", (event) => {
  const target = event.target.closest?.("[data-paw-keys], [data-paw-state]");
  const live = document.querySelector("paw-live");
  if (!target || !live) return;
  const keys = target.dataset.pawKeys;
  const state = target.dataset.pawState ? JSON.parse(target.dataset.pawState) : null;
  live.drive({ keys, state }).catch(() => {});
});
