// <paw-cast>: a recorded terminal session of paw, on a page of the website.
//
//   <paw-cast src="docs/images/cast-basics.cast">Text for a page with no script.</paw-cast>
//
// The file is an asciicast of version 2, made by docs/images/make/cast.py:
// "o" events are what paw wrote, "i" events the keys typed, and "m" events
// (markers) the captions of the steps. The element shows the screen, a
// button to play or pause, a bar to move in time, and the steps with
// their keys as text that the reader can copy. A click on a step goes to
// its start. The terminal is a small emulator of the sequences that paw
// writes: cursor moves, erases and colours. Everything else is skipped.

const STYLE_ID = "paw-cast-style";

// The colours of the terminal the pictures are taken in (Catppuccin Mocha,
// docs/images/make/wezterm.lua): the default pen, and the 16 colours.
const FG = "#cdd6f4";
const BG = "#1e1e2e";
const ANSI = [
  "#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#bac2de",
  "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8",
];

/** The colour of index `n` of the 256 of xterm. */
function indexed(n) {
  if (n < 16) return ANSI[n];
  if (n < 232) {
    const level = (v) => (v === 0 ? 0 : 55 + v * 40);
    const i = n - 16;
    return `rgb(${level(Math.floor(i / 36))},${level(Math.floor(i / 6) % 6)},${level(i % 6)})`;
  }
  const grey = 8 + (n - 232) * 10;
  return `rgb(${grey},${grey},${grey})`;
}

/** True for a character that takes two cells (East Asian wide, emoji). */
function wide(code) {
  return (
    (code >= 0x1100 && code <= 0x115f) ||
    (code >= 0x2e80 && code <= 0xa4cf) ||
    (code >= 0xac00 && code <= 0xd7a3) ||
    (code >= 0xf900 && code <= 0xfaff) ||
    (code >= 0xfe30 && code <= 0xfe4f) ||
    (code >= 0xff00 && code <= 0xff60) ||
    (code >= 0xffe0 && code <= 0xffe6) ||
    (code >= 0x1f300 && code <= 0x1faff) ||
    (code >= 0x20000 && code <= 0x3fffd)
  );
}

const BOLD = 1, DIM = 2, ITALIC = 4, UNDERLINE = 8, REVERSE = 16, STRIKE = 32;
const SGR_ON = { 1: BOLD, 2: DIM, 3: ITALIC, 4: UNDERLINE, 7: REVERSE, 9: STRIKE };
const SGR_OFF = { 22: BOLD | DIM, 23: ITALIC, 24: UNDERLINE, 27: REVERSE, 29: STRIKE };

/** A screen of cells that reads the output of paw. */
export class Screen {
  constructor(cols, rows) {
    this.cols = cols;
    this.rows = rows;
    this.pen = { fg: null, bg: null, attrs: 0 };
    this.cells = Array.from({ length: rows }, () => this.#blankRow());
    this.x = 0;
    this.y = 0;
    this.state = "ground";
    this.seq = "";
  }

  #blank() {
    return { ch: " ", fg: this.pen.fg, bg: this.pen.bg, attrs: 0 };
  }

