// The test of the course page with a live paw, in headless Chromium
// (web/browserpod/test.sh SITE OUT --course).
//
//   node test-course.mjs URL OUT.json
//
// URL is docs/tutorials/course/in-the-browser.html of the website with the
// pod. The test checks: nothing loads from BrowserPod's servers before
// Start, also when a step's button is pressed first; the credit and the
// privacy note; the terminal is 100 by 30 cells; then, for each lesson
// with buttons, the lesson's button opens it in paw, and the "Type it"
// button of each step does the step, so that the tutor goes on to the next
// step. OUT gets each check, the lessons' results, the times and the
// screens; screenshots go beside it. The exit code is the number of
// failed checks.
import puppeteer from "puppeteer-core";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const [url, outPath] = process.argv.slice(2);
const shots = path.dirname(outPath);
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "paw-course-test-"));
const result = { checks: [], lessons: [], times: {}, screens: {}, console: [], shots: [] };
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
const requests = [];
try {
  const page = await browser.newPage();
  await page.setViewport({ width: 1680, height: 1000 });
  page.on("console", (m) => result.console.push(`${m.type()}: ${m.text().slice(0, 300)}`));
  page.on("pageerror", (e) => result.console.push(`pageerror: ${String(e).slice(0, 300)}`));
  page.on("request", (r) => requests.push(r.url()));
  const shot = async (name) => {
    const file = path.join(shots, `course-${name}.png`);
    await page.screenshot({ path: file });
    result.shots.push(file);
  };
  const screen = () => page.evaluate(() => (window.pawPod ? window.pawPod.screen().join("\n") : ""));
  const status = () => page.evaluate(() => document.querySelector(".paw-live-status")?.textContent ?? "");
  const fromBrowserPod = () => requests.filter((u) => /browserpod\.io/.test(u));
  /** Wait until fn() is true, or the time is over; gives the last value. */
  const until = async (fn, ms) => {
    const end = Date.now() + ms;
    let value = await fn();
    while (!value && Date.now() < end) {
      await pause(200);
      value = await fn();
    }
    return value;
  };

  await page.goto(url, { waitUntil: "load" });
  await pause(1000);
  await shot("before-start");
  check("the page has a Start button", await page.$(".paw-live-start"));
  const credit = await page.evaluate(() =>
    [...document.querySelectorAll(".paw-live a")].some((a) => a.href.startsWith("https://browserpod.io") && /BrowserPod/.test(a.textContent)),
  );
  check("the panel credits BrowserPod", credit);
  check("the page says what loads from where", await page.evaluate(() => /loads BrowserPod from browserpod\.io/.test(document.body.textContent)));
  const buttons = await page.$$eval("[data-paw-keys] button", (b) => b.length);
  check("the steps have buttons", buttons > 50, `${buttons} buttons`);

  // A step's button before Start shows the Start button, and loads nothing.
  await page.click("[data-paw-keys] button");
  await pause(800);
  check("a step's button before Start points at Start", await page.$eval(".paw-live-start", (b) => b.classList.contains("paw-live-attention")));
  check("nothing loads from BrowserPod before Start", fromBrowserPod().length === 0, fromBrowserPod().join(" "));

  const t0 = Date.now();
  await page.click(".paw-live-start");
  const started = await until(async () => /runs here|stopped|quit/.test(await status()), 240000);
  result.times.start_to_running_ms = Date.now() - t0;
  check("Start runs paw in the page", started && /runs here/.test(await status()), await status());
  if (!/runs here/.test(await status())) {
    result.screens.start = (await screen()).split("\n");
    await shot("start-failed");
    throw new Error(await status());
  }
  const size = await page.evaluate(() => window.pawPod.size());
  check("the terminal is 100x30", size.cols === 100 && size.rows === 30, JSON.stringify(size));
  const fits = await page.evaluate(() => {
    const panel = document.querySelector(".paw-live-screen").getBoundingClientRect();
    const text = document.querySelector(".paw-course-text").getBoundingClientRect();
    return { side: panel.left > text.right - 1, inside: panel.right <= window.innerWidth };
  });
  check("paw sits beside the text, inside the window", fits.side && fits.inside, JSON.stringify(fits));
  await shot("started");

  // Each lesson: its button, then each step's button.
  const lessons = await page.$$eval("[data-paw-open]", (spans) =>
    spans.map((span) => {
      const state = JSON.parse(span.dataset.pawOpen);
      const steps = [];
      // The span is alone in a paragraph; the steps are the next list.
      let node = (span.closest("p") ?? span).nextElementSibling;
      while (node && node.tagName !== "OL") node = node.nextElementSibling;
      if (node) node.dataset.testLesson = state.lesson;
      // The start of a text, as the panel of the tutor shows it.
      const start = (text) => text?.trim().replace(/\s+/g, " ").slice(0, 24);
      for (const li of node ? node.children : []) {
        const say = [...li.childNodes].filter((n) => !(n instanceof Element && n.matches("ul, [data-paw-keys]")));
        const done = [...li.querySelectorAll(":scope li")].map((n) => n.textContent.trim()).find((t) => t.startsWith("✓"));
        steps.push({
          keys: li.querySelector(":scope > [data-paw-keys]") !== null,
          say: start(say.map((n) => n.textContent).join("")),
          done: start(done),
        });
      }
      return { lesson: state.lesson, steps };
    }),
  );
  // PAW_LESSONS="1,2" tries only these lessons.
  const only = process.env.PAW_LESSONS ? process.env.PAW_LESSONS.split(",").map(Number) : null;
  for (const { lesson, steps } of lessons.filter((l) => !only || only.includes(l.lesson))) {
    const report = { lesson, steps: [], ms: 0 };
    result.lessons.push(report);
    const t = Date.now();
    await page.click(`[data-paw-open*='"lesson":${lesson},'] button`);
    const opened = await until(async () => new RegExp(`lesson ${lesson} of \\d+`).test(await screen()) && /runs here/.test(await status()), 60000);
    if (!opened) {
      check(`lesson ${lesson} opens`, false, await status());
      result.screens[`lesson-${lesson}-open`] = (await screen()).split("\n");
      continue;
    }
    const total = steps.length;
    for (let i = 0; i < total; i++) {
      if (!steps[i].keys) {
        report.steps.push("no keys");
        break;
      }
      const target = await page.$(`ol[data-test-lesson="${lesson}"] > li:nth-child(${i + 1}) > [data-paw-keys] button`);
      await target.click();
      await until(() => target.evaluate((b) => !b.disabled), 60000);
      const next = i + 1 < total ? `step ${i + 2} of ${total}` : null;
      // The tutor shows the next step, or the ✓ text of this one. A panel
      // beside the tutor can make its title too short for the step number.
      const done = await until(async () => {
        const text = await screen();
        const flat = text.replace(/[\s│]+/g, " ");
        if (next && text.includes(next)) return "ok";
        if (steps[i].done && flat.includes(steps[i].done)) return "ok";
        if (i + 1 < total && flat.includes(steps[i + 1].say)) return "ok";
        if (/Lesson done|the last lesson/.test(text)) return "ok";
        return /has quit/.test(await status()) && "ok";
      }, 20000);
      // A float over the tutor (a list that the step opens) hides it: the
      // next step, which closes the float, shows that this one was done.
      const covered = !done && !new RegExp(`lesson ${lesson} of`).test(await screen());
      report.steps.push(done || (covered ? "covered" : `not noticed (${next})`));
      if (lesson === 1 && i === 0) {
        await pause(1500);
        result.sound = await page.evaluate(() => window.pawPod.audio.stats());
        check("the song of lesson 1 reaches the worklet", result.sound.played > 0 && result.sound.peak > 0.01, JSON.stringify(result.sound));
      }
      if (!done && !covered) {
        result.screens[`lesson-${lesson}-step-${i + 1}`] = (await screen()).split("\n");
        await shot(`lesson-${lesson}-step-${i + 1}-failed`);
        break;
      }
    }
    report.ms = Date.now() - t;
    const ok = report.steps.length === total && report.steps.at(-1) === "ok" && report.steps.every((s) => s === "ok" || s === "covered");
    check(`lesson ${lesson}: each step's button does the step`, ok, report.steps.join(" "));
    if ([2, 4, 10].includes(lesson)) await shot(`lesson-${lesson}`);
  }
} catch (err) {
  check("the test ran to its end", false, String((err && err.stack) || err));
} finally {
  result.failed = failed;
  fs.writeFileSync(outPath, JSON.stringify(result, null, 1));
  await browser.close();
  fs.rmSync(scratch, { recursive: true, force: true });
}
process.exit(failed);
