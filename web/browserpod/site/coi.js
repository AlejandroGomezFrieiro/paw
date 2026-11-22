// Cross-origin isolation on a host that cannot set headers (GitHub Pages).
//
// SharedArrayBuffer (and so threads in WebAssembly) needs the page to be
// cross-origin isolated: its response must carry
//   Cross-Origin-Opener-Policy: same-origin
//   Cross-Origin-Embedder-Policy: require-corp (or credentialless)
// A service worker can add these headers to the responses it serves. The
// first visit registers coi-sw.js and loads the page once more, through it.
// A page served with the headers already (serve.py) does nothing here.
(() => {
  if (self.crossOriginIsolated || !("serviceWorker" in navigator)) return;
  if (!window.isSecureContext) return;
  navigator.serviceWorker.register("coi-sw.js").then((registration) => {
    const reload = () => {
      // Once only: a browser that will not isolate does not loop.
      if (sessionStorage.getItem("coi-reloaded")) return;
      sessionStorage.setItem("coi-reloaded", "1");
      location.reload();
    };
    if (navigator.serviceWorker.controller) reload();
    else navigator.serviceWorker.addEventListener("controllerchange", reload);
    registration.update();
  });
})();
