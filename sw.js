// Bump this on every deploy to invalidate the old cache.
const CACHE_NAME = "patient-care-v6";
const APP_SHELL = ["/", "/index.html", "/manifest.json", "/icon.svg", "/icon-192.png", "/icon-512.png", "/badge-96.png"];

self.addEventListener("install", event => {
  event.waitUntil(caches.open(CACHE_NAME).then(cache => cache.addAll(APP_SHELL)).catch(() => {}));
  self.skipWaiting();
});

self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(key => key !== CACHE_NAME).map(key => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

// Allow the page to tell a waiting SW to take over immediately.
self.addEventListener("message", e => { if (e.data === "skipWaiting") self.skipWaiting(); });

// ---- Web Push: show a notification even when the app is closed ----
self.addEventListener("push", event => {
  let d = { title: "رعاية المريض", body: "" };
  try { d = event.data.json(); } catch (_) { if (event.data) d.body = event.data.text(); }
  event.waitUntil(self.registration.showNotification(d.title || "رعاية المريض", {
    body: d.body || "",
    icon: "/icon-192.png",
    badge: "/badge-96.png",
    tag: d.tag || "care-reminder",
    renotify: true,
    dir: "auto",
    data: { url: "/" }
  }));
});

// Tapping a notification focuses the open app (or opens it).
self.addEventListener("notificationclick", event => {
  event.notification.close();
  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then(list => {
      for (const c of list) { if ("focus" in c) return c.focus(); }
      if (self.clients.openWindow) return self.clients.openWindow("/");
    })
  );
});

self.addEventListener("fetch", event => {
  const req = event.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;               // Supabase & other origins → straight to network
  if (url.pathname.startsWith("/.netlify/functions/")) return;    // config function → always fresh

  const isHTML = req.mode === "navigate" || (req.headers.get("accept") || "").includes("text/html");

  if (isHTML) {
    // Network-first: always load the latest app when online; fall back to cache offline.
    event.respondWith(
      fetch(req)
        .then(res => { const copy = res.clone(); caches.open(CACHE_NAME).then(c => c.put(req, copy)); return res; })
        .catch(() => caches.match(req).then(c => c || caches.match("/index.html")))
    );
    return;
  }

  // Static assets (manifest, icon): cache-first, refresh in background.
  event.respondWith(
    caches.match(req).then(cached =>
      cached || fetch(req).then(res => { const copy = res.clone(); caches.open(CACHE_NAME).then(c => c.put(req, copy)); return res; })
    )
  );
});
