# Hometown Week

Weekly family digests for the city you live in. This is a Jekyll site for [hometownweek.com](https://hometownweek.com/).

Washington editions right now are Redmond, Kirkland, Issaquah, Edmonds, and Ferndale. Each city uses the same path, for example `/wa/kirkland/`.

## URLs

| Page | Path |
| --- | --- |
| Home | `/` |
| Washington | `/wa/` |
| City | `/wa/redmond/`, `/wa/kirkland/`, `/wa/issaquah/`, `/wa/edmonds/`, `/wa/ferndale/` |
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

The home page and the footer both read `_data/cities.yml`. City, year, and issue pages load `assets/css/city.css`. The home page does not, except through the shared card styles in `assets/css/main.css`.