  #blankRow() {
    return Array.from({ length: this.cols }, () => ({ ch: " ", fg: null, bg: null, attrs: 0 }));
  }

  feed(text) {
    for (const ch of text) {
      switch (this.state) {
        case "ground":
          this.#ground(ch);
          break;
        case "esc":
          // CSI, a string (OSC, APC, DCS, PM, SOS), or a two-byte sequence.
          if (ch === "[") (this.state = "csi"), (this.seq = "");
          else if ("]_PX^".includes(ch)) this.state = "string";
          else this.state = "ground";
          break;
        case "csi":
          if (ch >= "@" && ch <= "~") {
            this.#csi(this.seq, ch);
            this.state = "ground";
          } else this.seq += ch;
          break;
        case "string":
          // A string ends with BEL, or with ESC \ (ST).
          if (ch === "\x07") this.state = "ground";
          else if (ch === "\x1b") this.state = "string-esc";
          break;
        case "string-esc":
          this.state = ch === "\\" ? "ground" : "string";
          break;
      }
    }
  }

  #ground(ch) {
    if (ch === "\x1b") this.state = "esc";
    else if (ch === "\r") this.x = 0;
    else if (ch === "\n") this.#lineFeed();
    else if (ch === "\b") this.x = Math.max(0, this.x - 1);
    else if (ch === "\t") this.x = Math.min(this.cols - 1, (Math.floor(this.x / 8) + 1) * 8);
    else if (ch >= " ") this.#put(ch);
  }

  #lineFeed() {
    if (this.y === this.rows - 1) {
      this.cells.shift();
      this.cells.push(this.#blankRow());
    } else this.y += 1;
  }

  #put(ch) {
    const width = wide(ch.codePointAt(0)) ? 2 : 1;
    if (this.x + width > this.cols) {
      this.x = 0;
      this.#lineFeed();
    }
    const row = this.cells[this.y];
    row[this.x] = { ch, fg: this.pen.fg, bg: this.pen.bg, attrs: this.pen.attrs };
    // The second cell of a wide character draws nothing.
    if (width === 2) row[this.x + 1] = { ch: "", fg: this.pen.fg, bg: this.pen.bg, attrs: this.pen.attrs };
    this.x += width;
  }

  #erase(y, from, to) {
    for (let x = from; x < to; x++) this.cells[y][x] = this.#blank();
  }

  #csi(seq, final) {
    // Private sequences (modes, queries) change nothing that shows.
    if (/^[?>=<]/.test(seq) || /[$ ]/.test(seq)) return;
    const params = seq.split(";").map((p) => (p === "" ? 0 : parseInt(p, 10)));
    const n = Math.max(1, params[0] || 0);
    const clampX = (x) => Math.max(0, Math.min(this.cols - 1, x));
    const clampY = (y) => Math.max(0, Math.min(this.rows - 1, y));
    switch (final) {
      case "H":
      case "f":
        this.y = clampY((params[0] || 1) - 1);
        this.x = clampX((params[1] || 1) - 1);
        break;
      case "A": this.y = clampY(this.y - n); break;
      case "B": this.y = clampY(this.y + n); break;
      case "C": this.x = clampX(this.x + n); break;
      case "D": this.x = clampX(this.x - n); break;
      case "G": this.x = clampX(n - 1); break;
      case "d": this.y = clampY(n - 1); break;
      case "X": this.#erase(this.y, this.x, Math.min(this.cols, this.x + n)); break;
      case "K": {
        const mode = params[0] || 0;
        this.#erase(this.y, mode === 0 ? this.x : 0, mode === 1 ? this.x + 1 : this.cols);
        break;
      }
      case "J": {
        const mode = params[0] || 0;
        if (mode === 0) {
          this.#erase(this.y, this.x, this.cols);
          for (let y = this.y + 1; y < this.rows; y++) this.#erase(y, 0, this.cols);
        } else if (mode === 1) {
          for (let y = 0; y < this.y; y++) this.#erase(y, 0, this.cols);
          this.#erase(this.y, 0, this.x + 1);
        } else for (let y = 0; y < this.rows; y++) this.#erase(y, 0, this.cols);
        break;
      }
      case "m":
        this.#sgr(params);
        break;
    }
  }

  #sgr(params) {
    for (let i = 0; i < params.length; i++) {
      const p = params[i];
      if (p === 0) this.pen = { fg: null, bg: null, attrs: 0 };
      else if (SGR_ON[p]) this.pen.attrs |= SGR_ON[p];
      else if (SGR_OFF[p]) this.pen.attrs &= ~SGR_OFF[p];
      else if (p >= 30 && p <= 37) this.pen.fg = ANSI[p - 30];
      else if (p >= 90 && p <= 97) this.pen.fg = ANSI[p - 90 + 8];
      else if (p >= 40 && p <= 47) this.pen.bg = ANSI[p - 40];
      else if (p >= 100 && p <= 107) this.pen.bg = ANSI[p - 100 + 8];
      else if (p === 39) this.pen.fg = null;
      else if (p === 49) this.pen.bg = null;
      else if (p === 38 || p === 48) {
        // 38;5;n or 38;2;r;g;b, and the same with 48 for the background.
        let colour = null;
        if (params[i + 1] === 5) {
          colour = indexed(params[i + 2] || 0);
          i += 2;
        } else if (params[i + 1] === 2) {
          colour = `rgb(${params[i + 2] || 0},${params[i + 3] || 0},${params[i + 4] || 0})`;
          i += 4;
        }
        if (p === 38) this.pen.fg = colour;
        else this.pen.bg = colour;
      }
    }
  }

  /** The screen as HTML: one line for each row, a span for each run of one style. */
  html() {
    const escape = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    const style = (c) => {
      let fg = c.fg || FG;
      let bg = c.bg || BG;
      if (c.attrs & REVERSE) [fg, bg] = [bg, fg];
      let css = `color:${fg};background:${bg}`;
      if (c.attrs & BOLD) css += ";font-weight:bold";
      if (c.attrs & DIM) css += ";opacity:0.6";
      if (c.attrs & ITALIC) css += ";font-style:italic";
      const lines = [c.attrs & UNDERLINE ? "underline" : "", c.attrs & STRIKE ? "line-through" : ""].filter(Boolean);
      if (lines.length) css += `;text-decoration:${lines.join(" ")}`;
      return css;
    };
    return this.cells
      .map((row) => {
        let out = "";
        let run = "";
        let runStyle = null;
        for (const cell of row) {
          const s = style(cell);
          if (s !== runStyle) {
            if (run) out += `<span style="${runStyle}">${escape(run)}</span>`;
            run = "";
            runStyle = s;
          }
          run += cell.ch;
        }
        if (run) out += `<span style="${runStyle}">${escape(run)}</span>`;
        return out;
      })
      .join("\n");
  }
}

