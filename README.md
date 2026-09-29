# Eastside Family Calendar

Upcoming family events for cities on Washington's Eastside. This is a Jekyll site. It is published at [eastsidecalendar.com](https://eastsidecalendar.com/). See [Domain](#domain).

The home page leads with a map of the Eastside, from Lake Washington to the Cascade foothills, and a list of the same cities. Each city on the map is a link. The list shows how many upcoming events that city has. The footer does not repeat every city. City pages and the other pages use a slim bar: the mark, Eastside Family Calendar, and a Cities menu. The home page does not show that bar. Its nameplate is the page heading. The menu lists cities. It does not lay the names across the bar.

Newcastle is an Eastside city that does not have a page yet. Do not invent a page for it. Fall City is not a separate page; its farm and library listings are on Snoqualmie. Names without a page can sit in `_data/coming_soon.yml` and do not link anywhere.

## URLs

| Page | Path |
| --- | --- |
| Home | `/` |
| City | `/{city}/`, for example `/redmond/` |
| About | `/about/` |
| Feed | `/feed.xml` |
| LLM guide | `/llms.txt` |

`llms.txt` is written at build time from `_data/cities.yml`. It lists each city page and the sitemap. It does not include upcoming-event counts. Do not maintain it by hand.

City URLs have no state segment and no year or week segment. Old addresses are not redirected.

The city page lists upcoming family events. There is no year index and no week issue.

Events stay in the city page in the order they are written. The build groups each `###` event into Today, Tomorrow, This weekend, or Later from the first month and day on its gold date line (`<p class="event-when">`). A line with no month and day, and no matching dated row in `{city}_events.yml`, goes in Later. Empty groups are left out. Today and tomorrow take priority over the weekend. This weekend is the Saturday and Sunday of the current Pacific week. The groups are in the HTML, so they still show with JavaScript off. If the Pacific date has moved past the build date, the browser moves the same cards into the current groups.

The footer can show a small link, Add to Home screen or Pin to taskbar, only after the browser fires `beforeinstallprompt`. It stays hidden on iOS and when the site is already open in its own window. There is no install card and no saved dismiss or visit count. The service worker still registers on every page.

`_data/nearby.yml` lists up to four nearby city ids per city, under `wa`. The Also close row links only to ids that have a page.

## Domain

The site is published with a custom GitHub Actions workflow. GitHub ignores the `CNAME` file for that kind of publish. The live host is the custom domain in the repository Pages settings, which is eastsidecalendar.com. `_config.yml` sets `url` to `https://eastsidecalendar.com` and `baseurl` to an empty string. Keep the baseurl empty. A `/Home-town-week` baseurl breaks CSS and images on the apex domain.

IndexNow reads `https://eastsidecalendar.com/sitemap.xml`. That file has to be real sitemap XML. Do not point IndexNow at a retired host.

Suggestion and request links use `suggestions@eastsidecalendar.com`.

## Local build

```bash
bundle install
bundle exec jekyll serve
```

Open `http://127.0.0.1:4000/`.

## GitHub Pages

Pushes to `main` run `.github/workflows/pages.yml`, which builds the site and deploys it with GitHub Actions. The workflow passes the Pages base path through, and that path is empty on the custom domain.

`.github/workflows/prune.yml` runs daily at 11:15 UTC, early morning Pacific. It deletes events whose last day is before today in America/Los_Angeles from each city page (`{city}/index.md`) and from `_data/{city}_events.yml`. If nothing expired, it does not commit. If it removed something, it pushes that commit. Either way it starts the Pages deploy, so the home page weekend block is chosen again from the current date. The HTML is static. The browser does not hide old events.

## Content

An editor writes the event blurbs, the city lists, and any curated weekend picks. GitHub Actions does not crawl calendars and does not rewrite that copy. The only workflows are `pages.yml` (build, deploy, IndexNow) and `prune.yml` (daily prune and rebuild).

The home block is chosen when the site builds. By default it picks up to four standout events, one city each, for the coming Friday through Sunday. The heading is "This weekend on the Eastside". When that weekend has no standout, the heading is "Coming up on the Eastside" and the window is the next seven days. `_data/weekend_picks.yml` can replace the automatic choice. It is a list of `city` and `name`, and `name` must match `_data/{city}_events.yml`. When at least one listed event is still ahead, those are the picks, in that order, up to four. Entries that have already ended are skipped. If the file is missing, empty, or every entry has ended, the automatic picks are used.

