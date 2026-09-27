# Hometown Week

Weekly family digests for the city you live in. This is a Jekyll site for GitHub Pages. While setup continues, it is published at [madskristensen.github.io/Home-town-week](https://madskristensen.github.io/Home-town-week/).

Redmond, Washington is the first city. More cities can use the same path, for example `/wa/kirkland/` later.

## URLs

| Page | Path |
| --- | --- |
| Home | `/` |
| City | `/wa/redmond/` |
| Year | `/wa/redmond/2026/` |
| Issue | `/wa/redmond/2026/w40/` |
| Latest | `/wa/redmond/latest/` |
| About | `/about/` |
| Feed | `/feed.xml` |

Issue addresses use the ISO week (`w40`). Week numbers stay in the URL only. Page titles and headings use the date span and the topic.

`/wa/redmond/latest/` redirects to the newest Redmond issue.

## Local build

```bash
bundle install
bundle exec jekyll serve
```

Open `http://127.0.0.1:4000/Home-town-week/`. `_config.yml` sets `url` to `https://madskristensen.github.io` and `baseurl` to `/Home-town-week`.

## GitHub Pages

Pushes to `main` run `.github/workflows/pages.yml`, which builds the site and deploys it with GitHub Actions.

1. In the repo, open **Settings → Pages**.
2. Under **Build and deployment**, set **Source** to **GitHub Actions**.
3. Leave the custom domain blank for now. The site is the project URL above.

`CNAME` is in the repo for later and is excluded from the build, so this deploy does not switch the host to hometownweek.com.

## hometownweek.com later

When DNS is ready:

1. Build with the domain overlay: `bundle exec jekyll build --config _config.yml,_config.domain.yml`
2. Stop excluding `CNAME` in `_config.yml` so `hometownweek.com` is published.
3. Point DNS at Pages. If the host can CNAME the apex (ALIAS, ANAME, or CNAME flattening), set `hometownweek.com` to `madskristensen.github.io`. Otherwise use GitHub's A records: `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, and `185.199.111.153`.
4. Confirm the custom domain in Pages settings. Optional `www`: CNAME `www` to `madskristensen.github.io`. The `CNAME` file lists the apex only.

## Adding a city

1. Add the city to `_data/cities.yml`.
2. Add `wa/{state}/{city}/index.html`, `wa/{state}/{city}/{year}/index.html`, and `wa/{state}/{city}/latest.html`, using the Redmond pages as the pattern.
3. Add issues under `_issues/` with `city`, `state`, `year`, `week`, and a permalink like `/wa/kirkland/2026/w40/`.
4. Put photos in `assets/images/{city}/` at 800, 1200, and 1600 widths, and add `{city}_events.yml` under `_data/` if you want event structured data.

City pages load `assets/css/city.css`. The home page does not.
