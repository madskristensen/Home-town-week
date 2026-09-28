# Hometown Week SEO audit

The week-issue model this audit describes is retired. Each city is one page at `/{state}/{city}/` with a chronological list of upcoming events. There are no week URLs, year indexes, or `/latest/` redirects.

Live site: https://hometownweek.com  
Repo: madskristensen/Home-town-week  
Audited: 27 September 2026, against production and a local production build.  
Baseline before fixes: `c59e0af` (inline CSS and no `tabindex="-1"` on `main` left as they were).

## PageSpeed Insights, mobile home

Report: https://pagespeed.web.dev/analysis/https-hometownweek-com/0hb4xv09b1?form_factor=mobile  
Lighthouse 13.5.0, fetched 2026-09-27T11:28:20Z, Moto-class phone (412×823, DPR 1.75). No CrUX field data (“No Data”).

| Category | Score |
| --- | --- |
| Performance | 90 |
| SEO | 100 |
| Accessibility | 100 |
| Best practices | 100 |

Lab metrics: FCP 2.7s, LCP 3.0s, Speed Index 2.7s, TTI 3.0s, TBT 0ms, CLS 0. The LCP element is the first city card, Bellevue Botanical Garden (`botanical-garden-800.webp`), already `fetchpriority="high"` and not lazy. LCP discovery passes.

### High: render-blocking requests (fonts fixed; layout CSS already unblocked)

“Render-blocking requests” scored 0, estimated savings 2,060ms. Two requests in that run:

- `fonts.googleapis.com` CSS, 751ms. That stylesheet was the long pole. It then chains Fraunces and Outfit from `fonts.gstatic.com` (about 68KB and 33KB). The only layout shift on the page is those two files arriving (`CLS` still scores 0).
- `/assets/css/main.css`, 159ms. The flash fix that landed in `ee04530` already removed the blocking `main.css` and `city.css` links. Layout CSS stays in the one inline `<style>` block, including `critical.css`, and `main` still has no `tabindex="-1"`. This change does not put those links back.

**Fix:** Fraunces and Outfit latin and latin-ext woff2 files are served from `/assets/fonts/` (SIL Open Font License). The `@font-face` rules sit in that same first `<style>`, with `font-display: swap`. The Google stylesheet, its `media=print` swap, and the preconnects are gone, so first paint does not wait on a third-party CSS hop and does not need script to turn the fonts on. The font files are not preloaded, so they do not compete with the LCP photo. First paint uses the fallback stacks in `critical.css`, then swaps.

### Medium: image delivery, 197 KiB

Six home-page cards are flagged. On this phone the photo slot is about 380×214 CSS pixels (about 665×374 device pixels), and `sizes` resolves to `100vw`, so the browser picks the 800w file. There is no srcset candidate between the icon and 800. Ferndale, Bothell, and Edmonds are also compressed lightly (Ferndale’s 800w file is 123KB, of which Lighthouse attributes about 63KB to compression). The LCP photo itself is only about 17KB over size, and compression was not flagged for it. These are below-the-fold except Bellevue. Recompressing or adding a ~720w candidate would change the 800/1200/1600 set and the look of the photos, so it is not in this push.

### Medium: cache lifetime, 390 KiB

Every flagged URL is `Cache-Control: max-age=600` (10 minutes), which is what GitHub Pages sends for the apex host. The repo cannot set a longer lifetime. A CDN in front of Pages would be a hosting change, not a template change.

### Not a problem in this run

SEO, accessibility, and best-practices audits passed, including meta description, canonical, crawlable links, image alt, tap targets, and contrast. Unused CSS and unused JavaScript savings are zero. Document TTFB is not the issue. No third-party cookies. The home-page `city.css` prefetch from the earlier build is gone with the flash fix; city CSS is inlined only on city and Washington pages.

Crawled without following redirects: home, `/wa/`, city homes (Redmond, Kirkland, Bellingham, Mercer Island, and the rest via the sitemap), year indexes, all 65 week digests, `/latest/`, legacy `/w38/` `/w39/` `/w40/`, a missing URL (404), `/about/`, `robots.txt`, `sitemap.xml`, and `feed.xml`. Also checked `http`, `www`, bare paths, and `madskristensen.github.io`.

## Already in good shape

