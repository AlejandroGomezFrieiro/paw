// The test of the pod image in headless Chromium (web/browserpod/test.sh).
//
//   node test.mjs URL OUT.json
//
// URL is demo.html on a local server. The test clicks Start, then drives
// paw through the JS API of paw-pod.js. It checks: nothing loads from
// BrowserPod's servers before the click; the credit; the terminal is 100
// by 30 cells at two sizes of the window; the demo song, a scope and a
// lesson open; keys in Vim notation arrive, an arrow key too; and the
// sound reaches the AudioWorklet. OUT gets the screens, the times and the
// sound's numbers. The exit code is the number of failed checks.
import puppeteer from "puppeteer-core";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const [url, outPath] = process.argv.slice(2);
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "paw-pod-test-"));
const result = { checks: [], times: {}, screens: {}, console: [], requests: [] };
let failed = 0;
const check = (name, ok, detail = "") => {
  result.checks.push({ name, ok: !!ok, detail });
  if (!ok) failed += 1;
  console.log(`${ok ? "ok  " : "FAIL"} ${name}${detail ? ": " + detail : ""}`);
};

const browser = await puppeteer.launch({
  executablePath: process.env.CHROMIUM,
  headless: true,
  userDataDir: path.join(scratch, "profile"),
  env: { ...process.env, HOME: scratch },
  args: ["--no-first-run", "--no-default-browser-check", "--mute-audio"],
  protocolTimeout: 300000,
});
try {
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 900 });
  page.on("console", (m) => result.console.push(`${m.type()}: ${m.text().slice(0, 300)}`));
  page.on("pageerror", (e) => result.console.push(`pageerror: ${String(e).slice(0, 300)}`));
  page.on("request", (r) => result.requests.push(r.url()));
  const pod = (fn, ...args) => page.evaluate(fn, ...args);
  const screen = () => pod(() => window.pawPod.screen());
  const show = async (name) => (result.screens[name] = await screen());

  await page.goto(url, { waitUntil: "load" });
  await new Promise((r) => setTimeout(r, 1000));
  const early = result.requests.filter((u) => /browserpod\.io/.test(u));
  check("nothing loads from BrowserPod before Start", early.length === 0, early.join(" "));
  const credit = await pod(() => [...document.querySelectorAll("a")].some((a) => a.href.startsWith("https://browserpod.io") && /BrowserPod/.test(a.textContent)));
  check("the page credits BrowserPod", credit);

  // Start: a real click, the gesture that lets the page play sound.
  const t0 = Date.now();
  await page.click("#start");
  await page.waitForFunction(() => /is running|could not start/.test(document.getElementById("status").textContent), { timeout: 180000 });
  result.times.start_to_running_ms = Date.now() - t0;
  const status = await pod(() => document.getElementById("status").textContent);
  check("paw starts in the pod", /is running/.test(status), status);
  if (!/is running/.test(status)) throw new Error(status);
  await show("demo-song");

  const size = await pod(() => window.pawPod.size());
  check("the terminal is 100x30", size.cols === 100 && size.rows === 30, JSON.stringify(size));
  await page.setViewport({ width: 900, height: 600 });
  await new Promise((r) => setTimeout(r, 500));
  const small = await pod(() => window.pawPod.size());
  check("the terminal stays 100x30 in a smaller window", small.cols === 100 && small.rows === 30, JSON.stringify(small));
  await page.setViewport({ width: 1280, height: 900 });
  const rows = await screen();
  check("the demo song is drawn", rows.join("\n").includes("Drums"));
  // paw's status line is the row above the last (the message line).
  check("paw's status line is on row 29 of 30", /NORMAL/.test(rows[28]), rows[28]);

  // Keys: a motion, then an arrow key (an escape sequence).
  // The part under the cursor has a full bar before its name.
  const cursorPart = (r) => (r.find((line) => /^\s*\d*\s*█ \S/.test(line)) || "").replace(/^[\s\d█]*/, "").split(" ")[0];
  await pod(() => window.pawPod.sendKeys("gg"));
  await new Promise((r) => setTimeout(r, 300));
  const top = await show("after-gg");
  await pod(() => window.pawPod.sendKeys("j"));
  await new Promise((r) => setTimeout(r, 300));
  const afterJ = await show("after-j");
  check("gg, then j, moves the cursor to the second part", cursorPart(top) === "Drums" && cursorPart(afterJ) === "Bass", `${cursorPart(top)} ${cursorPart(afterJ)}`);
  await pod(() => window.pawPod.sendKeys("<Up>"));
  await new Promise((r) => setTimeout(r, 300));
  const afterUp = await show("after-up");
  check("<Up> moves the cursor back, as one key", cursorPart(afterUp) === "Drums" && /NORMAL/.test(afterUp[28]), cursorPart(afterUp));

  // Sound: play for three seconds.
  await pod(() => window.pawPod.sendKeys("<Space><Space>"));
  await new Promise((r) => setTimeout(r, 3000));
  const sound = await pod(() => window.pawPod.audio.stats());
  await pod(() => window.pawPod.sendKeys("<Space><Space>"));
  result.sound = sound;
  check("the sound reaches the worklet", sound.played > 48000 && sound.peak > 0.01, JSON.stringify(sound));

  // A scope.
  let t = Date.now();
  await pod(() => window.pawPod.open({ project: "demo-song", scope: "Melody" }));
  result.times.open_scope_ms = Date.now() - t;
  await new Promise((r) => setTimeout(r, 500));
  const scoped = await show("scope-melody");
  check("the scope opens", scoped.join("\n").includes("Melody"), scoped[29]);

  // A lesson.
  t = Date.now();
  await pod(() => window.pawPod.open({ lesson: 1 }));
  result.times.open_lesson_ms = Date.now() - t;
  await new Promise((r) => setTimeout(r, 500));
  const lesson = await show("lesson-1");
  check("lesson 1 opens", /Lesson 1/i.test(lesson.join("\n")));
} catch (err) {
  check("the test ran to its end", false, String(err && err.stack || err));
} finally {
  result.failed = failed;
  fs.writeFileSync(outPath, JSON.stringify(result, null, 1));
  await browser.close();
  fs.rmSync(scratch, { recursive: true, force: true });
}
process.exit(failed);
