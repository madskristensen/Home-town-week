# Eastside Family Calendar

This file is the content rules for the daily routine and for anyone editing events. The site is a Jekyll calendar at https://www.eastsidecalendar.com. GitHub Pages deploys from `main`.

## Family only

List events a parent would take a child to. Story times, parks, farms, markets, youth theater, teen hangouts, library programs, and drop-off kids' nights stay.

Leave out adult concerts, bar nights, brewery festivals, fitness classes for older adults, caregiver groups, parent-only workshops, English conversation hours, and 21+ events. Youth theater stays, including a teen or high-school cast. A paid camp or class series does not. A parents' night out where the kids stay and the adult leaves is family, and it gets `drop_off: true`.

## The 14 cities

Bellevue, Bothell, Carnation, Duvall, Issaquah, Kenmore, Kirkland, Mercer Island, North Bend, Redmond, Renton, Sammamish, Snoqualmie, and Woodinville. Fall City is part of the Snoqualmie page, not its own page. Newcastle has no page. Do not add Maple Valley.

Worth the Drive is a separate short list in `_data/worth_the_drive_events.yml` for family venues outside those 14 cities and within about an hour of Bellevue. It does not go on a city page or on the home weekend picks. Cross-listing one Eastside event onto another city's page is fine when the event is useful there. A name that says Seattle can still be an Eastside event when the place is here, such as a race at Marymoor Park.

## Location

Every row has to resolve to Washington and to the 14 cities, the nearby towns folded into them, or a Worth the Drive town. `script/check-event-areas.py` rejects the rest. The build fails on a reject. The daily prune removes rejects. An unresolved row is logged and kept. A street direction such as Ave NE is not a state.

## Write both places

An event is a `###` heading on `{city}/index.md` and a row in `_data/{city}_events.yml`. The heading, the date line (`<p class="event-when">`), the place line, the blurb, and a source link live on the city page. The row has `name`, `start`, `end`, `place`, `same_as`, and any labels. There are no individual event pages. Each dated card has a share button. It sends the title, when, place, and a short blurb. The phone share sheet attaches the source link by itself. A desktop copy pastes that note as text and as simple HTML, and the HTML links the source and the city page. The blurb stops after a sentence or two, keeps Free or the price when that fits, and leaves out phone numbers and email addresses. It does not send a page on this site as the main link.

A data row with no matching city-page event is an orphan. Delete it. The build fails if a new one appears. Hub pages skip a row that has no real blurb. Do not invent a filler such as "Name in Mercer Island."

## Blurbs

Write the blurb in our own words: what it is, who it is for, and any cost or registration a parent needs. Link the source. Do not quote a calendar against itself, and do not point at another listing. No em dashes. En dashes in a time range are fine.

`script/check-events.py` checks required fields, ISO dates, end on or after start, cost of `Free` or `$...`, ages and setting labels, a place, an http source, a date line and source link on each city event, a match between the city page and the data row, and em dashes. It fails on new errors only. Adult-only wording and same-day near-duplicate names are warnings.

## Tags

Labels are `cost`, `ages`, `setting`, `drop_off`, `signup`, and `sensory`. Seasonal words stay in `tags`.

Free is the only cost pill. A price is plain text. All ages is plain text. Never a price pill and never an All ages pill. A `free` tag with no price is the Free pill.

Toddlers means aimed at under 5: ages 0-3, 1 to 3, 18 months, babies, toddlers, preschool, under 5, lap sit, baby story time. Ages 5 and older is not Toddlers. Do not guess All ages.

Kids and Teens chips appear only when a page has at least three. The Toddlers chip appears whenever a card has it.

Setting is Indoor or Outdoor, not both. Library, museum, theater, and community center events are Indoor unless the page says outdoors, stroll, hike, parade, or market. A farmers market is Outdoor. If the page says both, leave setting off. `_data/venue_settings.yml` fills a blank setting. The longest place name wins. `script/apply-venue-settings.py` runs in the Pages build before Jekyll and again in the daily prune, so city pages and hubs show the same tags on the day the event is added.

Drop-off is only when the child stays and the adult leaves. Camps are not drop-off. Signup is when registration or tickets are required, not when the page says registration is not required. Sensory is only when the page says sensory-friendly or low-sensory.

## Photos

Order for a hub card: the event's own photo (the organizer page, og:image, or flyer), then a photo of that specific venue, then a themed picture, then the seasonal pool, then the year-round pool in `_data/hub_pools.yml`. A grid card with no image fails the build. Do not use a designed card.

Always look for the event's own photo or the venue's own photo before a theme or pool picture. Prefer CC0, CC BY, CC BY-SA, or public domain when one exists. If no licensed photo exists, use the organizer's or venue's own photo anyway. Credit it as `Photo: <organizer or site name>`, link the source page, and set `license: organizer` (on the venue row, or `license="organizer"` on the event-photo include). A show poster or key art from the organizer counts as the event's own image. Credit that `Image: <organizer>`, with the same organizer marker and a link. A photo with a credit and a source link passes when it has an open license or that organizer marker. Do not drop an organizer photo only because it is unlicensed.

No recognizable kids or teens. Removed on request. A venue key must name that place. "crossroads" is the mall (`crossroads mall`, `crossroads bellevue`), not Crossroads Community Center. The longest key wins.

## What the daily prune does

`.github/workflows/prune.yml` runs at 09:00 UTC. It rebases onto main before pushing. It drops out-of-area rows, fills venue labels, and deletes events whose last day is before today in America/Los_Angeles. An explicit year is that year. Otherwise use the matching data row, or the next future occurrence. Do not delete a far-future youth theater show because the month and day look like last year.

The browser hides a card whose end date is before today, so yesterday's cards do not sit on the page until the next build. The Pages rebuild that follows writes `/calendar/{city}.ics` from the events still on each city page.

## Cultural holidays

Diwali, Lunar New Year, Día de los Muertos, Hanukkah, and Eid need a targeted search about six weeks before the date. City calendars and the library feeds often leave them off until someone looks. The Monday fill, the Thursday fill, and the first-Friday source review should use the city source list and those searches. Tag a Diwali row `diwali`. The hub runs from Oct 15 through Nov 15.

## Weekend picks

`/this-weekend/` is Friday through Sunday across the 14 cities. The home page shows a short pick of that list. Keep both in step with the city pages. Worth the Drive stays off that list.

## Cards

Grouped cards always use `_includes/card-grid.html`. It renders each item with `_includes/event-card.html` inside one grid. Home, city day buckets, seasonal hubs, this weekend, worth the drive, rainy day, lights lists, and explore pages all use that include. Do not add another grid class or a page-specific wrapper. The daily prune and content edits must not paste card markup.

## Dedupe

One event, one row. Two sessions at different times can both stay when the page lists both. A second row with the same time and a near-duplicate name should be removed. The event check warns on same-day near-duplicates.
