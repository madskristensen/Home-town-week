# Hometown Week

Weekly family digests for the city you live in. This is a Jekyll site for [hometownweek.com](https://hometownweek.com/).

Washington, Oregon, Idaho, Utah, Colorado, and Texas each have a state hub. Live city names link to `/{state}/{city}/latest/`. The home page leads with this week's digest: an opt-in location lookup, a city search, and links to the state hubs. The full city list stays on those hubs and in the footer. The site header does not list cities. Names without a digest stay in `_data/coming_soon.yml` and do not link to issues.

## URLs

| Page | Path |
| --- | --- |
| Home | `/` |
| State hub | `/{state}/`, for example `/wa/`, `/or/`, `/id/`, `/ut/`, `/co/`, `/tx/` |
| City | `/{state}/{city}/`, for example `/wa/redmond/` or `/or/bend/` |
| Year | `/{state}/{city}/2026/` |
| Issue | `/{state}/{city}/2026/sep-28-oct-4/` |
| Latest | `/{state}/{city}/latest/` |
| About | `/about/` |
| Feed | `/feed.xml` |

An issue address is the Monday-through-Sunday span in lowercase, such as `sep-14-sep-20`, `sep-21-sep-27`, or `sep-28-oct-4`. Week numbers do not appear in addresses, titles, or headings. Older `/w38/`, `/w39/`, and `/w40/` addresses redirect to the new ones.

`/wa/{city}/latest/` redirects to the newest issue for that city.

## Local build

```bash
bundle install
bundle exec jekyll serve
```

Open `http://127.0.0.1:4000/`. `_config.yml` sets `url` to `https://hometownweek.com` and `baseurl` to an empty string. Keep it that way. A `/Home-town-week` baseurl breaks CSS and images on the apex domain.

## GitHub Pages

Pushes to `main` run `.github/workflows/pages.yml`, which builds the site and deploys it with GitHub Actions. The workflow passes the Pages base path through, and that path is empty on the custom domain.

## Adding a city

1. Add the city to `_data/cities.yml`, alphabetical within its state, with `lat` and `lon` for the city center in decimal degrees. The home page uses those coordinates to suggest the nearest digest. It does not call a geocoding service. Add a `sources:` list on that same city entry (name, url, type, notes). Do not put the list in a separate file. Types include city_hall, parks, allevents, theater, market, library, downtown, and venue. Cover the Monday, Wednesday, and Friday crawl: the city hall calendar, AllEvents for that city and state, a local theater, plus parks, market, downtown, and the library as one source among several.
2. Add `{state}/{city}/index.html`, `{state}/{city}/{year}/index.html`, and `{state}/{city}/latest.html`, using the Redmond pages as the pattern.
3. Add issues under `_issues/` with `city`, `state`, `year`, `slug`, and a permalink like `/wa/kirkland/2026/sep-28-oct-4/`.
4. Put a state outline with a city pin at `assets/images/cities/{state}/{city}.svg`. Put photos in `assets/images/{city}/` at 800, 1200, and 1600 widths, and add `{city}_events.yml` under `_data/` if you want event structured data.

The footer reads `_data/cities.yml` in list order: states in block order, cities alphabetical inside each state. The home page uses the same order for its state links and its search index. It does not print every city. When a coming-soon city gets a digest, add it here (with `lat` and `lon`) and remove it from `_data/coming_soon.yml`. Do not publish an empty issue just to make the name clickable. The site header does not list cities. Away from the home page and away from a city page, it links to each state hub. City names in the header appear only on that city's own pages.

Every page inlines `assets/css/site.css` from the head. There is no separate city stylesheet and no render-blocking CSS link. State hubs still use the city cards.
