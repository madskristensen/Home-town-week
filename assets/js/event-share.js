/* Share an event as text. Deferred, so it is not on the first paint. */
(function () {
  var DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  var timers = typeof WeakMap === "function" ? new WeakMap() : null;

  function parseWhen(value) {
    var match = /^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2}))?/.exec(value || "");
    if (!match) return null;
    return {
      y: +match[1],
      m: +match[2],
      d: +match[3],
      hasTime: match[4] != null,
      h: match[4] != null ? +match[4] : 0,
      min: match[5] != null ? +match[5] : 0
    };
  }

  function sameDay(a, b) {
    return a.y === b.y && a.m === b.m && a.d === b.d;
  }

  function dayLabel(part) {
    var weekday = DAYS[new Date(Date.UTC(part.y, part.m - 1, part.d)).getUTCDay()];
    return weekday + ", " + MONTHS[part.m - 1] + " " + part.d;
  }

  function suffix(hour) {
    return hour >= 12 ? "p.m." : "a.m.";
  }

  function hour12(hour) {
    var value = hour % 12;
    return value === 0 ? 12 : value;
  }

  function minutes(min) {
    return (min < 10 ? "0" : "") + min;
  }

  function clock(part, withSuffix) {
    var text = hour12(part.h) + ":" + minutes(part.min);
    if (withSuffix === false) return text;
    return text + " " + suffix(part.h);
  }

  function timeRange(start, end) {
    if (!end || !end.hasTime) return clock(start);
    if (suffix(start.h) === suffix(end.h)) return clock(start, false) + "\u2013" + clock(end);
    return clock(start) + "\u2013" + clock(end);
  }

  function whenLine(startValue, endValue) {
    var start = parseWhen(startValue);
    if (!start) return "";
    var end = parseWhen(endValue);
    var label = dayLabel(start);
    if (!start.hasTime) {
      if (end && !sameDay(start, end)) return label + " to " + dayLabel(end);
      return label;
    }
    if (end && end.hasTime && !sameDay(start, end)) {
      return label + ", " + clock(start) + " to " + dayLabel(end) + ", " + clock(end);
    }
    return label + ", " + timeRange(start, end);
  }

  function clean(value) {
    return (value || "").replace(/\s+/g, " ").trim();
  }

  var BLURB_LIMIT = 180;

  function hasPrice(text, price) {
    var lower = text.toLowerCase();
    var needle = price.toLowerCase();
    var at = lower.indexOf(needle);
    if (at < 0) return false;
    var after = lower.charAt(at + needle.length);
    return !/\d/.test(after);
  }

  function hasContact(text) {
    return /(?:^|\D)(?:\+?1[\s.-]?)?(?:\(\d{3}\)|\d{3})[\s.-]\d{3}[\s.-]\d{4}\b/.test(text) ||
      /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/.test(text);
  }

  function mentionsFree(text) {
    return /\bfree\b/i.test(text);
  }

  function isFreeCost(price) {
    return price.toLowerCase() === "free";
  }

  function withFree(text) {
    if (mentionsFree(text)) return text;
    if (!text) return "Free.";
    var next = text + " Free.";
    return next.length <= BLURB_LIMIT ? next : text;
  }

  function sentencesOf(text) {
    var sentences = [];
    var start = 0;
    var i;
    for (i = 0; i < text.length; i++) {
      var mark = text.charAt(i);
      if (mark !== "." && mark !== "!" && mark !== "?") continue;
      var rest = text.slice(i + 1);
      if (rest && !/^\s/.test(rest)) continue;
      var tail = rest.replace(/^\s+/, "");
      if (tail && !/^[A-Z0-9"']/.test(tail)) continue;
      var sentence = text.slice(start, i + 1).trim();
      if (sentence) sentences.push(sentence);
      start = text.length - tail.length;
      i = start - 1;
    }
    var last = text.slice(start).trim();
    if (last) sentences.push(last);
    return sentences;
  }

  function tidyEllipsis(text) {
    return text.replace(/([.!?])\s*(?:\.{2,}|\u2026)/g, "$1");
  }

  function sentenceEnd(text, limit) {
    var end = -1;
    var i;
    var cap = Math.min(text.length, limit);
    for (i = 0; i < cap; i++) {
      var mark = text.charAt(i);
      if (mark !== "." && mark !== "!" && mark !== "?") continue;
      var rest = text.slice(i + 1);
      if (rest && !/^\s/.test(rest) && rest.charAt(0) !== "") continue;
      if (rest && !/^\s*$/.test(rest) && !/^\s+[A-Z0-9"']/.test(rest)) continue;
      end = i + 1;
    }
    return end;
  }

  function clipSentence(sentence, limit) {
    var max = limit || BLURB_LIMIT;
    if (sentence.length <= max) return sentence;
    var end = sentenceEnd(sentence, max);
    if (end > 40) return sentence.slice(0, end).trim();
    var slice = sentence.slice(0, max - 1);
    var space = slice.lastIndexOf(" ");
    var trimmed = (space > 40 ? slice.slice(0, space) : slice).replace(/[\s,;:]+$/, "");
    while (/[.!?…]$/.test(trimmed) || /\.{2,}$/.test(trimmed)) {
      var back = trimmed.lastIndexOf(" ");
      if (back <= 40) break;
      trimmed = trimmed.slice(0, back).replace(/[\s,;:]+$/, "");
    }
    return trimmed + "\u2026";
  }

  function priceSentenceIndex(sentences, price) {
    var i;
    if (!price) return -1;
    if (isFreeCost(price)) {
      for (i = 0; i < sentences.length; i++) {
        if (mentionsFree(sentences[i])) return i;
      }
      return -1;
    }
    for (i = 0; i < sentences.length; i++) {
      if (hasPrice(sentences[i], price)) return i;
    }
    if (price.charAt(0) === "$") {
      for (i = 0; i < sentences.length; i++) {
        if (/\$\d/.test(sentences[i])) return i;
      }
    }
    return -1;
  }

  function blurbLine(blurb, cost) {
    var price = clean(cost);
    var sentences = sentencesOf(tidyEllipsis(clean(blurb))).filter(function (sentence) {
      return !hasContact(sentence);
    });
    if (!sentences.length) {
      if (isFreeCost(price)) return "Free.";
      return price.length <= BLURB_LIMIT ? price : "";
    }

    if (sentences[0].length > BLURB_LIMIT) {
      var clipped = clipSentence(sentences[0]);
      return isFreeCost(price) ? withFree(clipped) : clipped;
    }

    var indexes = [0];
    if (sentences.length > 1 && (sentences[0] + " " + sentences[1]).length <= BLURB_LIMIT) {
      indexes.push(1);
    }

    function joined(extra) {
      var parts = [];
      var n;
      for (n = 0; n < indexes.length; n++) parts.push(sentences[indexes[n]]);
      if (extra) parts.push(extra);
      return parts.join(" ");
    }

    var body = joined();
    var priceAt = priceSentenceIndex(sentences, price);
    var priceIncluded = priceAt !== -1 && indexes.indexOf(priceAt) !== -1;
    if (priceAt !== -1 && !priceIncluded) {
      var withSentence = joined(sentences[priceAt]);
      if (withSentence.length <= BLURB_LIMIT) body = withSentence;
      else if (isFreeCost(price)) body = withFree(body);
    } else if (isFreeCost(price)) {
      body = withFree(body);
    } else if (!priceIncluded && price && !hasPrice(body, price) && (body + " " + price).length <= BLURB_LIMIT) {
      body += " " + price;
    }
    return body;
  }

  var SHEET_BLURB_LIMIT = 120;

  // Phone share keeps one sentence. Free. is added only when that sentence
  // does not already say free and the result still fits.
  function sheetBlurb(blurb, cost) {
    var price = clean(cost);
    var sentences = sentencesOf(tidyEllipsis(clean(blurb))).filter(function (sentence) {
      return !hasContact(sentence);
    });
    if (!sentences.length) return isFreeCost(price) ? "Free." : "";

    var body = clipSentence(sentences[0], SHEET_BLURB_LIMIT);
    if (!isFreeCost(price) || mentionsFree(body)) return body;
    if (!body) return "Free.";
    var next = body + " Free.";
    return next.length <= SHEET_BLURB_LIMIT ? next : body;
  }

  function placeLine(venue, city) {
    var where = clean(venue);
    var town = clean(city);
    if (where && town && where.toLowerCase().indexOf(town.toLowerCase()) === -1) {
      return where + ", " + town;
    }
    return where || town;
  }

  function sourceUrl(value) {
    var url = clean(value);
    if (!url || url.indexOf("eastsidecalendar.com") !== -1) return "";
    return url;
  }

  var FOUND = "Found on Eastside Family Calendar";

  function joinLines(lines) {
    var kept = [];
    var i;
    for (i = 0; i < lines.length; i++) {
      if (lines[i]) kept.push(lines[i]);
    }
    return kept.join("\n");
  }

  function shareLines(attrs, includeSource) {
    var lines = [
      clean(attrs.title),
      whenLine(attrs.start, attrs.end),
      placeLine(attrs.venue, attrs.city),
      blurbLine(attrs.blurb, attrs.cost)
    ];
    if (includeSource) lines.push(sourceUrl(attrs.url));
    lines.push(FOUND);
    return lines;
  }

  function shareMessage(attrs) {
    return joinLines(shareLines(attrs, true));
  }

  function shareSheetMessage(attrs) {
    var title = clean(attrs.title);
    var when = whenLine(attrs.start, attrs.end);
    var place = placeLine(attrs.venue, attrs.city);
    var blurb = sheetBlurb(attrs.blurb, attrs.cost);
    var source = sourceUrl(attrs.url);
    var lines = [];
    if (title) lines.push(title);
    if (when) lines.push("\uD83D\uDCC5 " + when);
    if (place) lines.push("\uD83D\uDCCD " + place);
    if (blurb) lines.push("", blurb);
    if (source) lines.push("", source);
    return lines.join("\n");
  }

  function escapeHtml(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function cityPage(city) {
    var slug = clean(city).toLowerCase().replace(/['’]/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
    if (!slug) return "https://www.eastsidecalendar.com/";
    return "https://www.eastsidecalendar.com/" + slug + "/";
  }

  function sourceLabel(url) {
    var match = /^https?:\/\/([^/?#]+)/i.exec(url || "");
    if (!match) return "Event details";
    return match[1].replace(/^www\./i, "");
  }

  function shareHtml(attrs) {
    var title = clean(attrs.title);
    var when = whenLine(attrs.start, attrs.end);
    var place = placeLine(attrs.venue, attrs.city);
    var blurb = blurbLine(attrs.blurb, attrs.cost);
    var source = sourceUrl(attrs.url);
    var link = "color:inherit;";
    var parts = [];
    if (title) {
      parts.push(source
        ? "<strong><a href=\"" + escapeHtml(source) + "\" style=\"" + link + "\">" + escapeHtml(title) + "</a></strong>"
        : "<strong>" + escapeHtml(title) + "</strong>");
    }
    if (when) parts.push(escapeHtml(when));
    if (place) parts.push(escapeHtml(place));
    if (blurb) parts.push(escapeHtml(blurb));
    if (source) {
      parts.push("<a href=\"" + escapeHtml(source) + "\" style=\"" + link + "\">" + escapeHtml(sourceLabel(source)) + "</a>");
    }
    parts.push("Found on <a href=\"" + escapeHtml(cityPage(attrs.city)) + "\" style=\"" + link + "\">Eastside Family Calendar</a>");
    return "<div style=\"font-family:system-ui,sans-serif;color:inherit;\">" + parts.join("<br>") + "</div>";
  }

  function attrsFrom(button) {
    return {
      title: button.getAttribute("data-share-title"),
      start: button.getAttribute("data-share-start"),
      end: button.getAttribute("data-share-end"),
      venue: button.getAttribute("data-share-venue"),
      city: button.getAttribute("data-share-city"),
      blurb: button.getAttribute("data-share-blurb"),
      cost: button.getAttribute("data-share-cost"),
      url: button.getAttribute("data-share-url")
    };
  }

  function copyWithTextarea(text) {
    return new Promise(function (resolve, reject) {
      var area = document.createElement("textarea");
      area.value = text;
      area.setAttribute("readonly", "");
      area.style.position = "fixed";
      area.style.left = "-9999px";
      document.body.appendChild(area);
      area.select();
      var ok = false;
      try { ok = document.execCommand("copy"); } catch (error) { ok = false; }
      document.body.removeChild(area);
      if (ok) resolve();
      else reject(error);
    });
  }

  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text).catch(function () {
        return copyWithTextarea(text);
      });
    }
    return copyWithTextarea(text);
  }

  function copyRich(plain, html) {
    if (navigator.clipboard && navigator.clipboard.write && typeof ClipboardItem !== "undefined") {
      try {
        var item = new ClipboardItem({
          "text/html": new Blob([html], { type: "text/html" }),
          "text/plain": new Blob([plain], { type: "text/plain" })
        });
        return navigator.clipboard.write([item]).catch(function () {
          return copyText(plain);
        });
      } catch (error) {
        return copyText(plain);
      }
    }
    return copyText(plain);
  }

  function showStatus(button, text) {
    var status = button.querySelector("[data-share-status]");
    if (!status) {
      status = document.createElement("span");
      status.className = "event-share-status";
      status.setAttribute("data-share-status", "");
      status.setAttribute("aria-live", "polite");
      button.appendChild(status);
    }
    window.setTimeout(function () {
      status.textContent = text;
    }, 20);
    var previous = timers ? timers.get(button) : 0;
    window.clearTimeout(previous);
    var timer = window.setTimeout(function () {
      if (status.textContent === text) status.textContent = "";
    }, 2000);
    if (timers) timers.set(button, timer);
  }

  function copyAndConfirm(button, plain, html) {
    copyRich(plain, html).then(function () {
      showStatus(button, "Copied");
    }, function () {
      showStatus(button, "Could not copy.");
    });
  }

  function weekendText(button) {
    var picks = (button.getAttribute("data-share-picks") || "").split(" || ");
    var lines = [];
    var i;
    for (i = 0; i < picks.length && lines.length < 5; i++) {
      var line = clean(picks[i]);
      if (line) lines.push(line);
    }
    var url = clean(button.getAttribute("data-share-url"));
    if (url) lines.push(url);
    return lines.join("\n");
  }

  function shareWeekend(button) {
    var text = weekendText(button);
    var title = clean(button.getAttribute("data-share-title")) || "This weekend";
    if (navigator.share) {
      navigator.share({ title: title, text: text }).catch(function (error) {
        if (error && error.name === "AbortError") return;
        copyText(text).then(function () {
          showStatus(button, "Copied");
        }, function () {
          showStatus(button, "Could not copy.");
        });
      });
      return;
    }
    copyText(text).then(function () {
      showStatus(button, "Copied");
    }, function () {
      showStatus(button, "Could not copy.");
    });
  }

  function share(button) {
    if (button.getAttribute("data-share-mode") === "weekend") {
      shareWeekend(button);
      return;
    }
    var attrs = attrsFrom(button);
    var plain = shareMessage(attrs);
    var html = shareHtml(attrs);
    if (navigator.share) {
      navigator.share({ title: clean(attrs.title), text: shareSheetMessage(attrs) }).catch(function (error) {
        if (error && error.name === "AbortError") return;
        copyAndConfirm(button, plain, html);
      });
      return;
    }
    copyAndConfirm(button, plain, html);
  }

  if (typeof document !== "undefined") document.addEventListener("click", function (event) {
    var button = event.target && event.target.closest ? event.target.closest(".event-share") : null;
    if (!button) return;
    event.preventDefault();
    event.stopPropagation();
    share(button);
  });

  if (typeof module !== "undefined" && module.exports) {
    module.exports = {
      shareMessage: shareMessage,
      shareSheetMessage: shareSheetMessage,
      shareHtml: shareHtml,
      weekendText: weekendText
    };
  }
})();
