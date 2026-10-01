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

  function clipSentence(sentence) {
    var budget = BLURB_LIMIT - 3;
    var slice = sentence.slice(0, budget);
    var space = slice.lastIndexOf(" ");
    var trimmed = (space > 0 ? slice.slice(0, space) : slice).replace(/[\s.,;:]+$/, "");
    return trimmed + "...";
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
    var sentences = sentencesOf(clean(blurb)).filter(function (sentence) {
      return !hasContact(sentence);
    });
    if (!sentences.length) return price.length <= BLURB_LIMIT ? price : "";

    if (sentences[0].length > BLURB_LIMIT) {
      var clipped = clipSentence(sentences[0]);
      if (isFreeCost(price) && !mentionsFree(clipped) && (clipped + " Free").length <= BLURB_LIMIT) {
        return clipped + " Free";
      }
      return clipped;
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
      else if (isFreeCost(price) && !mentionsFree(body) && (body + " Free").length <= BLURB_LIMIT) {
        body += " Free";
      }
    } else if (!priceIncluded && price) {
      var already = isFreeCost(price) ? mentionsFree(body) : hasPrice(body, price);
      if (!already && (body + " " + price).length <= BLURB_LIMIT) body += " " + price;
    }
    return body;
  }

  function placeLine(venue, city) {
    var where = clean(venue);
    var town = clean(city);
    if (where && town) return where + ", " + town;
    return where || town;
  }

  function sourceUrl(value) {
    var url = clean(value);
    if (!url || url.indexOf("eastsidecalendar.com") !== -1) return "";
    return url;
  }

  function shareMessage(attrs) {
    var lines = [
      clean(attrs.title),
      whenLine(attrs.start, attrs.end),
      placeLine(attrs.venue, attrs.city),
      blurbLine(attrs.blurb, attrs.cost),
      sourceUrl(attrs.url),
      "Found on eastsidecalendar.com"
    ];
    var kept = [];
    var i;
    for (i = 0; i < lines.length; i++) {
      if (lines[i]) kept.push(lines[i]);
    }
    return kept.join("\n");
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

  function showStatus(button, text) {
    var status = button.querySelector("[data-share-status]");
    if (!status) return;
    status.textContent = text;
    var previous = timers ? timers.get(button) : 0;
    window.clearTimeout(previous);
    var timer = window.setTimeout(function () {
      if (status.textContent === text) status.textContent = "";
    }, 2000);
    if (timers) timers.set(button, timer);
  }

  function copyAndConfirm(button, text) {
    copyText(text).then(function () {
      showStatus(button, "Copied");
    }, function () {
      showStatus(button, "Could not copy.");
    });
  }

  function share(button) {
    var attrs = attrsFrom(button);
    var text = shareMessage(attrs);
    var title = clean(attrs.title);
    if (navigator.share) {
      navigator.share({ title: title, text: text }).catch(function (error) {
        if (error && error.name === "AbortError") return;
        copyAndConfirm(button, text);
      });
      return;
    }
    copyAndConfirm(button, text);
  }

  if (typeof document !== "undefined") document.addEventListener("click", function (event) {
    var button = event.target && event.target.closest ? event.target.closest(".event-share") : null;
    if (!button) return;
    event.preventDefault();
    event.stopPropagation();
    share(button);
  });

  if (typeof module !== "undefined" && module.exports) {
    module.exports = { shareMessage: shareMessage };
  }
})();
