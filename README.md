# Hometown Week

Weekly family digests for the city you live in. This is a Jekyll site for GitHub Pages, published at [hometownweek.com](https://hometownweek.com).

Redmond, Washington is the first city. More cities can use the same path, for example `/wa/kirkland/` later.

## URLs

| Page | Path |
| --- | --- |
| Home | `/` |
| City | `/wa/redmond/` |
| Year | `/wa/redmond/2026/` |
| Issue | `/wa/redmond/2026/w40/` |
| Latest | `/wa/redmond/latest/` |

Issue addresses use the ISO week (`w40`). Week numbers stay in the URL only. Page titles and headings use the date span and the topic.

`/wa/redmond/latest/` redirects to the newest Redmond issue.

## Local build

```bash
bundle install
bundle exec jekyll serve
```

The canonical host is `https://hometownweek.com` (`url` and `baseurl` in `_config.yml`). To preview the github.io project path before the custom domain is attached:

```bash
bundle exec jekyll build --config _config.yml,_config.github.yml
```

That overlay sets `url` to `https://madskristensen.github.io` and `baseurl` to `/Home-town-week`.

## GitHub Pages

Pushes to `main` run `.github/workflows/pages.yml`, which builds the site and deploys it with GitHub Actions.

1. In the repo, open **Settings → Pages**.
2. Under **Build and deployment**, set **Source** to **GitHub Actions**.
3. The `CNAME` file already sets the custom domain to `hometownweek.com`. Confirm that domain on the Pages settings page after the first deploy.

## DNS for hometownweek.com

Point the domain at GitHub Pages, then wait for the certificate.

- If your DNS host can use a CNAME on the apex (ALIAS, ANAME, or CNAME flattening), set `hometownweek.com` to `madskristensen.github.io`.
- If the apex cannot be a CNAME, use GitHub's A records: `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, and `185.199.111.153`.
- Optional `www`: a CNAME from `www` to `madskristensen.github.io`. The `CNAME` file in this repo lists the apex only, which is the host Pages will serve.

## Adding a city

1. Add the city to `_data/cities.yml`.
2. Add `wa/{state}/{city}/index.html`, `wa/{state}/{city}/{year}/index.html`, and `wa/{state}/{city}/latest.html`, using the Redmond pages as the pattern.
3. Add issues under `_issues/` with `city`, `state`, `year`, `week`, and a permalink like `/wa/kirkland/2026/w40/`.
4. Put photos in `assets/images/{city}/` at 800, 1200, and 1600 widths, and add `{city}_events.yml` under `_data/` if you want event structured data.

City pages load `assets/css/city.css`. The home page does not.