- One `h1` per indexable page. Heading levels do not skip. `lang="en-US"`, charset, and viewport are present. No `hreflang`.
- Canonicals are self-referencing `https://hometownweek.com/.../` URLs. `http`, `www`, `github.io`, and paths without a trailing slash 301 to that host.
- Week digests use date spans (`/wa/redmond/2026/sep-28-oct-4/`). Week numbers are not in titles or headlines. Legacy `/w38/` `/w39/` `/w40/` and `/latest/` are `noindex`, out of the sitemap, and point `rel=canonical` at the real URL.
- City and year pages are `CollectionPage`. Weeks are `BlogPosting` plus `BreadcrumbList`, and `ItemList` when the week has dated events. Visible breadcrumbs match the schema. `rel=prev` / `rel=next` exist in the head and in the week nav, including on the first and last week of each city.
- Issue photos are WebP with 800/1200/1600 `srcset`. Heroes use `fetchpriority="high"`; later photos are `loading="lazy"`. Alts are present. The header map mark is a small decorative SVG (`alt=""`).
- `robots.txt` allows crawl and points at `https://hometownweek.com/sitemap.xml`. The sitemap has 94 URLs, all on the apex host: home, about, `/wa/`, 13 cities, 13 year indexes, 65 issues. Latest, legacy week URLs, the feed, and the 404 are excluded.
- IndexNow is configured. The latest Pages run uploaded the key file and `api.indexnow.org` accepted the sitemap submission. The key filename is the secret, so this audit does not print it.
- Cities stay in the footer and on `/wa/`, not in the front-page header. The masthead kicker is “Weekly family digest”.

## Critical

None. The site is indexable, canonicals match the apex host, and the sitemap does not list duplicate or legacy URLs.

## High

Fixed on `main` in this change.

### 1. Hub pages had no sitemap `lastmod`, and issue `lastmod` was the week’s Monday

`jekyll-sitemap` prints `lastmod` for ordinary pages only when `last_modified_at` is set. Home, `/about/`, `/wa/`, 13 city homes, and 13 year indexes (29 URLs) had none. Issue `lastmod` was the front-matter `date`, so a page written on 26 September for 12 October was stamped `2026-10-12`, and an edit to a past week never moved `lastmod`.

The IndexNow action requires `lastmod` and only submits URLs from the last day. Hubs were never pinged. Past issues were not pinged again after edits. Future-dated issues were pinged on every deploy because their Monday is still in the future.

**Fix:** `_plugins/last_modified.rb` sets `last_modified_at` from each file’s git commit time. City, year, home, and `/wa/` use the newest related issue as well, because those pages change when an issue changes. Checkout uses `fetch-depth: 0` so unchanged files keep their real commit time. `BlogPosting.dateModified` is the later of that time and `datePublished`, so it is never earlier than the publication date.

Example after the build: `/wa/redmond/2026/sep-14-sep-20/` lastmod `2026-09-26T21:31:57-07:00` (the commit), with `datePublished` still `2026-09-14`.

### 2. City and year social images were SVG

All 13 city homes and 13 year indexes set `og:image` and `twitter:image` to `/assets/images/cities/wa/{city}.svg` (`image/svg+xml`, about 1200×1170). Facebook, X, LinkedIn, and Slack do not use SVG for large cards, so those 26 URLs shared with no image.

**Fix:** Open Graph and Twitter now use a WebP from the featured or newest issue (1600×900), and the site PNG if a city has no photo. The header still uses the map SVG. Built Redmond home card: `marymoor-center.webp`. Built Redmond 2026 card: `downtown-park.webp`.

### 3. Five `Event` nodes had no `startDate`

Google’s event rich result requires `startDate`. These were invalid and sat inside an otherwise valid `ItemList`:

| Page | Name |
| --- | --- |
| `/wa/lynnwood/2026/sep-14-sep-20/` | Scriber Lake Park |
| `/wa/lynnwood/2026/sep-21-sep-27/` | Lynnwood Library |
| `/wa/redmond/2026/sep-14-sep-20/` | Welcoming Week |
| `/wa/sammamish/2026/sep-14-sep-20/` | Beaver Lake Park |
| `/wa/sammamish/2026/sep-14-sep-20/` | Pine Lake Park |

**Fix:** the `ItemList` includes only events that have `start`. Redmond’s 14 September week still lists the other 10 events. Lynnwood’s two early weeks and Sammamish’s 14 September week no longer emit an `ItemList`, because every entry was undated. The prose is unchanged. Add a real `start` in the events YAML if those places should return to the list.

### 4. `/wa/` was a generic `WebPage`

City and year pages were already `CollectionPage`. The Washington hub was `WebPage` with a breadcrumb only, so the collection of cities was not in the graph.

