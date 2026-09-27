# Hometown Week

Weekly family digests for the city you live in. This is a Jekyll site for [hometownweek.com](https://hometownweek.com/).

Washington editions right now are Redmond, Kirkland, and Issaquah. Each city uses the same path, for example `/wa/kirkland/`.

## URLs

| Page | Path |
| --- | --- |
| Home | `/` |
| Washington | `/wa/` |
| City | `/wa/redmond/`, `/wa/kirkland/`, `/wa/issaquah/` |
| Year | `/wa/{city}/2026/` |
| Issue | `/wa/{city}/2026/w40/` |
| Latest | `/wa/{city}/latest/` |
| About | `/about/` |
| Feed | `/feed.xml` |

Issue addresses use the ISO week (`w40`). Week numbers stay in the URL only. Page titles and headings use the date span and the topic.

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
3. Add issues under `_issues/` with `city`, `state`, `year`, `week`, and a permalink like `/wa/kirkland/2026/w40/`.
4. Put photos in `assets/images/{city}/` at 800, 1200, and 1600 widths, and add `{city}_events.yml` under `_data/` if you want event structured data.

The home page and the footer both read `_data/cities.yml`. City, year, and issue pages load `assets/css/city.css`. The home page does not, except through the shared card styles in `assets/css/main.css`.