`sources:` lives only on each city in `_data/cities.yml`. Do not add a separate sources file. The editor uses that list when refreshing a city page. Add events in chronological order on `{city}/index.md`, and add the same events to `_data/{city}_events.yml` so the calendar icon and the event list in the page schema stay in step. Do not add an event that has already ended. Do not create week pages. The daily prune removes expired events.

Photos are one source file each, under `assets/images/{city}/`. Put that path on the city hero or in the event photo include. Do not resize it, and do not commit width variants. The Pages workflow runs `script/render-image-variants.py` before Jekyll. It writes AVIF, WebP, and JPEG at 400, 800, 1200, and 1600 pixels wide, never wider than the source, plus `_data/image_variants.yml`. Actions caches those outputs, keyed on a hash of the source files, so an unchanged photo is not encoded again. `_includes/responsive-img.html` prints a `picture` from the manifest: AVIF, then WebP, then JPEG. If the manifest or a width is missing, the tag is the original file and the build still succeeds. The map is SVG and is left as is.

The first Friday of the month is source maintenance only: find a new calendar or drop a stale URL. That Friday does not rewrite event copy.

A first seed of a city can write the list and fill the upcoming events in the same pass. After that, keep the split. Family events first. If a page does not print a clock, leave the clock out. Do not keep a past event as an archive.

## Adding a city

1. Add the city to `_data/cities.yml`, alphabetical, with `lat` and `lon` for the city center in decimal degrees. Those coordinates are the reference for choosing neighbors in `_data/nearby.yml`. The home page does not look up a location. Add a `sources:` list on that same city entry (name, url, type, notes). Do not put the list in a separate file. Types include city_hall, parks, allevents, theater, market, library, downtown, and venue. Cover city hall, AllEvents for that city and state, a local theater, plus parks, market, downtown, and the library as one source among several. The editor fills the city page from it. The first Friday of the month keeps this list current. When a source is already a machine feed, set `format` to `ical`, `rss`, `libcal`, `bibliocommons`, or `allevents`. If the feed URL is not the browse page, put it in `feed_url` and leave `url` as the page a person would open. Set `logo` only when an official city logo is allowed. Leave it unset otherwise. The header shows that image only when `logo` is set.
2. Add `{city}/index.md`, using the Redmond page as the pattern. Front matter holds the teaser (`hook`) and an optional hero image. The body is the upcoming events, earliest first. Each event is a `###` title, then a gold date line (`<p class="event-when">`), a place line (`<p class="event-place">`), a short blurb, and a link. The date line needs a month and day (`Mon Sep 28`) so the build can place the event in Today, Tomorrow, This weekend, or Later. Add that city to `_data/nearby.yml` only when you know two to four neighbors that already have pages.
3. Add the city to the home map in `_includes/eastside-map.html`. Mark it with a link whose text is the city name.
4. Add `_data/{city}_events.yml` as one chronological list (`name`, `start`, `end`, `place`, `same_as`). Dated rows become add-to-calendar files and the `ItemList` on the city page. Delete a row when the event has ended.
5. Put a state outline with a city pin at `assets/images/cities/wa/{city}.svg` if a share card should use that mark. Run `python3 script/render-og-images.py` so `assets/images/og/wa/{city}.png` matches. Share previews use the city hero when the page has one, and that map card when it does not. Put one source photo in `assets/images/{city}/` and point the hero `image` at it. The Pages build makes the other widths and formats.

`_data/cities.yml` stays in alphabetical order. The home page and the Cities menu use that order. The home page also draws those cities on the map. The footer does not print them. When a city without a page gets one, add it here (with `lat` and `lon`) and remove it from `_data/coming_soon.yml`. Do not publish an empty page just to make the name clickable. City pages use the slim bar: the mark, Eastside Family Calendar, and a Cities menu. The home page does not. Its heading is the nameplate. On a city page that bar sits above the city name, the only heading, with the official slogan under it when `slogan` is set. There is no state outline in the city header.

Every page inlines `assets/css/site.css` from the head. There is no separate city stylesheet and no render-blocking CSS link. Type is system fonts only.
