/* Shared page behavior. Loaded with fetchpriority=low so it does not
   compete with the city hero. Layout that must run without a network
   wait stays inline: the js class, the hero reveal, and past-event buckets. */
(function () {
  var header = document.querySelector(".nav-mock");
  if (!header) return;
  var menus = header.querySelectorAll("details");
  function closeOthers(details) {
    var i, other;
    for (i = 0; i < menus.length; i++) {
      other = menus[i];
      if (other === details || !other.open) continue;
      if (other.contains(details) || details.contains(other)) continue;
      other.open = false;
    }
  }
  var n;
  for (n = 0; n < menus.length; n++) {
    menus[n].addEventListener("toggle", function () {
      if (this.open) closeOthers(this);
    });
  }
  document.addEventListener("keydown", function (event) {
    if (event.key !== "Escape") return;
    var open = header.querySelectorAll("details[open]");
    var inner = null;
    var i;
    for (i = 0; i < open.length; i++) {
      if (!open[i].querySelector("details[open]")) inner = open[i];
    }
    if (!inner) return;
    inner.open = false;
    var summary = inner.querySelector(":scope > summary");
    if (summary) summary.focus();
    event.preventDefault();
  });
  document.addEventListener("click", function (event) {
    var open = header.querySelectorAll("details[open]");
    var i;
    for (i = 0; i < open.length; i++) {
      if (!open[i].contains(event.target)) open[i].open = false;
    }
  });
})();

var slot = document.getElementById("eastside-map");
        var source = document.getElementById("eastside-map-src");
        if (slot && source && source.content) {
          var mount = function () {
            if (slot.querySelector("svg")) return;
            slot.appendChild(source.content.cloneNode(true));
          };
          var schedule = function () {
            if (window.requestIdleCallback) requestIdleCallback(mount, { timeout: 1200 });
            else setTimeout(mount, 1);
          };
          if (!("IntersectionObserver" in window)) {
            schedule();
          } else {
            var watcher = new IntersectionObserver(function (entries) {
              var i;
              for (i = 0; i < entries.length; i++) {
                if (!entries[i].isIntersecting) continue;
                watcher.disconnect();
                schedule();
                return;
              }
            }, { rootMargin: "80px 0px" });
            watcher.observe(slot);
          }
        }

