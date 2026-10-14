const CACHE = "productjvity-presentation-v3";
const APP_SHELL = ["./", "./?demo=1", "./site.webmanifest", "./productjvity-icon.svg", "./productjvity-icon-192.png", "./productjvity-icon-512.png"];

self.addEventListener("install", event => event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(APP_SHELL)).then(() => self.skipWaiting())));
self.addEventListener("activate", event => event.waitUntil(self.clients.claim()));
self.addEventListener("fetch", event => {
  if (event.request.method !== "GET") return;
  event.respondWith(fetch(event.request).catch(() => caches.match(event.request).then(found => found || caches.match("./?demo=1"))));
});
