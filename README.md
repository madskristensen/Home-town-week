# Hometown Week

Upcoming family events for the city you live in. This is a Jekyll site for [hometownweek.com](https://hometownweek.com/).

Washington, Oregon, Idaho, Utah, Colorado, Texas, and California each have a state hub. A city name on a state hub, and a result in Find your city, open that city's page. The home page leads with a location lookup, a city search, and a map of the states that already have events. Choosing a highlighted state opens that state's hub. The full city list stays on those hubs and in the footer. The site header does not list cities. Names without a page stay in `_data/coming_soon.yml` and do not link anywhere. State outlines live in `_data/us_map.json` (regenerate with `python3 script/build-us-map.py`). A state is highlighted only when `_data/cities.yml` includes one of its cities.

Weeks are not pages. A later Monday email may use a week, and that email is out of scope here.

## URLs

| Page | Path |
| --- | --- |
| Home | `/` |
| State hub | `/{state}/`, for example `/wa/`, `/or/`, `/id/`, `/ut/`, `/co/`, `/tx/`, `/ca/` |
| City | `/{state}/{city}/`, for example `/wa/redmond/` or `/or/bend/` |
| About | `/about/` |
| Feed | `/feed.xml` |

The city page is the digest: a short teaser, then upcoming family events in chronological order. There is no year index, no week issue, and no `/latest/` redirect. Old week addresses are not redirected.

## Local build

```bash
bundle install
bundle exec jekyll serve
```

Open `http://127.0.0.1:4000/`. `_config.yml` sets `url` to `https://hometownweek.com` and `baseurl` to an empty string. Keep it that way. A `/Home-town-week` baseurl breaks CSS and images on the apex domain.

## GitHub Pages

Pushes to `main` run `.github/workflows/pages.yml`, which builds the site and deploys it with GitHub Actions. The workflow passes the Pages base path through, and that path is empty on the custom domain.

`.github/workflows/prune.yml` runs daily, after midnight Pacific. It deletes events whose last day is before today in America/Los_Angeles from each city page and from `_data/{city}_events.yml`. If nothing expired, it does not commit. If it removed something, it pushes that commit and starts the Pages deploy. The HTML is static. The browser does not hide old events.

## Update cadence

`sources:` lives only on each city in `_data/cities.yml`. Do not add a separate sources file.

Monday is the primary content fill. Read the lists already in `cities.yml` and update each city's upcoming list from those URLs. Add events in chronological order on `{state}/{city}/index.md`, and add the same events to `_data/{city}_events.yml` so the calendar icon and the event list in the page schema stay in step. Do not add an event that has already ended. Do not create week pages. Monday does not add or remove sources. The daily prune removes expired events, so Monday does not have to hunt for them.

Thursday is the midweek content fill, a visible update before the weekend. Read the same lists and refresh event copy that is still ahead. Thursday does not add or remove sources, and it does not create week pages.

The first Friday of the month is source maintenance only: find a new calendar or drop a stale URL. That Friday does not rewrite event copy.

A first seed of a city can write the list and fill the upcoming events in the same pass. After that, keep the split. Family events first. If a page does not print a clock, leave the clock out. Do not keep a past event as an archive.

## Adding a city

1. Add the city to `_data/cities.yml`, alphabetical within its state, with `lat` and `lon` for the city center in decimal degrees. The home page uses those coordinates to list cities within about 10 miles, then the nearest page if none are that close. It does not call a geocoding service. Add a `sources:` list on that same city entry (name, url, type, notes). Do not put the list in a separate file. Types include city_hall, parks, allevents, theater, market, library, downtown, and venue. Cover city hall, AllEvents for that city and state, a local theater, plus parks, market, downtown, and the library as one source among several. Monday and Thursday fill the city page from it. The first Friday of the month keeps this list current.
2. Add `{state}/{city}/index.md`, using the Redmond page as the pattern. Front matter holds the teaser (`hook`) and an optional hero image. The body is the upcoming events, earliest first. Each event is a `###` title, then a gold date line (`<p class="event-when">`), a place line (`<p class="event-place">`), a short blurb, and a link.
3. Add `_data/{city}_events.yml` as one chronological list (`name`, `start`, `end`, `place`, `same_as`). Dated rows become add-to-calendar files and the `ItemList` on the city page. Delete a row when the event has ended.
4. Put a state outline with a city pin at `assets/images/cities/{state}/{city}.svg`. Run `python3 script/render-og-images.py` so `assets/images/og/{state}/{city}.png` matches that mark. Share previews use the city hero when the page has one, and that map card when it does not. Put photos in `assets/images/{city}/` at 800, 1200, and 1600 widths.

The footer reads `_data/cities.yml` in list order: states in block order, cities alphabetical inside each state. The home page uses the same order for the state names under the map and for its search index. It does not print every city. When a coming-soon city gets a page, add it here (with `lat` and `lon`) and remove it from `_data/coming_soon.yml`. Do not publish an empty page just to make the name clickable. The site header does not list cities. Away from the home page and away from a city page, it links to each state hub. Home uses Hometown Week as the only title, set as the nameplate. On a city page a slim Hometown Week bar sits above the city name, the only heading, with the official slogan or "Weekly family digest" under it and a small map pin beside the name.

Every page inlines `assets/css/site.css` from the head. There is no separate city stylesheet and no render-blocking CSS link. Type is system fonts only. State hubs still use the city cards.
