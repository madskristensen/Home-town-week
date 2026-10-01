# Shared components

Card and page markup lives in one include each. Pages, layouts, and the city calendar plugin call those includes. Do not paste a second copy of the markup into a page or layout.

`script/check-components.py` runs in the Pages workflow after checkout. It fails the build when that markup shows up outside its include. The check reads `.html` and `.md` files only. It skips `_site`, `vendor`, `node_modules`, `.git`, and the image caches. CSS, Ruby, and Python are not scanned.

| Include | What it renders |
| --- | --- |
| `_includes/event-card.html` | Every event card. `layout` is blank for a city stack, `tile` for hubs, lights, and decorations, and `weekend` for the home weekend picks. The weekend photo sits outside the link. |
| `_includes/event-photo.html` | Photo and the credit strip. `figure` defaults to `event-photo`. Home weekend picks pass `weekend-photo`. |
| `_includes/filter-chip.html` | One filter chip. Event chips pass `group` and `value`. Playground chips pass `input_class`, `city`, `count`, or `amenity`, and do not pass `value`. |
| `_includes/page-intro.html` | The one-line introduction. Renders nothing when `text` is blank. |
| `_includes/empty-suggest.html` | Empty-state suggestion. The playground line links to `/playgrounds/`, with `?town=` on a city page. |
| `_includes/playground-promo.html` | Compact playground card on a city page. Links to `/playgrounds/?town={id}`. |
| `_includes/lights-feature.html` | Seasonal promo for the lights or decorations map. |
| `_includes/map-frame.html` | Map poster and canvas. Includes the shared loader unless `loader` is `false`. |
| `_includes/map-loader.html` | `loadMapCss` and `loadMapJs`. |
| `_includes/guide-header.html` | Playground page title and introduction. The heading links to `/playgrounds/`. |

The city plugin in `_plugins/event_calendar.rb` renders `event-card.html` for each city card. It still adds the calendar icon, the place link, and the source line before that render. Pass a page hash with `path` into Liquid registers. Do not pass the page object.

Each include starts with a Liquid comment that lists its parameters. Liquid comments are not in the built HTML.

## What the check catches

A file fails when it contains one of these outside the include that owns it:

- `class="event-card` (city cards, tiles, and weekend cards)
- `weekend-card`
- `event-card--tile`
- `class="event-photo"`
- `class="weekend-photo"`
- `class="page-intro"`
- `class="empty-suggest` (the empty box and its button)
- `class="lights-feature`
- `class="map-frame"`
- `class="filter-chip"`

`COMPONENTS.md` may name those strings. The bare word `event-card` is also allowed in `_includes/event-card.html`, `_includes/pwa.html` (the script selects `article.event-card` and `.event-card`), and `README.md`. An `{% include event-card.html %}` call is not markup and is allowed.
