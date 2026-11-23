// The live parts of a page of the website, loaded only on a page that has
// them: a live paw panel ([data-paw-live], pod/paw-live.js beside the pod
// image) and a recorded session (<paw-cast>, paw-cast.js). mdBook adds
// this script to every page (book.toml, additional-js).
//
// The service worker coi-sw.js is at the top of the site, so that its
// scope holds every page: the panel gets its URL here. A page that loads
// pod/paw-live.js itself too gets the same module, which runs once.
(() => {
  const base = document.currentScript.src;
  const panels = document.querySelectorAll("[data-paw-live]");
  if (panels.length) {
    const worker = new URL("coi-sw.js", base).href;
    for (const panel of panels) if (!panel.dataset.pawWorker) panel.dataset.pawWorker = worker;
    import(new URL("pod/paw-live.js", base).href).catch(() => {});
  }
  if (document.querySelector("paw-cast")) import(new URL("paw-cast.js", base).href).catch(() => {});
})();
