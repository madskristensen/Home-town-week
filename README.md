# Eastside Family Calendar

Upcoming family events for cities on Washington's Eastside. This is a Jekyll site. It is published at [eastsidecalendar.com](https://eastsidecalendar.com/). See [Domain](#domain).

The home page leads with a map of the Eastside, from Lake Washington to the Cascade foothills, and a list of the same cities. Each city on the map is a link. The list shows how many upcoming events that city has. The footer does not repeat every city. Every page uses the same compact wordmark bar: the site name on one line, linked home, with the Cities menu on that same row, a thin bottom border, and no kicker. The page heading below it is the large display title. On the home page that heading is "Things to do with kids on the Eastside", followed by "Upcoming family events in Eastside cities, so you never miss the fun." That intro line is on the home page only. A seasonal banner, when one qualifies, sits under the header with a small gap so it reads as its own band.

Newcastle is an Eastside city that does not have a page yet. Do not invent a page for it. Fall City is not a separate page; its farm and library listings are on Snoqualmie. Names without a page can sit in `_data/coming_soon.yml` and do not link anywhere.

## URLs

| Page | Path |
| --- | --- |
| Home | `/` |
| City | `/{city}/`, for example `/redmond/` |
| About | `/about/` |
| Seasonal hub | One path per hub in `_data/seasonal_hubs.yml`, for example `/fall/` and `/christmas/` |
| Feed | `/feed.xml` |
| LLM guide | `/llms.txt` |

`llms.txt` is written at build time from `_data/cities.yml` and `_data/seasonal_hubs.yml`. It lists each city page, the about page, each seasonal hub, and the sitemap. It says the blurbs are original and link to sources. It does not include upcoming-event counts. Do not maintain it by hand.