**Fix:** `/wa/` is a `CollectionPage` whose `hasPart` is the 13 city collections. Breadcrumb schema is unchanged.

### Smaller fixes included with the above

- `hasPart` blog posts now include `datePublished`.
- Atom entry titles include the city (`Preston Lee at the Saturday market | Redmond`) so the combined feed is not a list of bare headlines.
- Redmond’s city meta description named the market, library, and Marymoor (it was 65 characters and generic). The two shortest issue descriptions (Larry Murante, Preston Lee) now include the 11-to-1 market fact already in the hook.

## Medium (not changed)

- **Title length.** 47 document titles are over 60 characters because the pattern is `{headline} | {City} | Hometown Week`. The longest is the Lynnwood week at 82 characters (`Toddler stories, a science lab, and preschool storytime | Lynnwood | Hometown Week`). Unique and accurate. Truncation in the results page is the tradeoff. Do not shorten by dropping the city.
- **Meta descriptions are still short.** Issue descriptions run about 70–150 characters. Only the two Redmond market lines were under 70, and those were extended. A pass toward 120–160 characters, using the existing hook, would give Google a better snippet. City descriptions other than Redmond are already specific and fine.
- **Four cities stop at 28 September–4 October.** Bothell, Lynnwood, Renton, and Sammamish have no later issue, so those weeks correctly have no “next” link. Bellevue, Bellingham, Edmonds, Everett, Ferndale, Issaquah, Kirkland, Mercer Island, and Redmond continue through 19–25 October. This is a content gap, not a template bug.
- **Event `Place` has a name and no `PostalAddress`.** Rich results warn on a missing address. The place string often already contains a street (`Redmond Library, 15990 NE 85th St`). Splitting that into structured address fields needs a careful pass so we do not invent a postal code.
- **Every `Event.url` is the digest URL.** `sameAs` holds the organizer link. That is a reasonable choice for a roundup. Pointing `url` at `sameAs` would match Google’s “official event page” hint and would also send the click off hometownweek.com.
- **`/latest/` and `/w38/` are HTTP 200 with a meta refresh, not a 301.** GitHub Pages cannot emit a real redirect for those paths. Google treats a zero-delay refresh as a redirect, and the pages are `noindex` with the right canonical. Leave them.
- **City names on the home page and on `/wa/` link to `/wa/{city}/latest/`.** The photo and the date already link to the canonical issue. The name link is an extra hop through a `noindex` URL. It is set that way so the href always tracks the newest issue. Linking the name straight at the issue URL would pass equity in one hop. Product choice, not changed here.
- **Home-page photos are heavier than the mobile slot.** See the PageSpeed section. The 800w file is the smallest srcset candidate, a few cards are lightly compressed, and GitHub Pages caches them for 10 minutes. Not changed here.
- **Do not put `main.css` or `city.css` back on a blocking `<link>`.** The mobile report charged `main.css` about 159ms while that link still existed. `ee04530` removed it. The inline block, including `critical.css`, is what paints the masthead.

## Low

- The 404 is `noindex` and has no canonical. `og:url` still points at `https://hometownweek.com/404.html`. Harmless while `noindex` holds.
- The feed is Atom, served as `application/xml`. Absolute URLs are correct. A second RSS file is unnecessary.
- The `Person` node for Mads lives on the homepage (`/about/#person`). The about page itself is a `WebPage` and does not repeat that node. Crawlers that have seen the homepage can join the graph.
- No site search, so no `SearchAction`. Do not add an empty one.
- GitHub Pages does not send HSTS from this repo. `http` already 301s to `https`.
- Legacy redirect pages share the title “This page has moved”. They are `noindex`.

## Checks that should stay true after deploy

- City and year `og:image` / `twitter:image` end in `.webp` or the site PNG, never `.svg`. The header `<img class="city-mark">` is still the SVG.
- `sitemap.xml` has a `lastmod` on all 94 URLs, every `loc` on `https://hometownweek.com`, and no `/latest/` or `/w38/` paths.
- `/wa/lynnwood/2026/sep-14-sep-20/` has `BlogPosting` and `BreadcrumbList` and no `Event`. `/wa/redmond/2026/sep-14-sep-20/` has events and does not list “Welcoming Week” in the `ItemList`.
- `/wa/` JSON-LD `@type` is `CollectionPage`.
- `main` has no `tabindex="-1"`. Layout CSS is still an inline `<style>` before the stylesheet link.
