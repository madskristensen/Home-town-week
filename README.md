# Hometown Week

Weekly family digests for the city you live in. This is a Jekyll site for [hometownweek.com](https://hometownweek.com/).

Washington editions are Bellevue, Bellingham, Bothell, Edmonds, Everett, Ferndale, Issaquah, Kirkland, Lynnwood, Mercer Island, Redmond, Renton, and Sammamish. Each city uses the same path, for example `/wa/kirkland/`.

The home page is a directory, not a second digest. Live city names link to `/{state}/{city}/latest/`. Oregon, Idaho, Utah, Colorado, and Texas are listed as coming soon from `_data/coming_soon.yml`. Those names do not link to issues, and they stay out of the footer and the header.

## URLs

| Page | Path |
| --- | --- |
| Home | `/` |
| Washington | `/wa/` |
| City | `/wa/{city}/`, for example `/wa/redmond/` or `/wa/bellevue/` |
| Year | `/wa/{city}/2026/` |
| Issue | `/wa/{city}/2026/sep-28-oct-4/` |
| Latest | `/wa/{city}/latest/` |
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

1. Add the city to `_data/cities.yml`.
2. Add `wa/{state}/{city}/index.html`, `wa/{state}/{city}/{year}/index.html`, and `wa/{state}/{city}/latest.html`, using the Redmond pages as the pattern.
3. Add issues under `_issues/` with `city`, `state`, `year`, `slug`, and a permalink like `/wa/kirkland/2026/sep-28-oct-4/`.
4. Put photos in `assets/images/{city}/` at 800, 1200, and 1600 widths, and add `{city}_events.yml` under `_data/` if you want event structured data.

The Washington hub and the footer read `_data/cities.yml` in list order, so keep that file alphabetical. The home directory lists those live cities first, then coming-soon names. When a coming-soon city gets a digest, add it here and remove it from `_data/coming_soon.yml`. Do not publish an empty issue just to make the name clickable. The site header does not list cities. It links to Washington. City names in the header appear only on that city's own pages.

City, year, and issue pages inline `assets/css/city.css` with the shared sheet. The home page uses `assets/css/main.css` only. State hubs still use the city cards.
