---
permalink: /sw.js
sitemap: false
---
{%- comment -%}
  Built with the site so each deploy gets a new cache name. Page scripts
  stay inline in the HTML. Any real stylesheet, script, or manifest is
  listed from the files Jekyll copied.
{%- endcomment -%}
{%- assign cache_version = site.time | date: "%Y%m%d%H%M%S" -%}
{%- if site.data.build -%}
{%- assign build_sha = site.data.build.sha | append: "" -%}
{%- if build_sha.size > 0 -%}
{%- assign cache_version = build_sha -%}
{%- endif -%}
{%- endif -%}
/* Eastside Family Calendar. Pages and images are cached apart. No push. */
var VERSION = {{ cache_version | jsonify }};
var PAGES = "eastside-pages-" + VERSION;
var IMAGES = "eastside-images-" + VERSION;
var IMAGE_CAP = 60;
var NAV_TIMEOUT = 3000;
var imageWrite = Promise.resolve();

function enqueueImageWrite(task) {
  var run = imageWrite.then(task, task);
  imageWrite = run.then(function () {}, function () {});
  return run;
}

var SHELL_PAGES = [
  {%- for path in site.data.shell.pages -%}
  "{{ path | relative_url }}",
  {%- endfor -%}
];

var SHELL_IMAGES = [
  {%- for path in site.data.shell.images -%}
  "{{ path | relative_url }}",
  {%- endfor -%}
];

self.addEventListener("install", function (event) {
  event.waitUntil(
    Promise.all([
      caches.open(PAGES).then(function (cache) {
        return precache(cache, SHELL_PAGES);
      }),
      caches.open(IMAGES).then(function (cache) {
        return precache(cache, SHELL_IMAGES);
      })
    ]).then(function () {
      return self.skipWaiting();
    })
  );
});

self.addEventListener("activate", function (event) {
  event.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(keys.map(function (key) {
        if (key === PAGES || key === IMAGES) return Promise.resolve();
        return caches.delete(key);
      }));
    }).then(function () {
      if (!self.registration.navigationPreload) return;
      return self.registration.navigationPreload.enable().catch(function () {});
    }).then(function () {
      return self.clients.claim();
    })
  );
});

function precache(cache, urls) {
  return Promise.all(urls.map(function (url) {
    return fetch(new Request(url, { cache: "reload" })).then(function (response) {
      if (!response || !response.ok) throw new Error("precache " + url);
      return putStamped(cache, url, response);
    });
  }));
}

function isHtml(request) {
  if (request.mode === "navigate") return true;
  var accept = request.headers.get("accept") || "";
  return accept.indexOf("text/html") !== -1;
}

function isImage(request, url) {
  if (request.destination === "image") return true;
  return /\.(?:avif|webp|png|jpe?g|gif|svg|ico)$/i.test(url.pathname);
}

function cacheKey(request) {
  return typeof request === "string" ? request : request.url;
}

function putStamped(cache, request, response) {
  if (!response || !response.ok || response.type !== "basic") return Promise.resolve();
  var headers = new Headers(response.headers);
  headers.set("X-Cached-At", new Date().toISOString());
  var stamped = new Response(response.clone().body, {
    status: response.status,
    statusText: response.statusText,
    headers: headers
  });
  // Navigation requests cannot be cache keys. Store the URL instead.
  return cache.put(cacheKey(request), stamped).catch(function () {});
}

function trimImages(cache) {
  return cache.keys().then(function (requests) {
    if (requests.length <= IMAGE_CAP) return;
    return Promise.all(requests.map(function (request) {
      return cache.match(request).then(function (response) {
        var at = response && response.headers.get("X-Cached-At") || "";
        return { request: request, at: at };
      });
    })).then(function (entries) {
      entries.sort(function (a, b) {
        if (a.at < b.at) return -1;
        if (a.at > b.at) return 1;
        return 0;
      });
      var extra = entries.length - IMAGE_CAP;
      return Promise.all(entries.slice(0, extra).map(function (entry) {
        return cache.delete(entry.request);
      }));
    });
  });
}