/** Keys as bytes back into Vim notation, for the list of steps. */
const NOTATION = {
  "\x1b": "<Esc>", "\r": "<CR>", " ": "<Space>", "\t": "<Tab>", "\x7f": "<BS>", "<": "<lt>",
  "\x1b[A": "<Up>", "\x1b[B": "<Down>", "\x1b[C": "<Right>", "\x1b[D": "<Left>",
};
function notation(key) {
  if (NOTATION[key]) return NOTATION[key];
  const code = key.charCodeAt(0);
  if (key.length === 1 && code < 0x20) return `<C-${String.fromCharCode(code + 0x60)}>`;
  if (key.length === 2 && key[0] === "\x1b") return `<A-${key[1]}>`;
  return key;
}

/** Parse an asciicast of version 2: the header, the output, and the steps with their keys. */
export function parseCast(text) {
  const lines = text.split("\n").filter((l) => l.trim());
  const header = JSON.parse(lines[0]);
  const output = [];
  const steps = [];
  for (const line of lines.slice(1)) {
    const [time, kind, data] = JSON.parse(line);
    if (kind === "o") output.push({ time, data });
    else if (kind === "m") steps.push({ time, caption: data, keys: "" });
    else if (kind === "i" && steps.length) steps.at(-1).keys += notation(data);
  }
  const end = Math.max(output.at(-1)?.time ?? 0, steps.at(-1)?.time ?? 0) + 1.5;
  return { header, output, steps, end };
}

function addStyle() {
  if (document.getElementById(STYLE_ID)) return;
  const style = document.createElement("style");
  style.id = STYLE_ID;
  style.textContent = `
paw-cast { display: block; margin: 1em 0; }
.paw-cast-screen { margin: 0; padding: 0.5em; overflow-x: auto; background: ${BG}; color: ${FG};
  font-family: "Fira Code", "DejaVu Sans Mono", monospace; font-size: 12px; line-height: 1.2; border-radius: 6px; }
.paw-cast-caption { font-weight: bold; min-height: 1.5em; margin: 0.5em 0; }
.paw-cast-controls { display: flex; gap: 0.75em; align-items: center; }
.paw-cast-controls input { flex: 1; }
.paw-cast-controls button { font: inherit; padding: 0.3em 0.9em; border-radius: 6px;
  border: 1px solid var(--links, #0645ad); background: transparent; color: var(--fg, inherit); cursor: pointer; }
.paw-cast-steps { margin: 0.5em 0 0; padding-left: 1.5em; }
.paw-cast-steps li { cursor: pointer; }
.paw-cast-steps li.current { font-weight: bold; }
`;
  document.head.append(style);
}

