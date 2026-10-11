/* Site search. The header panel and /search/ share one form
   (_includes/search-form.html). /search.json is fetched the first time a
   box gets focus or the page opens with ?q=, never on page load. Every
   word must match, accents and case are ignored, title matches rank
   first, and the list stops at 20. */
(function () {
  var forms = document.querySelectorAll("form[data-search]");
  if (!forms.length) return;
  var MAX = 20;
  var index = null;
  var loading = null;
  var ORDER = [4, 6, 6, 0, 3, 5, 5, 5, 5, 5, 5, 5];

  function fold(text) {
    return String(text || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "")
      .toLowerCase().replace(/['\u2019]/g, "").replace(/[^a-z0-9]+/g, " ").trim();
  }

  function load(url) {
    if (index) return Promise.resolve(index);
    if (!loading) {
      loading = fetch(url).then(function (res) {
        if (!res.ok) throw new Error(res.status);
        return res.json();
      }).then(function (data) {
        index = data.i.map(function (row, n) {
          return { row: row, n: n, title: " " + fold(row[0]) + " ",
            all: " " + fold(row[0] + " " + data.t[row[1]] + " " + row[2] + " " + row[3] + " " + row[5]) + " " };
        });
        index.types = data.t;
        return index;
      }).catch(function (err) { loading = null; throw err; });
    }
    return loading;
  }

  function search(query) {
    var words = fold(query).split(" ").filter(Boolean);
    if (!words.length) return [];
    var hits = [];
    var i, j, item, score, ok;
    for (i = 0; i < index.length; i++) {
      item = index[i];
      ok = true;
      score = 0;
      for (j = 0; j < words.length; j++) {
        if (item.all.indexOf(words[j]) < 0) { ok = false; break; }
        if (item.title.indexOf(" " + words[j]) >= 0) score += 2;
        else if (item.title.indexOf(words[j]) >= 0) score += 1;
      }
      if (!ok) continue;
      hits.push({ item: item, score: score });
    }
    hits.sort(function (a, b) {
      return b.score - a.score || (ORDER[a.item.row[1]] || 5) - (ORDER[b.item.row[1]] || 5) || a.item.n - b.item.n;
    });
    return hits;
  }

  function render(form, query) {
    var list = form.querySelector(".search-results");
    var status = form.querySelector(".search-status");
    list.textContent = "";
    if (!fold(query)) { status.textContent = ""; return; }
    var hits = search(query);
    status.textContent = hits.length === 0 ? "No matches. Try fewer words."
      : hits.length > MAX ? "Top " + MAX + " of " + hits.length + " matches. Add a word to narrow it."
      : hits.length + (hits.length === 1 ? " match" : " matches");
    var i, row, li, a, meta, bits;
    for (i = 0; i < hits.length && i < MAX; i++) {
      row = hits[i].item.row;
      li = document.createElement("li");
      a = document.createElement("a");
      a.href = row[4];
      a.textContent = row[0];
      meta = document.createElement("span");
      meta.className = "search-meta";
      bits = [index.types[row[1]]];
      if (row[2]) bits.push(row[2]);
      if (row[3]) bits.push(row[3]);
      meta.textContent = bits.join(" \u00b7 ");
      li.appendChild(a);
      li.appendChild(meta);
      list.appendChild(li);
    }
  }

  function wire(form) {
    var input = form.querySelector("input[type=search]");
    var status = form.querySelector(".search-status");
    var url = form.getAttribute("data-index");
    var timer = 0;
    function run() {
      load(url).then(function () { render(form, input.value); }, function () {
        status.textContent = "Search did not load. Press Enter to try again.";
      });
    }
    input.addEventListener("focus", function () { load(url).catch(function () {}); });
    input.addEventListener("input", function () {
      clearTimeout(timer);
      timer = setTimeout(run, 80);
    });
    form.addEventListener("submit", function (event) {
      if (!form.closest(".search-page")) return;
      event.preventDefault();
      var q = input.value.trim();
      history.replaceState(null, "", q ? "?q=" + encodeURIComponent(q) : location.pathname);
      run();
    });
    form.addEventListener("keydown", function (event) {
      if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return;
      var links = Array.prototype.slice.call(form.querySelectorAll(".search-results a"));
      if (!links.length) return;
      var at = links.indexOf(document.activeElement);
      var next = event.key === "ArrowDown" ? at + 1 : at - 1;
      if (next < -1) next = links.length - 1;
      if (next >= links.length) next = 0;
      if (next === -1) input.focus(); else links[next].focus();
      event.preventDefault();
    });
    var panel = form.closest("details");
    if (panel) {
      panel.addEventListener("toggle", function () {
        if (panel.open) { input.focus(); load(url).catch(function () {}); }
      });
    }
    if (form.closest(".search-page")) {
      var q = new URLSearchParams(location.search).get("q");
      if (q) { input.value = q; run(); }
      else input.focus();
      input.addEventListener("input", function () {
        var v = input.value.trim();
        history.replaceState(null, "", v ? "?q=" + encodeURIComponent(v) : location.pathname);
      });
    }
  }

  var k;
  for (k = 0; k < forms.length; k++) wire(forms[k]);
})();
