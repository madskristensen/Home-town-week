# Cities and events

`_data/cities.yml` stays in alphabetical order. The home page and the header menu use that order. The footer does not list the cities. Do not publish an empty page just to make a name clickable.

On a city page the city name is the heading and a link to `/{city}/`. "Family events and things to do with kids in {City}" stays in the title, the meta description, and the structured data. It is not visible text. There is no visible breadcrumb. The JSON-LD graph includes a BreadcrumbList. A hub title links to that hub's path the same way.

## Add a city

1. Add the city to `_data/cities.yml`, alphabetical, with `lat` and `lon` for the city center. Those coordinates are the reference for neighbors in `_data/nearby.yml`. Add a `sources:` list on that same city entry. Types include city_hall, parks, allevents, theater, market, library, downtown, venue, museum, nature, farm, school, sports, and news. When a source is already a machine feed, set `format` to `ical`, `rss`, `libcal`, `bibliocommons`, or `allevents`. If the feed URL is not the browse page, put it in `feed_url`. Set `logo` only when an official city logo is allowed.
2. Add `{city}/index.md`, using the Redmond page as the pattern. Front matter holds the teaser (`hook`). The hero photo lives on the city entry in `_data/cities.yml`. The body is the upcoming events, earliest first. Each event is a `###` title, then a gold date line (`<p class="event-when">`), a place line (`<p class="event-place">`), a short blurb, and a link. Leave the place line as text. The build turns it into an Apple Maps link. The query is the venue and the street address, then the town. The event title is not included. Add the city to `_data/nearby.yml` only when you know two to four neighbors that already have pages.
3. Add the city to the home map in `_includes/eastside-map.html`. The link text is the city name.
4. Add `_data/{city}_events.yml` as one chronological list of the same events. Each row has `name`, `start`, `end`, `place`, `same_as`, and `tags`. Dated rows that match a card become add-to-calendar files. Each city has a subscription feed at `/calendar/{city}.ics`. The city page links Apple, Google, and Outlook to that feed. Do not paste civic meetings, board sessions, or out-of-area listings. Delete a row when the event has ended.
5. Put one source photo in `assets/images/{city}/` and set `hero.image` on the city entry. The share preview is the card the Pages build draws from that photo. A state outline can live at `assets/images/cities/wa/{city}.svg` for the home map. It is not a separate Open Graph PNG.

## Labels

Optional card labels are separate fields, not `tags`. Add one when the source page states it, or when the place makes it clear. Do not guess from the blurb, and do not invent a price.

- `cost`: `Free`, or a price the source lists, such as `"$12"` or `"$55 to $65"`. A `free` tag already means `cost: Free`.
- `ages`: `Toddlers`, `Kids`, `Teens`, or `"All ages"`. Toddlers means aimed at under 5. Ages 5 and older is not Toddlers.
- `setting`: `Indoor` or `Outdoor`. `_data/venue_settings.yml` fills a blank setting. The longest phrase wins.
- `drop_off`: `true` when the child stays and the adult leaves. Camps are not drop-off.
- `signup`: `true` when registration or tickets are required.
- `sensory`: `true` only when the page says sensory-friendly or low-sensory.

Free is the only cost pill. A price and All ages stay plain text. Kids and Teens get a chip only when that page has at least three. Toddlers gets a chip whenever a card has it. Chips in one group combine with OR. Different groups combine with AND.

## Photos

Photos are one source file each, under `assets/images/{city}/`, `assets/images/themes/`, or `assets/images/hubs/{hub}/`. A city hero is set on the city in `_data/cities.yml` (`hero` with `image`, `alt`, `credit`, `license`, and `source`). A place in `_data/venue_images.yml` supplies one photo of that venue.

The Pages build runs `script/render-image-variants.py` and caches the result on a hash of the masters. Card photos become `name-400.avif`, `name-640.avif`, and `name-640.jpg`. A city hero also gets `name-800.avif`, `name-1200.avif`, and `name-1600.avif`. Those files are not committed. A referenced photo that cannot be encoded fails the build.

A hub card uses the event's own photo, then the venue photo, then a themed picture, then that season's pool, then the year-round pool. The build fails if a grid card still has no image. The credit text is the link to the source.

The home page share image is a 1200 by 630 PNG of the Eastside map, written by `script/render-home-og.py` and cached on a hash of the map and the script. City pages, hubs, Worth the Drive, This weekend, and the maps use a 1200 by 630 JPEG from `script/render-share-cards.mjs`.

## Playgrounds

`/playgrounds/` is every public park playground in the 15 cities, in `_data/playground_map.json`. The address is an Apple Maps link, the same query style as an event place. Bellevue, Kenmore, Mercer Island, and Sammamish are limited to parks named on the city directory or playground page. Fall City is listed under Snoqualmie.

Show map loads Leaflet, marker clusters, and `/data/playgrounds.json`. Nothing from those files is requested before the tap. Leaflet's stylesheet is trimmed from `assets/leaflet/leaflet.full.css` at the start of the build and is not committed.