function savedLabel(iso) {
  var when = new Date(iso || "");
  if (isNaN(when.getTime())) return "Saved earlier. Some events may have passed.";
  var day = "";
  try {
    day = new Intl.DateTimeFormat("en-US", {
      timeZone: "America/Los_Angeles",
      weekday: "long"
    }).format(when);
  } catch (err) {
    day = "";
  }
  if (!day) return "Saved earlier. Some events may have passed.";
  return "Saved " + day + ". Some events may have passed.";
}

function withSavedNote(response) {
  var type = response.headers.get("content-type") || "";
  if (type.indexOf("text/html") === -1) return Promise.resolve(response);
  var text = savedLabel(response.headers.get("X-Cached-At"));
  return response.text().then(function (html) {
    var safe = text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    var note = '<p id="saved-note" class="saved-note" role="status">' + safe + "</p>";
    var next = html.replace(/<body([^>]*)>/i, function (match) {
      return match + note;
    });
    if (next === html) next = note + html;
    var headers = new Headers(response.headers);
    headers.delete("content-length");
    return new Response(next, {
      status: response.status,
      statusText: response.statusText,
      headers: headers
    });
  });
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

function networkFromEvent(event, request) {
  var preload = event.preloadResponse || Promise.resolve();
  var preloadedOrFetch = Promise.resolve(preload).then(function (preloaded) {
    if (preloaded) return preloaded;
    return fetch(request);
  }, function () {
    return fetch(request);
  });
  // Offline, a preload can still resolve from the browser disk cache.
  // That is a saved page, so it should take the cached-page path.
  if (typeof navigator !== "undefined" && navigator.onLine === false) {
    preloadedOrFetch.catch(function () {});
    return Promise.reject(new Error("offline"));
  }
  return preloadedOrFetch;
}

function withTimeout(promise, ms) {
  return new Promise(function (resolve, reject) {
    var done = false;
    var timer = setTimeout(function () {
      if (done) return;
      done = true;
      resolve(null);
    }, ms);
    promise.then(function (value) {
      if (done) return;
      done = true;
      clearTimeout(timer);
      resolve(value);
    }, function (err) {
      if (done) return;
      done = true;
      clearTimeout(timer);
      reject(err);
    });
  });
}

function serveCachedPage(request, network) {
  return caches.open(PAGES).then(function (cache) {
    return cache.match(cacheKey(request)).then(function (cached) {
      if (cached) return withSavedNote(cached);
      return network.then(function (response) {
        return response || offlineDocument();
      }).catch(function () {
        return offlineDocument();
      });
    });
  });
}

function networkFirstNavigation(event, request) {
  var network = networkFromEvent(event, request);
  var caching = network.then(function (response) {
    if (!response || !response.ok || response.type !== "basic") return;
    // Clone before any await. The page reads the original body as soon
    // as this navigation is allowed to finish.
    var copy = response.clone();
    return caches.open(PAGES).then(function (cache) {
      return putStamped(cache, request, copy);
    });
  }).catch(function () {});
  event.waitUntil(caching);
  return withTimeout(network, NAV_TIMEOUT).then(function (response) {
    if (response) return response;
    return serveCachedPage(request, network);
  }).catch(function () {
    return serveCachedPage(request, network);
  });
}

function staleWhileRevalidate(event, request, cacheName) {
  return caches.open(cacheName).then(function (cache) {
    return cache.match(cacheKey(request)).then(function (cached) {
      var refreshed = fetch(request).then(function (response) {
        var store = function () {
          return putStamped(cache, request, response).then(function () {
            if (cacheName === IMAGES) return trimImages(cache);
          });
        };
        var stored = cacheName === IMAGES ? enqueueImageWrite(store) : store();
        return stored.then(function () {
          return response;
        });
      }).catch(function () {
        return cached;
      });
      if (cached) {
        event.waitUntil(refreshed.catch(function () {}));
        return cached;
      }
      return refreshed.then(function (response) {
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
    event.respondWith(networkFirstNavigation(event, request));
    return;
  }
  var cacheName = isImage(request, url) ? IMAGES : PAGES;
  event.respondWith(staleWhileRevalidate(event, request, cacheName));
});
