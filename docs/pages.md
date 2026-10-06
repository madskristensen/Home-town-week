# Pages

| Page | Path |
| --- | --- |
| Home | `/` |
| City | `/{city}/`, for example `/redmond/` |
| About | `/about/` |
| Seasonal hub | One path per hub in `_data/seasonal_hubs.yml`, for example `/fall/` and `/christmas/` |
| Worth the drive | `/worth-the-drive/` |
| This weekend | `/this-weekend/` |
| Christmas lights map | `/christmas/lights/` |
| Halloween decorations map | `/fall/decorations/` |
| Farmers markets | `/farmers-markets/` |
| Book ahead | `/book-ahead/` |
| Summer camps | `/summer-camps/` |
| School calendars | `/no-school-days/` |
| Articles | `/articles/` |
| Feed | `/feed.xml`, plus `/{city}/feed.xml` and a feed for each hub and explore page that lists events |
| LLM guide | `/llms.txt` |

`llms.txt` is written at build time from `_data/cities.yml`, `_data/seasonal_hubs.yml`, and a line for `/worth-the-drive/`. Do not maintain it by hand.

There is no `/preview/nav/` page. The header is the wordmark on its own row, then Cities, Seasons, Guides, and Explore. A Menu button shows only when those four labels do not fit. The footer is About, Suggest an event, Partner with us, Request a city, and Feed.

## Map links

An event place and a playground address link to a Google Maps search (`https://www.google.com/maps/search/?api=1&query=`), built by `_plugins/map_links.rb` and the playground map script. Google works on every platform with no script. `_js/page.js` reads the query back from each `a.addr` link and points it at Apple Maps (`https://maps.apple.com/?q=`) on an iPhone, iPad, or Mac, unless a choice is saved. The footer's last row, "Open addresses in" with Apple Maps and Google Maps buttons, is hidden in the HTML. The script shows it only on a page with an address link. The pick is saved in `localStorage` as `map-app` and applies on every page. The card link stays the schema.org Place. Do not add a per-card menu or data attributes.

## Home and cities

The home page opens with the weekend picks, then a featured-article line, then the Eastside map. The page heading is "Things to do with kids on the Eastside". A seasonal banner, when one qualifies, sits under the header.

City URLs have no state segment and no year or week segment. Events stay in the order of the data file. The build groups each card into Today, Tomorrow, This week, This weekend, or Later from the first month and day on its gold date line. Empty groups are left out. If the Pacific date has moved past the build date, the browser moves the same cards into the current groups.

The home page count follows those cards, not every row in the data file. Each current event card carries its own event microdata. There is no visible breadcrumb. The JSON-LD graph still includes a BreadcrumbList for a city, hub, guide, or article page.

## Hubs

Seasonal hubs are generated from `_data/seasonal_hubs.yml`. Each hub stays up all year. A section appears only when it has something to list, except the spring break district dates, which stay on the page while that hub is in season. One banner under the masthead links to the hub that is in season and has enough upcoming events.

There is no `/halloween/` page. Halloween events are the `/fall/#halloween` section. Decorated houses are on `/fall/decorations/`. There is no `/holiday-lights/` page. Dated public light displays are events in the Holiday lights section of `/christmas/`. Homes and streets with Christmas lights are on `/christmas/lights/`.

Hub events are microdata on the shared cards. The page does not add an ItemList of those events. An ItemList in the JSON-LD graph is a guide's places or a map's pins.

`/worth-the-drive/` uses the same hub layout for a short list of family venues outside the 15 cities, within about an hour of Bellevue. Rows live only in `_data/worth_the_drive_events.yml`.

`/this-weekend/` is Friday through Sunday across the 15 cities. The home weekend block links to it. City pages do not.

## Explore pages

`/farmers-markets/` lists weekly markets from `_data/farmers_markets.yml`. The daily prune does not delete a row when the season ends. The build marks each card open or closed.

`/summer-camps/` lists day camps from `_data/summer_camps.yml`. The season year is the coming summer: next year after August. The build marks each sign-up line Open now, Opens on a date, or dates not posted yet.

`/book-ahead/` lists ticketed family events from `_data/book_ahead.yml`. The daily prune deletes a row whose last day is before today, and any row marked sold out. Summer camps are not listed.

`/articles/` lists evergreen guides. `/articles/free-things-to-do/` and `/articles/toddler-friendly-outings/` add matching events from the city files at build time.

`/no-school-days/` lists student no-school days for the ten Eastside districts. Rows live in `_data/no_school_days.yml`. The build hides a day whose end is before today. Each district has a feed at `/calendar/no-school/{id}.ics`.

## Schema

Every page carries one JSON-LD graph. The home page adds WebSite, Organization with the logo, and a Person. City, hub, guide, and article pages add a BreadcrumbList. Articles add Article markup. Event rich-result fields are microdata on the card, not a second event graph.
