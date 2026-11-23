// The test of the website's live parts in headless Chromium
// (web/browserpod/test.sh SITE OUT --site).
//
//   node test-site.mjs URL OUT.json
//
// URL is the top of the website with the pod (index.html). The test checks
// the landing page: the recorded session plays and lists the keys of its
// steps; nothing loads from BrowserPod's servers before "Try paw"; the
// credit and the note on what loads; then "Try paw" runs the demo song,
// and "Play or stop the song" plays it, so that sound reaches the
// AudioWorklet. Then two how-to guides: one opens the demo song at its
// button, and one, in a browser with no Web Audio, opens an empty project
// and says that paw is silent. OUT gets each check and the screens;
// screenshots go beside it. The exit code is the number of failed checks.
import puppeteer from "puppeteer-core";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const [url, outPath] = process.argv.slice(2);
const site = url.replace(/[^/]*$/, "");
const shots = path.dirname(outPath);
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "paw-site-test-"));
const result = { checks: [], screens: {}, console: [], shots: [] };
let failed = 0;
const check = (name, ok, detail = "") => {
  result.checks.push({ name, ok: !!ok, detail });
  if (!ok) failed += 1;
  console.log(`${ok ? "ok  " : "FAIL"} ${name}${detail ? ": " + detail : ""}`);
};
const pause = (ms) => new Promise((r) => setTimeout(r, ms));

const browser = await puppeteer.launch({
  executablePath: process.env.CHROMIUM,
  headless: true,
  userDataDir: path.join(scratch, "profile"),
  env: { ...process.env, HOME: scratch },
  args: ["--no-first-run", "--no-default-browser-check", "--mute-audio", "--autoplay-policy=no-user-gesture-required"],
  protocolTimeout: 300000,
});

/** A new page that logs its console and its requests. */
async function open(name, { noAudio = false } = {}) {
  const page = await browser.newPage();
  await page.setViewport({ width: 1400, height: 1000 });
  page.requests = [];
  page.on("console", (m) => result.console.push(`${name} ${m.type()}: ${m.text().slice(0, 300)}`));
  page.on("pageerror", (e) => result.console.push(`${name} pageerror: ${String(e).slice(0, 300)}`));
  page.on("request", (r) => page.requests.push(r.url()));
  if (noAudio) {
    await page.evaluateOnNewDocument(() => {
      delete window.AudioContext;
      delete window.AudioWorkletNode;
    });
  }
  return page;
}

const shot = async (page, name, selector) => {
  const file = path.join(shots, `site-${name}.png`);
  const element = selector && (await page.$(selector));
  if (element) await element.screenshot({ path: file });
  else await page.screenshot({ path: file });
  result.shots.push(file);
};

/**
 * Press the panel's Start button, and wait until paw runs. A page that is
 * not isolated loads once more first (coi-sw.js), and paw starts by itself.
 */
async function start(page, label) {
  const [button] = await page.$$(`xpath/.//button[normalize-space()="${label}"]`);
  if (!button) throw new Error(`no button "${label}"`);
  await button.click();
  const until = Date.now() + 240000;
  for (;;) {
    try {
      const status = await page.$eval(".paw-live-status", (e) => e.textContent);
      if (/runs here|stopped|could not|cannot|does not/.test(status)) return status;
    } catch {
      // The page loads again for isolation.
    }
    if (Date.now() > until) throw new Error("paw did not start");
    await pause(250);
  }
}

const screen = (page) => page.evaluate(() => window.pawPod.screen());

