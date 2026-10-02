# Shared components

Card and page markup lives in one include each. Pages, layouts, and the city calendar plugin call those includes. Do not paste a second copy of the markup into a page or layout.

`script/check-components.py` runs in the Pages workflow after checkout. It fails the build when that markup shows up outside its include. The check reads `.html` and `.md` files only. It skips `_site`, `vendor`, `node_modules`, `.git`, and the image caches. CSS, Ruby, and Python are not scanned.

| Include | What it renders |
| --- | --- |
| `_includes/card-grid.html` | Every group of event cards. One `.card-grid` (one column on a phone, two from 42rem). Each item is `_includes/event-card.html`. Optional `heading` is a day bucket. `show_city` adds the town kicker. |
| `_includes/event-card.html` | Every event card. The same elements on home, city, hub, and explore pages: photo and credit, city label when a town is passed, date line, calendar and share actions, title, tags, place, and blurb. A dated card includes the share button. The card photo `sizes` value lives here. |
| `_includes/event-photo.html` | Photo and the credit strip. `figure` defaults to `event-photo`. |
| `_includes/filter-chip.html` | One filter chip. Event chips pass `group` and `value`. Playground chips pass `input_class`, `city`, `count`, or `amenity`, and do not pass `value`. |
| `_includes/page-intro.html` | The one-line introduction. Renders nothing when `text` is blank. |
| `_includes/empty-suggest.html` | Empty-state suggestion. The playground line links to `/playgrounds/`, with `?town=` on a city page. `mode="button"` renders only the Suggest an event or calendar link. `mode="line"` is the small muted mailto line on the missing page. |
| `_includes/playground-promo.html` | Compact playground card on a city page. Links to `/playgrounds/?town={id}`. |
| `_includes/playground-directory.html` | Playground list. The name line holds the star and the amenity badges. A legend under the heading uses the same badges. |
| `_includes/lights-feature.html` | Promo for the lights, decorations, or playgrounds map. `theme` picks the copy and the pin set. |
| `_includes/map-frame.html` | Map poster and canvas. Includes the shared loader unless `loader` is `false`. |
| `_includes/map-tip.html` | One short muted line. Under a lights or decorations map, pass `href` and the line is "Know a display we're missing? Tip us off." `kind="missing"` is "Missing something? Tell us." and uses the same Suggest an event mailto as the footer. Hub pages and explore pages include that line once, at the end of the article. The farmers market page does not also put a tip under the map. |
| `_includes/map-loader.html` | `loadMapCss` and `loadMapJs`. |
| `_includes/guide-header.html` | Playground page title and introduction. The heading links to `/playgrounds/`. |
| `_includes/calendar-subscribe.html` | Subscribe control. City pages use `/calendar/{city}.ics`. Pass `path` for another feed, such as `/calendar/no-school/{district}.ics`. |

The city plugin in `_plugins/event_calendar.rb` renders `card-grid.html` for each day bucket. That include renders `event-card.html`. The plugin still adds the calendar icon, the place link, and the source line before that render. Pass a page hash with `path` into Liquid registers. Do not pass the page object.

Each include starts with a Liquid comment that lists its parameters. Liquid comments are not in the built HTML.

## What the check catches

A file fails when it contains one of these outside the include that owns it:

- `class="card-grid"`
- `class="event-card`
- `class="event-photo"`
- `class="page-intro"`
- `class="empty-suggest` (the empty box and its button)
- `class="lights-feature`
- `class="map-frame"`
- `class="map-tip"`
- `class="filter-chip"`
- `class="cal-subscribe"`
- `class="event-share"`

`COMPONENTS.md` may name those strings. The bare word `event-card` is also allowed in `_includes/event-card.html`, `_includes/pwa.html` (the script selects `article.event-card` and `.event-card`), and `README.md`. An `{% include event-card.html %}` call is not markup and is allowed.

There is no `/dia-de-los-muertos/` hub and no redirect. Día de los Muertos events stay on city pages. Do not add the page back.