(function () {
  function runningInstalled() {
    try {
      if (window.matchMedia("(display-mode: standalone)").matches) return true;
      if (window.matchMedia("(display-mode: minimal-ui)").matches) return true;
      if (window.matchMedia("(display-mode: fullscreen)").matches) return true;
      if (window.matchMedia("(display-mode: window-controls-overlay)").matches) return true;
    } catch (err) {}
    return window.navigator.standalone === true;
  }

  function registerServiceWorker() {
    if (!("serviceWorker" in navigator)) return;
    var node = document.querySelector("script[data-sw]");
    var url = (node && node.getAttribute("data-sw")) || "/sw.js";
    navigator.serviceWorker.register(url, { scope: "/", updateViaCache: "none" }).catch(function () {});
  }

  window.addEventListener("load", registerServiceWorker);

  function onIdle(fn) {
    if (window.requestIdleCallback) requestIdleCallback(fn, { timeout: 1500 });
    else setTimeout(fn, 1);
  }

  onIdle(function () {
  var filterBoxes = document.querySelectorAll(".event-filters input[data-group]");
  function selectedFilterGroups() {
    var groups = {};
    var i;
    for (i = 0; i < filterBoxes.length; i++) {
      var box = filterBoxes[i];
      if (!box.checked) continue;
      var group = box.getAttribute("data-group");
      if (!group) continue;
      if (!groups[group]) groups[group] = [];
      groups[group].push(box.value);
    }
    return groups;
  }
  function matchingCard(card, groups) {
    var names = Object.keys(groups);
    var i;
    for (i = 0; i < names.length; i++) {
      var group = names[i];
      // A card can carry several values in one group, split by "|".
      var values = (card.getAttribute("data-" + group) || "").split("|");
      var hit = false;
      var v;
      for (v = 0; v < values.length; v++) {
        if (groups[group].indexOf(values[v]) !== -1) hit = true;
      }
      if (!hit) return false;
    }
    return true;
  }
  function applyFilters() {
    var groups = selectedFilterGroups();
    var active = Object.keys(groups).length > 0;
    var visible = 0;
    // Shared cards, and the compact rows of a camp-style list.
    document.querySelectorAll(".event-card, .camp-list > li").forEach(function (card) {
      var show = !active || matchingCard(card, groups);
      card.classList.toggle("is-filtered-out", !show);
      if (show) visible += 1;
    });
    document.querySelectorAll("h2.event-bucket").forEach(function (heading) {
      var any = false;
      var node = heading.nextElementSibling;
      if (node && node.classList.contains("card-grid")) {
        var nested = node.querySelectorAll(".event-card");
        var n;
        for (n = 0; n < nested.length; n++) {
          if (!nested[n].classList.contains("is-filtered-out")) any = true;
        }
      }
      while (node && !node.classList.contains("event-bucket") && !node.classList.contains("filter-empty") && !node.classList.contains("suggest-event")) {
        if (node.classList.contains("event-card") && !node.classList.contains("is-filtered-out")) any = true;
        if (node.classList.contains("card-grid")) {
          var inner = node.querySelectorAll(".event-card");
          var j;
          for (j = 0; j < inner.length; j++) {
            if (!inner[j].classList.contains("is-filtered-out")) any = true;
          }
        }
        node = node.nextElementSibling;
      }
      heading.classList.toggle("is-filtered-out", active && !any);
    });
    document.querySelectorAll(".card-grid").forEach(function (grid) {
      var cards = grid.querySelectorAll(".event-card");
      if (!cards.length) return;
      var any = false;
      var i;
      for (i = 0; i < cards.length; i++) {
        if (!cards[i].classList.contains("is-filtered-out")) any = true;
      }
      grid.classList.toggle("is-filtered-out", active && !any);
    });
    document.querySelectorAll(".hub-section").forEach(function (section) {
      var cards = section.querySelectorAll(".event-card");
      if (!cards.length) return;
      var any = false;
      var i;
      for (i = 0; i < cards.length; i++) {
        if (!cards[i].classList.contains("is-filtered-out")) any = true;
      }
      section.classList.toggle("is-filtered-out", active && !any);
    });
    document.querySelectorAll(".camp-town").forEach(function (section) {
      var rows = section.querySelectorAll(".camp-list > li, .event-card");
      var shown = 0;
      var i;
      for (i = 0; i < rows.length; i++) {
        if (!rows[i].classList.contains("is-filtered-out")) shown += 1;
      }
      var count = section.querySelector(".camp-group-count");
      if (count) count.textContent = String(shown);
      section.classList.toggle("is-filtered-out", active && shown === 0);
    });
    document.querySelectorAll(".hub-toc li").forEach(function (item) {
      var link = item.querySelector("a");
      if (!link) return;
      var id = (link.getAttribute("href") || "").replace(/^#/, "");
      var section = id ? document.getElementById(id) : null;
      if (!section) return;
      var cards = section.querySelectorAll(".event-card");
      var any = false;
      var i;
      for (i = 0; i < cards.length; i++) {
        if (!cards[i].classList.contains("is-filtered-out")) any = true;
      }
      item.classList.toggle("is-filtered-out", active && cards.length > 0 && !any);
    });
    document.querySelectorAll(".filter-empty").forEach(function (note) {
      note.hidden = !active || visible > 0;
    });
  }
  // The Group by pills rebuild the groups, so filter the new ones again.
  document.addEventListener("rows-regrouped", applyFilters);
  for (var filterIndex = 0; filterIndex < filterBoxes.length; filterIndex++) {
    filterBoxes[filterIndex].addEventListener("change", applyFilters);
  }
  // A chip checked before this ran (the playground ?town= preset).
  if (Object.keys(selectedFilterGroups()).length) applyFilters();
  });

  var installLink = document.getElementById("install-link");
  var installHowto = document.getElementById("install-howto");

  function isIOS() {
    var ua = navigator.userAgent || "";
    if (/iPad|iPhone|iPod/.test(ua)) return true;
    return navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1;
  }

  function hideInstallLink() {
    if (installLink) installLink.hidden = true;
  }

  function installLinkLabel() {
    var ua = navigator.userAgent || "";
    var platform = navigator.platform || "";
    var mobile = false;
    try {
      if (navigator.userAgentData) {
        if (navigator.userAgentData.platform) platform = navigator.userAgentData.platform;
        mobile = navigator.userAgentData.mobile === true;
      }
    } catch (err) {}
    if (/Android/i.test(ua) || /Android/i.test(platform) || mobile) return "Add to Home screen";
    return "Pin to taskbar";
  }

  function openInstallHowto() {
    if (!installHowto || typeof installHowto.showModal !== "function") return;
    if (!installHowto.open) installHowto.showModal();
    installHowto.focus();
  }

  if (runningInstalled()) {
    hideInstallLink();
    window.addEventListener("beforeinstallprompt", function (event) {
      event.preventDefault();
    });
  } else if (isIOS() && installLink && installHowto) {
    installLink.textContent = "Install app";
    installLink.hidden = false;
    installLink.setAttribute("aria-haspopup", "dialog");
    installLink.setAttribute("aria-controls", "install-howto");
    installLink.addEventListener("click", openInstallHowto);
    installHowto.querySelector("[data-install-close]").addEventListener("click", function () {
      installHowto.close();
    });
    installHowto.addEventListener("close", function () {
      installLink.focus();
    });
    window.addEventListener("beforeinstallprompt", function (event) {
      event.preventDefault();
    });
  } else if (installLink) {
    var deferredPrompt = null;

    installLink.addEventListener("click", function () {
      if (!deferredPrompt || typeof deferredPrompt.prompt !== "function") return;
      var promptEvent = deferredPrompt;
      deferredPrompt = null;
      var pending;
      try {
        pending = promptEvent.prompt();
      } catch (err) {
        hideInstallLink();
        return;
      }
      Promise.resolve(pending).then(function () {
        return promptEvent.userChoice;
      }).then(function () {
        hideInstallLink();
      }).catch(function () {
        hideInstallLink();
      });
    });

    window.addEventListener("beforeinstallprompt", function (event) {
      if (runningInstalled()) return;
      event.preventDefault();
      deferredPrompt = event;
      installLink.textContent = installLinkLabel();
      installLink.hidden = false;
    });

    window.addEventListener("appinstalled", function () {
      deferredPrompt = null;
      hideInstallLink();
    });
  }
})();

(function () {
      var node = document.querySelector("script[data-print]");
    var printHref = (node && node.getAttribute("data-print")) || "";
    if (!printHref) return;
      function addPrint() {
        if (document.head.querySelector("link[data-print-css]")) return;
        var link = document.createElement("link");
        link.rel = "stylesheet";
        link.href = printHref;
        link.media = "print";
        link.setAttribute("data-print-css", "");
        document.head.appendChild(link);
      }
      function addBeacon() {
        try {
          var m = /[?&]notrack=([01])/.exec(location.search);
          if (m) {
            if (m[1] === "1") localStorage.setItem("notrack", "1");
            else localStorage.removeItem("notrack");
          }
          if (localStorage.getItem("notrack") === "1") return;
        } catch (e) {}
        if (document.querySelector("script[data-cf-beacon]")) return;
        var script = document.createElement("script");
        script.src = "https://static.cloudflareinsights.com/beacon.min.js";
        script.type = "module";
        script.setAttribute("data-cf-beacon", "{\"token\": \"1c415eee86e04aaea8cd73a99feaf064\"}");
        document.head.appendChild(script);
      }
      window.addEventListener("beforeprint", addPrint);
      window.addEventListener("load", addBeacon);
    })();

(function () {
      var el = document.querySelector("[data-print-date]");
      if (!el) return;
      var text = new Intl.DateTimeFormat("en-US", {
        timeZone: "America/Los_Angeles",
        year: "numeric",
        month: "long",
        day: "numeric"
      }).format(new Date());
      el.textContent = "Printed " + text + " ";
    })();

if ("scrollRestoration" in history) history.scrollRestoration = "auto";

(function () {
      var button = document.querySelector(".to-top");
      if (!button) return;
      var reduce = window.matchMedia("(prefers-reduced-motion: reduce)");
      var brand = document.querySelector(".brand a");

      function shown(on) {
        button.classList.toggle("is-on", on);
        button.tabIndex = on ? 0 : -1;
        button.setAttribute("aria-hidden", on ? "false" : "true");
        if (!on && document.activeElement === button && brand) {
          brand.focus({ preventScroll: true });
        }
      }

      function hits(box) {
        var nodes = document.querySelectorAll(".event-cal, .event-when > .event-share, .event-actions, .footer-meta a, .footer-meta button, .footer-family a, .map-choice button, .leaflet-bottom");
        var found = null;
        for (var i = 0; i < nodes.length; i++) {
          var el = nodes[i];
          if (el.hidden) continue;
          var r = el.getBoundingClientRect();
          if (r.width < 1 || r.height < 1) continue;
          if (r.right < box.left || r.left > box.right || r.bottom < box.top || r.top > box.bottom) continue;
          if (!found || r.top < found.top) found = r;
        }
        return found;
      }

      function place() {
        button.style.setProperty("--to-top-lift", "0px");
        var lift = 0;
        var cap = window.innerHeight * 0.42;
        for (var n = 0; n < 5; n++) {
          var box = button.getBoundingClientRect();
          var hit = hits(box);
          if (!hit) return true;
          lift += box.bottom - hit.top + 8;
          if (lift > cap) return false;
          button.style.setProperty("--to-top-lift", lift + "px");
        }
        return !hits(button.getBoundingClientRect());
      }

      function update() {
        var on = window.scrollY > window.innerHeight * 1.5;
        if (!on) {
          shown(false);
          button.style.setProperty("--to-top-lift", "0px");
          return;
        }
        if (!place()) {
          shown(false);
          return;
        }
        shown(true);
      }

      var queued = false;
      function queue() {
        if (queued) return;
        queued = true;
        requestAnimationFrame(function () {
          queued = false;
          update();
        });
      }

      window.addEventListener("scroll", queue, { passive: true });
      window.addEventListener("resize", queue);
      button.addEventListener("click", function () {
        window.scrollTo({ top: 0, left: 0, behavior: reduce.matches ? "auto" : "smooth" });
        if (reduce.matches && brand) brand.focus({ preventScroll: true });
      });
    })();

/* Map app choice. Place links ship as Google Maps searches, which work
   everywhere with no script. Apple devices get Apple Maps unless the
   footer choice saved Google. The query is read back from each link,
   so cards carry no extra markup. Playground map popups are added
   later, so a link is pointed again when it is pressed. */
(function () {
  var key = "map-app";
  var bases = {
    google: "https://www.google.com/maps/search/?api=1&query=",
    apple: "https://maps.apple.com/?q="
  };

  function mapQuery(href) {
    var match = /^https:\/\/(?:www\.google\.com\/maps\/search\/\?api=1&query=|maps\.apple\.com\/\?q=)([^&#]*)$/.exec(href || "");
    return match ? match[1] : null;
  }

  function mapHref(href, app) {
    var query = mapQuery(href);
    return query === null ? null : bases[app] + query;
  }

  var picked = null;

  function chosenApp() {
    if (picked) return picked;
    var saved = null;
    try { saved = localStorage.getItem(key); } catch (e) {}
    if (saved === "apple" || saved === "google") return saved;
    return /iPhone|iPad|iPod|Macintosh/.test(navigator.userAgent) ? "apple" : "google";
  }

  function point(link, app) {
    var next = mapHref(link.getAttribute("href"), app);
    if (next === null) return false;
    if (next !== link.getAttribute("href")) link.setAttribute("href", next);
    return true;
  }

  function apply(app) {
    var links = document.querySelectorAll("a.addr");
    var found = false;
    for (var i = 0; i < links.length; i++) {
      if (point(links[i], app)) found = true;
    }
    var row = document.querySelector(".map-choice");
    if (!row) return found;
    var buttons = row.querySelectorAll("button");
    for (var n = 0; n < buttons.length; n++) {
      buttons[n].setAttribute("aria-pressed", buttons[n].value === app ? "true" : "false");
    }
    if (found) row.hidden = false;
    return found;
  }

  apply(chosenApp());

  function repoint(event) {
    var link = event.target.closest && event.target.closest("a.addr");
    if (link) point(link, chosenApp());
  }
  document.addEventListener("pointerdown", repoint, true);
  document.addEventListener("click", repoint, true);
  window.addEventListener("pageshow", function (event) {
    if (event.persisted) apply(chosenApp());
  });

  var row = document.querySelector(".map-choice");
  if (!row) return;
  row.addEventListener("click", function (event) {
    var button = event.target.closest("button");
    if (!button || !bases[button.value]) return;
    try {
      localStorage.setItem(key, button.value);
      picked = null;
    } catch (e) {
      picked = button.value;
    }
    apply(button.value);
  });
})();

/* Better photo: a camera button at the right end of each card photo's
   credit strip. Picking a file shows it in place at once, then uploads it
   to the submit API for review. On failure the old photo comes back. */
(function () {
  var node = document.querySelector("script[data-api]");
  var api = node && node.getAttribute("data-api");
  if (!api || !window.fetch || !window.FormData) return;
  var strips = document.querySelectorAll(".event-card figure > figcaption, .camp-sponsored figure > figcaption");
  if (!strips.length) return;
  var picker = document.createElement("input");
  picker.type = "file";
  picker.accept = "image/*";
  picker.hidden = true;
  document.body.appendChild(picker);
  var note = document.createElement("p");
  note.className = "photo-note";
  note.setAttribute("role", "status");
  document.body.appendChild(note);
  var noteTimer = 0;
  var target = null;

  // Photos are scaled so the long edge is at most 1600px, the widest
  // variant the site serves (city hero srcset). Phone photos shrink from
  // 3-12 MB to a few hundred KB. A file the browser cannot decode (HEIC
  // on most non-Apple browsers) goes up as is.
  var MAX_EDGE = 1600;
  var MAX_BYTES = 8 * 1024 * 1024;

  function decode(file) {
    if (window.createImageBitmap) {
      return createImageBitmap(file, { imageOrientation: "from-image" }).catch(function () {
        return createImageBitmap(file);
      });
    }
    return new Promise(function (resolve, reject) {
      var url = URL.createObjectURL(file);
      var im = new Image();
      im.onload = function () { URL.revokeObjectURL(url); resolve(im); };
      im.onerror = function () { URL.revokeObjectURL(url); reject(new Error("decode")); };
      im.src = url;
    });
  }

  function shrink(file) {
    return decode(file).then(function (src) {
      var w = src.naturalWidth || src.width;
      var h = src.naturalHeight || src.height;
      if (!w || !h) throw new Error("decode");
      var scale = Math.min(1, MAX_EDGE / Math.max(w, h));
      var canvas = document.createElement("canvas");
      canvas.width = Math.max(1, Math.round(w * scale));
      canvas.height = Math.max(1, Math.round(h * scale));
      var ctx = canvas.getContext("2d");
      ctx.fillStyle = "#fff";
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      ctx.drawImage(src, 0, 0, canvas.width, canvas.height);
      if (src.close) src.close();
      return new Promise(function (resolve) {
        canvas.toBlob(function (blob) { resolve(blob && blob.size ? blob : file); }, "image/jpeg", 0.85);
      });
    }).catch(function () {
      return file;
    });
  }

  function say(text, bad) {
    note.textContent = text;
    note.classList.toggle("is-bad", !!bad);
    note.classList.add("is-on");
    clearTimeout(noteTimer);
    noteTimer = setTimeout(function () { note.classList.remove("is-on"); }, 6000);
  }

  Array.prototype.forEach.call(strips, function (strip) {
    var button = document.createElement("button");
    button.type = "button";
    button.className = "photo-swap";
    button.title = "Suggest a better photo of this place";
    strip.appendChild(button);
  });

  document.addEventListener("click", function (event) {
    var button = event.target.closest && event.target.closest(".photo-swap");
    if (!button) return;
    target = button.closest("figure");
    picker.value = "";
    picker.click();
  });

  picker.addEventListener("change", function () {
    var file = picker.files && picker.files[0];
    var figure = target;
    if (!file || !figure) return;
    var img = figure.querySelector("img");
    var card = figure.closest("article, li");
    var title = card && card.querySelector("h2, h3, .camp-name-line a");
    var sources = figure.querySelectorAll("source");
    var old = img ? { src: img.src, srcset: img.getAttribute("srcset") } : null;
    var url = URL.createObjectURL(file);
    if (img) {
      Array.prototype.forEach.call(sources, function (s) { s.setAttribute("data-srcset", s.srcset); s.removeAttribute("srcset"); });
      img.removeAttribute("srcset");
      img.src = url;
    }
    function revert() {
      if (!img) return;
      Array.prototype.forEach.call(sources, function (s) { s.srcset = s.getAttribute("data-srcset"); });
      if (old.srcset) img.setAttribute("srcset", old.srcset);
      img.src = old.src;
      URL.revokeObjectURL(url);
    }
    var cardName = title ? title.textContent.trim().replace(/^\d+\s+/, "").slice(0, 200) : "";
    say("Sending your photo…");
    shrink(file).then(function (blob) {
      if (blob.size > MAX_BYTES) throw new Error("413");
      var form = new FormData();
      form.append("photo", blob, blob === file ? file.name : "photo.jpg");
      form.append("page", location.pathname);
      form.append("card_id", (card && card.id) || "");
      form.append("card_name", cardName);
      return fetch(api.replace(/\/$/, "") + "/photo", { method: "POST", body: form });
    }).then(function (res) {
      if (!res.ok) throw new Error(String(res.status));
      say("Thanks! We review new photos daily and may not use every one.");
    }).catch(function (err) {
      revert();
      var msg = err.message === "429" ? "Too many photos for now. Try again later." :
        err.message === "415" ? "That file is not a photo we can use. Try a JPEG or PNG." :
        err.message === "413" ? "That photo is over 8 MB. Try a smaller one." :
        "The photo did not send. Try again later.";
      say(msg, true);
    });
  });
})();