class PawCast extends HTMLElement {
  async connectedCallback() {
    if (this.cast) return;
    addStyle();
    const response = await fetch(this.getAttribute("src"));
    if (!response.ok) return;
    this.cast = parseCast(await response.text());
    this.#build();
    this.#seek(0);
  }

  #build() {
    const { steps, end } = this.cast;
    this.caption = document.createElement("p");
    this.caption.className = "paw-cast-caption";
    this.caption.setAttribute("aria-live", "polite");
    this.screen = document.createElement("pre");
    this.screen.className = "paw-cast-screen";
    this.screen.setAttribute("aria-label", "The screen of paw");
    const controls = document.createElement("p");
    controls.className = "paw-cast-controls";
    this.playButton = document.createElement("button");
    this.playButton.type = "button";
    this.playButton.addEventListener("click", () => (this.playing ? this.#pause() : this.#play()));
    this.bar = document.createElement("input");
    this.bar.type = "range";
    this.bar.min = "0";
    this.bar.max = String(end);
    this.bar.step = "0.05";
    this.bar.setAttribute("aria-label", "Time in the recording");
    this.bar.addEventListener("input", () => {
      this.#pause();
      this.#seek(parseFloat(this.bar.value));
    });
    controls.append(this.playButton, this.bar);
    this.list = document.createElement("ol");
    this.list.className = "paw-cast-steps";
    this.items = steps.map((step) => {
      const item = document.createElement("li");
      item.append(step.caption);
      if (step.keys) {
        const code = document.createElement("code");
        code.textContent = step.keys;
        item.append(": ", code);
      }
      item.addEventListener("click", () => {
        // A click that selects the keys to copy them does not jump.
        if (String(getSelection())) return;
        this.#pause();
        this.#seek(step.time);
      });
      this.list.append(item);
      return item;
    });
    this.replaceChildren(this.caption, this.screen, controls, this.list);
    this.#pause();
  }

  /**
   * Show the screen at `time`. Forward, the screen reads the output that
   * comes after what it read; back, it reads again from the start.
   */
  #seek(time) {
    const { header, output, steps } = this.cast;
    if (!this.terminal || time < this.time) {
      this.terminal = new Screen(header.width, header.height);
      this.read = 0;
      this.drawn = -1;
    }
    while (this.read < output.length && output[this.read].time <= time) {
      this.terminal.feed(output[this.read].data);
      this.read += 1;
    }
    if (this.drawn !== this.read) {
      this.screen.innerHTML = this.terminal.html();
      this.drawn = this.read;
    }
    this.time = time;
    this.bar.value = String(time);
    let current = -1;
    steps.forEach((step, i) => {
      if (step.time <= time) current = i;
    });
    this.caption.textContent = current >= 0 ? steps[current].caption : "";
    this.items.forEach((item, i) => item.classList.toggle("current", i === current));
  }

  #play() {
    if (this.time >= this.cast.end) this.time = 0;
    this.playing = true;
    this.playButton.textContent = "Pause";
    const from = performance.now() - this.time * 1000;
    const tick = () => {
      if (!this.playing) return;
      const time = (performance.now() - from) / 1000;
      if (time >= this.cast.end) {
        this.#seek(this.cast.end);
        this.#pause();
        return;
      }
      this.#seek(time);
      this.frame = requestAnimationFrame(tick);
    };
    tick();
  }

  #pause() {
    this.playing = false;
    cancelAnimationFrame(this.frame);
    this.playButton.textContent = "Play";
  }
}

customElements.define("paw-cast", PawCast);
