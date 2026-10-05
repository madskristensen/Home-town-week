# Eastside Family Calendar

Upcoming family events for cities on Washington's Eastside. The site is published at [www.eastsidecalendar.com](https://www.eastsidecalendar.com/).

Content rules for the daily routine are in [AGENTS.md](AGENTS.md). Shared card markup is listed in [COMPONENTS.md](COMPONENTS.md).

- [Pages](docs/pages.md) is the public URL map: hubs, maps, feeds, and what the build writes.
- [Cities and events](docs/cities.md) is how to add a city, an event, labels, photos, and playgrounds.
- [Build and deploy](docs/build.md) covers the local build, the domain, and the GitHub Actions workflows.

## Local build

```bash
bundle install
bundle exec jekyll serve
```

Open `http://127.0.0.1:4000/`.

Newcastle has no page. Fall City listings live on Snoqualmie. Covington listings live on Maple Valley. A name that is not in `_data/cities.yml` does not get a page or a link.
