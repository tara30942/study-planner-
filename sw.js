const CACHE_NAME = "study-planner-shell-v2";
const BASE_PATH = "/study-planner-/";
const APP_FILES = [
  BASE_PATH,
  BASE_PATH + "index.html",
  BASE_PATH + "manifest.webmanifest",
  BASE_PATH + "icon.svg"
];

self.addEventListener("install", event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(APP_FILES))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(key => key.startsWith("study-planner-") && key !== CACHE_NAME).map(key => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", event => {
  const request = event.request;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) {
    if (url.hostname === "cdn.jsdelivr.net") {
      event.respondWith((async () => {
        const cache = await caches.open(CACHE_NAME);
        const cached = await cache.match(request);
        if (cached) return cached;
        try {
          const response = await fetch(request);
          if (response && (response.ok || response.type === "opaque")) {
            cache.put(request, response.clone()).catch(() => {});
          }
          return response;
        } catch (error) {
          return new Response("", { status: 503, statusText: "Offline" });
        }
      })());
    }
    return;
  }

  if (!url.pathname.startsWith(BASE_PATH)) return;
  if (request.mode === "navigate") {
    event.respondWith((async () => {
      const cache = await caches.open(CACHE_NAME);
      try {
        const response = await fetch(request);
        if (response && response.ok) cache.put(BASE_PATH + "index.html", response.clone()).catch(() => {});
        return response;
      } catch (error) {
        return (await cache.match(request)) || (await cache.match(BASE_PATH + "index.html")) || Response.error();
      }
    })());
    return;
  }

  event.respondWith((async () => {
    const cache = await caches.open(CACHE_NAME);
    const cached = await cache.match(request);
    if (cached) return cached;
    try {
      const response = await fetch(request);
      if (response && response.ok) cache.put(request, response.clone()).catch(() => {});
      return response;
    } catch (error) {
      return Response.error();
    }
  })());
});
