/* Eastside Family Calendar. Cache the shell and pages opened while online. No push. */
var CACHE = "eastside-calendar-v1";
var SHELL = [
  "/",
  "/manifest.webmanifest",
  "/assets/images/favicon.svg",
  "/assets/images/icon-48.png",
  "/assets/images/icon-192.png",
  "/assets/images/icon-512.png",
  "/assets/images/icon-maskable-192.png",
  "/assets/images/icon-maskable-512.png",
  "/assets/images/apple-touch-icon.png"
];

self.addEventListener("install", function (event) {
  event.waitUntil(
    caches.open(CACHE).then(function (cache) {
      return cache.addAll(SHELL);
    }).then(function () {
      return self.skipWaiting();
    })
  );
});

self.addEventListener("activate", function (event) {
  event.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(keys.filter(function (key) {
        return key !== CACHE;
      }).map(function (key) {
        return caches.delete(key);
      }));
    }).then(function () {
      return self.clients.claim();
    })
  );
});

function isHtml(request) {
  if (request.mode === "navigate") return true;
  var accept = request.headers.get("accept") || "";
  return accept.indexOf("text/html") !== -1;
}

function canStore(response) {
  return response && response.ok && response.type === "basic" && !response.bodyUsed;
}

function store(cache, request, response) {
  if (!canStore(response)) return Promise.resolve();
  return cache.put(request, response.clone()).catch(function () {});
}

function offlineDocument() {
  var html = "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">" +
    "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">" +
    "<meta name=\"theme-color\" content=\"#f4efe6\">" +
    "<title>Offline. Eastside Family Calendar</title></head>" +
    "<body style=\"margin:0;background:#f4efe6;color:#2a3831;font-family:system-ui,-apple-system,Segoe UI,sans-serif\">" +
    "<main style=\"max-width:36rem;margin:0 auto;padding:2.2rem 1rem\">" +
    "<h1 style=\"margin:0 0 0.6rem;color:#1c2b24;font-weight:600\">You are offline</h1>" +
    "<p style=\"margin:0 0 0.8rem;line-height:1.5\">This page is not saved on this device yet. Open it once while you are online, then you can come back to it later.</p>" +
    "<p style=\"margin:0\"><a href=\"/\" style=\"color:#145c40\">Go to Eastside Family Calendar</a></p>" +
    "</main></body></html>";
  return new Response(html, {
    status: 200,
    headers: { "Content-Type": "text/html; charset=utf-8" }
  });
}

function networkFirst(request) {
  return caches.open(CACHE).then(function (cache) {
    return fetch(request).then(function (response) {
      var stored = store(cache, request, response);
      return stored.then(function () {
        return response;
      });
    }).catch(function () {
      return cache.match(request).then(function (cached) {
        return cached || offlineDocument();
      });
    });
  });
}

function staleWhileRevalidate(request) {
  return caches.open(CACHE).then(function (cache) {
    return cache.match(request).then(function (cached) {
      var fetched = fetch(request).then(function (response) {
        var stored = store(cache, request, response);
        return stored.then(function () {
          return response;
        });
      }).catch(function () {
        return cached;
      });
      if (cached) return cached;
      return fetched.then(function (response) {
        return response || new Response("", { status: 504, statusText: "Offline" });
      });
    });
  });
}

self.addEventListener("fetch", function (event) {
  var request = event.request;
  if (request.method !== "GET") return;
  if (request.headers.get("range")) return;

  var url;
  try {
    url = new URL(request.url);
  } catch (err) {
    return;
  }
  if (url.origin !== self.location.origin) return;
  if (url.pathname === "/sw.js") return;

  if (isHtml(request)) {
    event.respondWith(networkFirst(request));
    return;
  }
  event.respondWith(staleWhileRevalidate(request));
});
