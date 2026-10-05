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
      var value = card.getAttribute("data-" + group) || "";
      if (groups[group].indexOf(value) === -1) return false;
    }
    return true;
  }
  function applyFilters() {
    var groups = selectedFilterGroups();
    var active = Object.keys(groups).length > 0;
    var visible = 0;
    document.querySelectorAll(".event-card").forEach(function (card) {
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
  for (var filterIndex = 0; filterIndex < filterBoxes.length; filterIndex++) {
    filterBoxes[filterIndex].addEventListener("change", applyFilters);
  }
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
        if (document.querySelector("script[data-cf-beacon]")) return;
        var script = document.createElement("script");
        script.src = "https://static.cloudflareinsights.com/beacon.min.js";
        script.type = "module";
        script.setAttribute("data-cf-beacon", "{\"token\": \"1c415eee86e04aaea8cd73a99feaf064\"}");
        document.head.appendChild(script);
      }
      window.addEventListener("beforeprint", addPrint);
      window.addEventListener("load", function () {
        addPrint();
        addBeacon();
      });
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
        var nodes = document.querySelectorAll(".event-cal, .event-when > .event-share, .event-actions, .footer-meta a, .footer-meta button, .footer-family a, .leaflet-bottom");
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