try {
  // The landing page, before any press.
  const landing = await open("landing");
  await landing.goto(url, { waitUntil: "load" });
  await landing.waitForSelector(".paw-cast-steps li", { timeout: 30000 });
  await pause(1000);
  const early = landing.requests.filter((u) => /browserpod\.io/.test(u));
  check("nothing loads from BrowserPod before Try paw", early.length === 0, early.join(" "));
  const panel = await landing.$eval(".paw-live-panel", (e) => e.textContent);
  check("the landing page has a Try paw button", /Try paw/.test(panel));
  check("the panel says what loads from where", /browserpod\.io/.test(panel) && /this site/.test(panel), panel.slice(0, 200));
  const credit = await landing.$$eval(".paw-live-panel a", (as) => as.some((a) => a.href.startsWith("https://browserpod.io") && /BrowserPod/.test(a.textContent)));
  check("the panel credits BrowserPod", credit);

  // The recorded session: its steps with their keys, and a step's screen.
  const steps = await landing.$$eval(".paw-cast-steps li", (items) => items.map((i) => i.textContent));
  check("the recorded session lists its steps with their keys", steps.length >= 5 && steps.some((s) => s.includes("4Gwvicy0P")), steps.join(" | "));
  await landing.click(".paw-cast-steps li:nth-child(4)");
  await pause(300);
  const castScreen = await landing.$eval(".paw-cast-screen", (e) => e.textContent);
  const caption = await landing.$eval(".paw-cast-caption", (e) => e.textContent);
  check("a step of the recorded session shows its screen and caption", /NORMAL/.test(castScreen) && caption.length > 0 && steps[3].startsWith(caption), caption);
  await landing.click(".paw-cast-controls button");
  await pause(1500);
  await landing.click(".paw-cast-controls button");
  const played = await landing.$eval(".paw-cast-controls input", (e) => parseFloat(e.value));
  check("Play moves the recorded session on", played > 1, String(played));
  await shot(landing, "cast", "paw-cast");

  // Try paw: the demo song, and its sound.
  const status = await start(landing, "Try paw");
  check("Try paw runs paw in the page", /runs here/.test(status), status);
  const song = await screen(landing);
  result.screens.landing = song;
  check("paw shows the demo song", song.join("\n").includes("Drums"));
  const [play] = await landing.$$(`xpath/.//button[normalize-space()="Play or stop the song"]`);
  await play.click();
  await pause(3000);
  const sound = await landing.evaluate(() => window.pawPod.audio.stats());
  await play.click();
  result.sound = sound;
  check("Play or stop the song plays the song in the page", sound.played > 48000 && sound.peak > 0.01, JSON.stringify(sound));
  await shot(landing, "landing-live", ".paw-live");
  await landing.close();

  // A how-to guide: its button opens the demo song.
  const guide = await open("edit-notes");
  await guide.goto(`${site}docs/how-to/edit-notes.html`, { waitUntil: "load" });
  const guideStatus = await start(guide, "Try the steps in your browser");
  const guideScreen = await screen(guide);
  result.screens["edit-notes"] = guideScreen;
  check("a how-to guide opens paw at its state", /runs here/.test(guideStatus) && guideScreen.join("\n").includes("Drums"), guideStatus);
  await guide.evaluate(() => window.pawPod.sendKeys("4G5|<CR>"));
  await pause(1500);
  const roll = await screen(guide);
  result.screens["edit-notes-pianoroll"] = roll;
  check("the guide's first step opens the piano roll", /pianoroll/.test(roll.join("\n")), roll[28]);
  await shot(guide, "guide-edit-notes", ".paw-live");
  await guide.close();

  // A browser with no Web Audio: the empty project, and a silent paw.
  const silent = await open("start-paw", { noAudio: true });
  await silent.goto(`${site}docs/how-to/start-paw-and-hear-sound.html`, { waitUntil: "load" });
  const silentStatus = await start(silent, "Try the steps in your browser");
  const empty = await screen(silent);
  result.screens["start-paw"] = empty;
  check("with no Web Audio, the page says that paw is silent", /silent/.test(silentStatus), silentStatus);
  check("the state empty opens a project with no parts", /NORMAL/.test(empty.join("\n")) && !empty.join("\n").includes("Drums"));
  await shot(silent, "guide-silent", ".paw-live");
  await silent.close();
} catch (err) {
  check("the test ran to its end", false, String((err && err.stack) || err));
} finally {
  result.failed = failed;
  fs.writeFileSync(outPath, JSON.stringify(result, null, 1));
  await browser.close();
  fs.rmSync(scratch, { recursive: true, force: true });
}
process.exit(failed);
