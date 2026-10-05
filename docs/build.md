# Build and deploy

## Domain

The site is published at https://www.eastsidecalendar.com. The naked domain redirects there. `CNAME` contains `www.eastsidecalendar.com`. `_config.yml` sets `url` to that host and `baseurl` to an empty string. A `/Home-town-week` baseurl breaks CSS and images on the custom domain.

IndexNow is told about URLs whose source files changed in a push, not the whole sitemap. A city page or that city's event file also refreshes the home page, This weekend, and the seasonal hubs. The verification key file is written at the site root during the Pages build.

`/suggest/` is the page for sending an event. The address `suggestions@eastsidecalendar.com` is shown as text.

## GitHub Actions

Pushes to `main` run `.github/workflows/pages.yml`. The build job can read the repo. Only the deploy job has `pages: write` and `id-token: write`. Python packages are pinned in `requirements.txt`. Third-party actions are pinned to commits. Ruby is the version in `.ruby-version`.

Checkout uses full history so sitemap lastmod can use each file's commit time. A depth of 1 makes every unchanged page look unmodified.

The home share image is cached on a hash of the Eastside map and `script/render-home-og.py`. `librsvg` and the Liberation fonts are installed only when that cache misses. Share-card JPEGs and image variants are cached the same way.

`.github/workflows/prune.yml` runs at 09:17 UTC, with a backup at 10:47 UTC. That is early morning Pacific, after the date has rolled, and it avoids the crowded `:00` minute. The job rebases onto main before it pushes. It deletes events whose last day is before today in America/Los_Angeles from each `{city}/index.md` and from `_data/*_events.yml`, including Worth the Drive. Either way it starts the Pages deploy, so the home page weekend block is chosen again from the current date.

## Sitemap dates

A page with a source file uses that file's newest commit time. A city page also considers `_data/{city}_events.yml`. The home page uses the newest of those. A generated hub has no source file. Its lastmod is the newest commit among the event files, city pages, and photo data that feed it, not the build clock.

## Styles and the service worker

Stylesheets live in `_css/` and are minified with rcssmin, then fingerprinted (`script/fingerprint-css.py`). Every page links `/assets/css/site.<hash>.css`. Smaller layout files are inlined in one `<style>` block. `site.css` stays the shared cached file. Do not inline it. Print CSS is `/assets/css/print.<hash>.css`, added after load.

`_js/event-share.js` is published as `/assets/js/event-share.<hash>.js`. Page behavior scripts stay inline.

The service worker precaches the home page, the fingerprinted stylesheet and script, the manifest, and the shell icons. Leaflet is not in that list. The page cache name is a hash of those shell files. The image cache name stays `eastside-images` across deploys. Stored HTML pages are capped. Each deploy does not wipe saved images.

The Pages build minifies each HTML file, its inline scripts, and its JSON-LD (`script/minify-html.py`). Type is system fonts only. Dark mode follows `prefers-color-scheme: dark`.