Seasonal hubs are generated from `_data/seasonal_hubs.yml`. Each hub stays up all year. A section appears only when it has something to list. The home page does not get a separate seasonal note. One banner under the masthead links to the hub that is in season and has enough upcoming events. See [Seasonal cross-check](#seasonal-cross-check). There is no `/halloween/` page. Halloween is the `/fall/#halloween` section. There is no `/holiday-lights/` page. Public light displays go on the map at `/christmas/#lights`. See [Christmas lights map](#christmas-lights-map).

City URLs have no state segment and no year or week segment. Old addresses are not redirected.

The city page lists upcoming family events. There is no year index and no week issue.

Events stay in the city page in the order they are written. The build groups each `###` event into Today, Tomorrow, This week, This weekend, or Later from the first month and day on its gold date line (`<p class="event-when">`). This week is the days after tomorrow and before the coming Saturday. This weekend is the Saturday and Sunday of the current Pacific week (Monday through Sunday). Today and tomorrow take priority over those groups. A line with no month and day, and no matching dated row in `{city}_events.yml`, goes in Later. Empty groups are left out. The groups are in the HTML, so they still show with JavaScript off. If the Pacific date has moved past the build date, the browser moves the same cards into the current groups. The home page count and the city `ItemList` follow those cards, not every row in the data file.

The footer can show a small link, Add to Home screen or Pin to taskbar, only after the browser fires `beforeinstallprompt`. It stays hidden on iOS and when the site is already open in its own window. There is no install card and no saved dismiss or visit count. The service worker still registers on every page. Each deploy names its caches from the commit, drops the previous caches, and keeps pages apart from images. A saved page opened offline or on a slow connection shows a short note with the day it was saved.

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

An editor writes the event blurbs, the city lists, and any curated weekend picks. A blurb tells a parent what the event is, who it suits, and any cost or registration detail. Leave out cross-references to other listings, other events, or other sources, and leave out verification notes about what a page does or does not say. GitHub Actions does not crawl calendars and does not rewrite that copy. The only workflows are `pages.yml` (build, deploy, IndexNow) and `prune.yml` (daily prune and rebuild).

The home block is chosen when the site builds. By default it picks up to four standout events, one city each, for the coming Friday through Sunday. The heading is "This weekend on the Eastside". When that weekend has no standout, the heading is "Coming up on the Eastside" and the window is the next seven days. `_data/weekend_picks.yml` can replace the automatic choice. It is a list of `city` and `name`, and `name` must match `_data/{city}_events.yml`. When at least one listed event is still ahead, those are the picks, in that order, up to four. Entries that have already ended are skipped. If the file is missing, empty, or every entry has ended, the automatic picks are used.

`sources:` lives only on each city in `_data/cities.yml`. Do not add a separate sources file. The editor uses that list when refreshing a city page. Add events in chronological order on `{city}/index.md`, and add the same events to `_data/{city}_events.yml` so the calendar icon and the event list in the page schema stay in step. Do not add an event that has already ended. Do not create week pages. The daily prune removes expired events.

### Seasonal cross-check

Every daily content update checks each new or updated event against all seasonal hub tags and adds the matching tags on that row in `_data/{city}_events.yml`. Tag only what the event is. A Salmon Days parade stays on its city page. Do not tag it `parade`. A Diwali listing is `diwali`, not `holiday-market`. A hub can also name keywords. The build includes an event whose name contains one of those phrases even when the tags were missed, and the next daily run should still add the tag.

When a hub newly crosses the banner threshold, note it in the run summary. The threshold is at least 6 upcoming events from at least 3 different towns. Upcoming means the event's last day is today or later in America/Los_Angeles. The banner is chosen when the site builds. The daily rebuild checks it again. If several hubs qualify, the one whose season ends soonest is shown. If none qualify, there is no banner. At most one banner is shown.

The full tag vocabulary, with the season stored on each hub:

| Hub | Path | Season | Tags |
| --- | --- | --- | --- |
| Fall and Halloween | `/fall/` | Sep 1 through Oct 31 | `pumpkin-patch`, `corn-maze`, `u-pick`, `harvest`, `halloween`, `trunk-or-treat` |
| Christmas | `/christmas/` | Nov 10 through Dec 31 | `tree-lighting`, `holiday-lights`, `santa`, `holiday-market`, `holiday-show`, `parade` |
| Easter | `/easter/` | Mar 15 through Apr 25 | `egg-hunt`, `easter` |
| Fourth of July | `/fourth/` | Jun 28 through Jul 5 | `fourth`, `fireworks` |
| Lunar New Year | `/lunar-new-year/` | Jan 21 through Feb 20 | `lunar-new-year` |
| Diwali | `/diwali/` | Oct 15 through Nov 15 | `diwali` |
| Dia de los Muertos | `/dia-de-los-muertos/` | Oct 28 through Nov 2 | `dia-de-los-muertos` |
| Winter break and snow days | `/winter/` | Dec 15 through Jan 5 | `winter-break`, `snow-day` |
| Rainy day plans | `/rainy-day/` | Oct 1 through May 31 | `rainy-day` |

`/fall/` is the fall hub, in season Sep 1 through Oct 31. Its sections are Pumpkin patches and corn mazes, Apple and u-pick farms, Harvest festivals, and Halloween and trick-or-treat. The Halloween section anchor is `/fall/#halloween`. There is no `/halloween/` page and no redirect. A section also includes an event whose name contains `pumpkin patch`, `harvest festival`, `harvest fest`, `trick-or-treat`, `trick or treat`, `trunk-or-treat`, or `trunk or treat` when the tags were missed. While fall qualifies, the banner says "Fall fun for kids" and links to `/fall/`. Christmas sections are Tree lightings, Holiday lights, Santa visits and photos, Holiday markets and bazaars, Nutcracker and holiday shows, and Parades and festivals. The lights map at `/christmas/#lights` is separate from those sections. There is no `/salmon/` page. Salmon events stay on their city pages. A new season is a new hub in `_data/seasonal_hubs.yml`, including its theme colors and inline SVG. Set `group: town` with `tags` and `keywords` for a town list, or `sections` for named groups. That does not need a code change. The sitemap includes each hub. The page `ItemList` is the same events, in the same order, as the cards on the page. A hub page starts with a row of links to the sections that have events, each with its count. Empty sections are left off the page. Each section is a larger heading, a one-line intro, and one thin rule, then a grid of cards: two columns on a wide screen and one on a narrow screen. A card chooses a picture in this order. First, the event's own licensed photo from the city page. Second, a licensed photo of that specific venue from `_data/venue_images.yml`, and only when the event name or place names that venue. Third, a licensed or public-domain picture of the event type from `assets/images/themes/` and `_data/theme_images.yml`, with credit and source. Fourth, a text card with that hub's small seasonal motif and no photo. The home weekend block uses the same order, and its motif is the active banner's. A venue or theme file is used once on a page. When a theme has two or three pictures, the next card of that type takes the next picture, then the motif. The same theme may show on another town's page. An event's own photo can show again when that same event is listed in two sections. City heroes are not event-card fallbacks. Do not use a photo of identifiable kids or teens. The credit sits on the photo. The title links to the event, without an underline until hover or focus. The date stays gold. A date-only run of a week or more shows "Through {Mon D}". The place, the town, a one-line blurb, and the calendar icon follow. Images below the first row load lazy, with width and height set.

### Christmas lights map

The map is `/christmas/#lights`. It is separate from the chronological sections (Tree lightings, Holiday lights, and the rest). Displays live in `_data/holiday_lights.yml`. The file stays in the hub all year. From Nov 10 through Dec 31 the map is the first section on the page, and it is linked first in the on-page list. The rest of the year it follows the event sections. Pins are buttons on `_includes/eastside-map-static.html`, the same drawing as the home map with city names as labels only. When a city pin moves in `_includes/eastside-map.html`, move it in the static file too.

Each row:

| Field | What to write |
| --- | --- |
| `id` | A short slug, unique in the file. It becomes the list anchor. |
| `name` | The display name. |
| `type` | `home`, `neighborhood`, `park`, `drive-through`, or `walk-through`. |
| `city` | A city id from `_data/cities.yml`. |
| `address` | A street address, a street, or cross-streets. |
| `lat`, `lng` | Decimal degrees. The build projects these onto the Eastside map. |
| `description` | One or two original sentences. |
| `nights` | Which nights it runs, when known. |
| `hours` | Clock times, when known. Leave it blank when the source has none. |
| `source` | The public page, an `https` URL. |
| `free` | `true` or `false`. |
| `last_verified` | The day the source was checked, `YYYY-MM-DD`. |

A public venue can use its published street address. A home can use a house number only when the owner published it, or a news page already names it as the place to visit. Otherwise write the street or the cross-streets. Do not take a house number from a photo or a real-estate listing. A row with `lat` is a map pin and is not copied into the Holiday lights event section.

When a source describes a past season and the next season is not announced, start `nights` with `Last seen 2025` (use that season's year). Dated events still belong on the city page, not in this file.

Submissions arrive at `suggestions@eastsidecalendar.com`. The map links a mailto with the subject `Christmas lights: ` and a body that asks for the address or street, the town, what makes it great, the dates and hours, and whether it is the sender's own house. Add a row from that email when the display is publicly promoted or the owner sent it in. Set `last_verified` to the day you add it. The page says we only list displays that are publicly promoted or sent in by the owner.

Photos are one source file each, under `assets/images/{city}/` or `assets/images/themes/`. A city hero is set once, on that city in `_data/cities.yml` (`hero` with `image`, `alt`, `credit`, `license`, and `source`). It is the visible hero under the city name and the `og:image` and `twitter:image`. Choose a wide, bright landmark or scenic view of the town. Do not use a venue interior, identifiable kids or teens, or a photo that also appears on an event card. Themed event pictures live at `assets/images/themes/{theme}.webp`. `_data/theme_images.yml` maps tags and keywords to those files, with credit, license, and source. Wikimedia Commons, Openverse CC0 or CC BY, CC BY-SA, and other public-domain collections are fine. Do not resize a source file, and do not commit width variants. The Pages workflow runs `script/render-image-variants.py` before Jekyll. It writes AVIF, WebP, and JPEG at 400, 800, 1200, and 1600 pixels wide, never wider than the source, plus `_data/image_variants.yml`. Actions caches those outputs, keyed on a hash of the source files, so an unchanged photo is not encoded again. `_includes/responsive-img.html` prints a `picture` from the manifest: AVIF, then WebP, then JPEG. If the manifest or a width is missing, the tag is the original file and the build still succeeds. The map is SVG and is left as is.

The home page share image is a 1200 by 630 PNG of that same Eastside map, with the site name and a short line under it. The Pages workflow runs `script/render-home-og.py` before Jekyll and writes `assets/images/og-home.png`. That file is not committed. City pages do not use it. A city share image is the hero in `_data/cities.yml`, or the card from `script/render-og-images.py` when that hero is missing.

The first Friday of the month is source maintenance only: find a new calendar or drop a stale URL. That Friday does not rewrite event copy.

A first seed of a city can write the list and fill the upcoming events in the same pass. After that, keep the split. Family events first. If a page does not print a clock, leave the clock out. Do not keep a past event as an archive.

## Adding a city

1. Add the city to `_data/cities.yml`, alphabetical, with `lat` and `lon` for the city center in decimal degrees. Those coordinates are the reference for choosing neighbors in `_data/nearby.yml`. The home page does not look up a location. Add a `sources:` list on that same city entry (name, url, type, notes). Do not put the list in a separate file. Types include city_hall, parks, allevents, theater, market, library, downtown, venue, museum, nature, farm, school, sports, and news. Cover city hall, AllEvents for that city and state, a local theater, plus parks, market, downtown, and the library as one source among several. The editor fills the city page from it. The first Friday of the month keeps this list current. When a source is already a machine feed, set `format` to `ical`, `rss`, `libcal`, `bibliocommons`, or `allevents`. If the feed URL is not the browse page, put it in `feed_url` and leave `url` as the page a person would open. Set `logo` only when an official city logo is allowed. Leave it unset otherwise. The header shows that image only when `logo` is set.
2. Add `{city}/index.md`, using the Redmond page as the pattern. Front matter holds the teaser (`hook`). The hero photo lives on the city entry in `_data/cities.yml`, not in this file. The body is the upcoming events, earliest first. Each event is a `###` title, then a gold date line (`<p class="event-when">`), a place line (`<p class="event-place">`), a short blurb, and a link. The date line needs a month and day (`Mon Sep 28`) so the build can place the event in Today, Tomorrow, This week, This weekend, or Later. Add that city to `_data/nearby.yml` only when you know two to four neighbors that already have pages.
3. Add the city to the home map in `_includes/eastside-map.html`. Mark it with a link whose text is the city name. Copy the same pin and label into `_includes/eastside-map-static.html` as a group, without a link.
4. Add `_data/{city}_events.yml` as one chronological list of the same events that appear on the city page. Each row has `name`, `start`, `end`, `place`, `same_as`, and `tags`. `tags` is a list of short labels. Seasonal labels are in the table above. Other labels the daily routine can add include `free`, `story-time`, and `farmers-market`. Dated rows that match a card become add-to-calendar files. The `ItemList` is those cards. Do not paste civic meetings, board sessions, or out-of-area listings into the file. Delete a row when the event has ended.
5. Put a state outline with a city pin at `assets/images/cities/wa/{city}.svg` if a share card should use that mark. Run `python3 script/render-og-images.py` so `assets/images/og/wa/{city}.png` matches. Share previews use the hero in `_data/cities.yml`, and that map card when it is missing. Put one source photo in `assets/images/{city}/` and set `hero.image` to it. The Pages build makes the other widths and formats.

`_data/cities.yml` stays in alphabetical order. The home page and the Cities menu use that order. The home page also draws those cities on the map. The footer does not print them. When a city without a page gets one, add it here (with `lat` and `lon`) and remove it from `_data/coming_soon.yml`. Do not publish an empty page just to make the name clickable. Every page uses the compact wordmark, and the Cities menu sits in that bar. On the home page the heading below it is "Things to do with kids on the Eastside". On a city page the city name is the heading below it and a link to `/{city}/` with no fragment, with Share on the same line, the subtitle "Family events and things to do with kids in {City}", and the slogan under that when `slogan` is set. There is no breadcrumb and no BreadcrumbList. A hub title links to that hub's own path the same way. There is no separate city top bar.

Every page inlines `assets/css/site.css` from the head. There is no separate city stylesheet and no render-blocking CSS link. Type is system fonts only.
