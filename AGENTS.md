# Eastside Family Calendar

This file is the content rules for the daily routine and for anyone editing events. The site is a Jekyll calendar at https://www.eastsidecalendar.com. GitHub Pages deploys from `main`.

## Family only

List events a parent would take a child to. Story times, parks, farms, markets, youth theater, teen hangouts, library programs, and drop-off kids' nights stay.

Leave out adult concerts, bar nights, brewery festivals, fitness classes for older adults, caregiver groups, parent-only workshops, English conversation hours, and 21+ events. Youth theater stays, including a teen or high-school cast. A paid camp or class series does not. A parents' night out where the kids stay and the adult leaves is family, and it gets `drop_off: true`.

## The 15 cities

Bellevue, Bothell, Carnation, Duvall, Issaquah, Kenmore, Kirkland, Maple Valley, Mercer Island, North Bend, Redmond, Renton, Sammamish, Snoqualmie, and Woodinville. Fall City is part of the Snoqualmie page, not its own page. Covington is part of the Maple Valley page, not its own page. Newcastle has no page.

Worth the Drive is a separate short list in `_data/worth_the_drive_events.yml` for family venues outside those 15 cities and within about an hour of Bellevue. It does not go on a city page or on the home weekend picks. Cross-listing one Eastside event onto another city's page is fine when the event is useful there. A name that says Seattle can still be an Eastside event when the place is here, such as a race at Marymoor Park.

## Location

Every row has to resolve to Washington and to the 15 cities, the nearby towns folded into them, or a Worth the Drive town. `script/check-event-areas.py` rejects the rest. The build fails on a reject. The daily prune removes rejects. An unresolved row is logged and kept. A street direction such as Ave NE is not a state.

## Write both places

An event is a `###` heading on `{city}/index.md` and a row in `_data/{city}_events.yml`. The heading, the date line (`<p class="event-when">`), the place line, the blurb, and a source link live on the city page. The row has `name`, `start`, `end`, `place`, `same_as`, and any labels. There are no individual event pages. Each event row gets `href` and `external` when it is built: `same_as` when that is a webpage, otherwise `/city/#slug`. Aggregate cards use that href. The town name links to the city page. A city page card keeps the source link under the blurb. Each dated card has a share button. It sends the title, when, place, and a short blurb. The phone share sheet attaches the source link by itself. A desktop copy pastes that note as text and as simple HTML, and the HTML links the source and the city page. The blurb stops after a sentence or two, keeps Free or the price when that fits, and leaves out phone numbers and email addresses. It does not send a page on this site as the main link.

A data row with no matching city-page event is an orphan. Delete it. The build fails if a new one appears. Hub pages skip a row that has no real blurb. Do not invent a filler such as "Name in Mercer Island."

## Blurbs

Write the blurb in our own words: what it is, who it is for, and any cost or registration a parent needs. Link the source. Do not quote a calendar against itself, and do not point at another listing. No em dashes. En dashes in a time range are fine.

`script/check-events.py` checks required fields, ISO dates, end on or after start, cost of `Free` or `$...`, ages and setting labels, a place, an http source, a date line and source link on each city event, a match between the city page and the data row, and em dashes. It fails on new errors only. Adult-only wording and same-day near-duplicate names are warnings.

## Tags

Labels are `cost`, `ages`, `setting`, `drop_off`, `signup`, and `sensory`. Seasonal words stay in `tags`. Set `organizer` and `organizer_url` when the host is not the source site. Set `performer` only when the source names that person. The build fills the other organizers from the source site.

Free is the only cost pill. A price is plain text. All ages is plain text. Never a price pill and never an All ages pill. A `free` tag with no price is the Free pill.

Toddlers means aimed at under 5: ages 0-3, 1 to 3, 18 months, babies, toddlers, preschool, under 5, lap sit, baby story time. Ages 5 and older is not Toddlers. Do not guess All ages.

Kids and Teens chips appear only when a page has at least three. The Toddlers chip appears whenever a card has it.

Setting is Indoor or Outdoor, not both. Library, museum, theater, and community center events are Indoor unless the page says outdoors, stroll, hike, parade, or market. A farmers market is Outdoor. If the page says both, leave setting off. `_data/venue_settings.yml` fills a blank setting. The longest place name wins. `script/apply-venue-settings.py` runs in the Pages build before Jekyll and again in the daily prune, so city pages and hubs show the same tags on the day the event is added.

Drop-off is only when the child stays and the adult leaves. Camps are not drop-off. Signup is when registration or tickets are required, not when the page says registration is not required. Sensory is only when the page says sensory-friendly or low-sensory.

## Photos

Leave existing photo files untouched. Before committing a new photo, run `python3 script/cap-master.py` on that file. The long side is capped at 1600px, or 2000px when the path is a city hero in `_data/cities.yml`. The file stays WebP, JPEG, or PNG. The Pages build warns if that new master is still over the cap. It does not rewrite the file.

Order for a hub card: the event's own photo (the organizer page, og:image, or flyer), then a photo of that specific venue, then a themed picture, then the seasonal pool, then the year-round pool in `_data/hub_pools.yml`. A grid card with no image fails the build. Do not use a designed card.

Always look for the event's own photo or the venue's own photo before a theme or pool picture. Prefer CC0, CC BY, CC BY-SA, or public domain when one exists. If no licensed photo exists, use the organizer's or venue's own photo anyway. Credit it as `Photo: <organizer or site name>`, link the source page, and set `license: organizer` (on the venue row, or `license="organizer"` on the event-photo include). A show poster or key art from the organizer counts as the event's own image. Credit that `Image: <organizer>`, with the same organizer marker and a link. A photo with a credit and a source link passes when it has an open license or that organizer marker. Do not drop an organizer photo only because it is unlicensed.

No recognizable kids or teens. Removed on request. A venue key must name that place. "crossroads" is the mall (`crossroads mall`, `crossroads bellevue`), not Crossroads Community Center. The longest key wins.

## What the daily prune does

`.github/workflows/prune.yml` runs at 09:00 UTC. It rebases onto main before pushing. It drops out-of-area rows, fills venue labels, and deletes events whose last day is before today in America/Los_Angeles. An explicit year is that year. Otherwise use the matching data row, or the next future occurrence. Do not delete a far-future youth theater show because the month and day look like last year.

The browser hides a card whose end date is before today, so yesterday's cards do not sit on the page until the next build. The Pages rebuild that follows writes `/calendar/{city}.ics` from the events still on each city page. Subscribe to this calendar stays under the updated line. The city Atom feed stays in the head as `link rel=alternate`. The visible link is a small "RSS feed" beside Suggest an event, at the bottom of the list, not under Upcoming.

## Cultural holidays

Diwali, Lunar New Year, Día de los Muertos, Hanukkah, and Eid need a targeted search about six weeks before the date. City calendars and the library feeds often leave them off until someone looks. The Monday fill, the Thursday fill, and the first-Friday source review should use the city source list and those searches. Tag a Diwali row `diwali`. The hub runs from Oct 15 through Nov 15.

There is no `/dia-de-los-muertos/` hub and no redirect. Día de los Muertos events stay on their city pages. Do not add the page back. Keep Día de los Muertos in the cultural-holiday search above.

There is no `/winter/` hub and no redirect. Winter events stay on their city pages. Do not add the page back. The Christmas hub stays.

## Friday source hunt

Each Friday, scan the lead sites for about the next six weeks. The Yodel embed needs a headless browser. For a new organizer or event in the 15 cities, verify it on the organizer's own page. Add a verified event with the organizer as the source link. Add a good organizer to `sources` in `_data/cities.yml`. Never link a lead site, and never copy its text. Skip a sponsored or paid listing unless the organizer's own page shows it is a real free or family event. Expect a lead site's clock to be off by an hour.

### Lead sites (never cite or link)

- https://the-eastside.macaronikid.com/ covers Redmond, Kirkland, Bothell, and Woodinville.
- https://rentonwa.macaronikid.com/ covers Renton and Bellevue.
- https://snoqualmievalley.macaronikid.com/ covers the Snoqualmie Valley, Issaquah, and Sammamish.
- https://cherryvalley.macaronikid.com/ covers Monroe, Duvall, and Carnation.
- https://www.parentmap.com/ covers all 15 cities. No JavaScript. Use The Events Calendar API, for example /wp-json/tribe/events/v1/events?start_date=...&end_date=...&per_page=50&page=N, or /wp-json/wp/v2/tribe_events?event_region=39 for the Eastside. Send a normal browser user-agent. Plain curl gets a 403. Wait between pages. robots.txt disallows filtered /calendar? URLs, so use the API. Skip business self-submissions such as paid classes, school open houses, and gyms.
- https://www.seattleschild.com/ is seasonal guides only. Check it monthly, on the first Friday of each month. Never link it, and never copy it. Use the WordPress posts API, /wp-json/wp/v2/posts, for the guides. The calendar adds little beyond ParentMap, and robots.txt blocks /calendar/page/*. Skip sponsored posts, directories, and camps. Useful timing: a Halloween roundup in mid-September, fun runs and turkey trots in September and October, holiday trains in September, and a volunteer list each month.

## Weekend picks

`/this-weekend/` is Friday through Sunday across the 15 cities. The home page shows a short pick of that list. Keep both in step with the city pages. Worth the Drive stays off that list.

## Cards

Grouped cards always use `_includes/card-grid.html`. It renders each item with `_includes/event-card.html` inside one grid. Home, city day buckets, seasonal hubs, this weekend, worth the drive, rainy day, lights lists, explore pages, and articles all use that include. Do not add another grid class or a page-specific wrapper. The daily prune and content edits must not paste card markup.

## Articles

`/articles/` lists evergreen guides. Each guide is its own page and uses the same card grid. The guides are Halloween with kids, Christmas lights, meeting Santa, winter break, New Year's Eve, snow play, rainy-day indoor places, free things to do with kids, salmon spawning, no-school day ideas, toddler outings, starred playgrounds, birthday party places, and easy hikes. `/fall/bucket-list/` is the printable fall checklist. Each row is a label: the checkbox, then one span. The sentence and its link stay inline inside that span. The label is a two-column grid, checkbox then text. A checked row is muted and struck through. The salmon spotting list uses that same row. There is no winter, summer, or spring bucket list. The salmon article includes a printable spotting checklist. The free guide adds the next Free-tagged events from the city files at build time. The toddler guide does the same for events tagged Toddlers. The playground guide is built from the starred playgrounds and opens with the playgrounds map card. Link the organizer's own page. Use a real licensed or credited photo of that place. Do not cite a lead site. No em dashes. The footer Explore group links Articles. The header does not.

## Seasonal banner

The home page shows one seasonal banner, chosen when the site builds. It is the hub in `_data/seasonal_hubs.yml` that is in season, has at least 6 upcoming events from at least 3 towns, and has a theme drawing. If several hubs qualify, the one whose season ends soonest is the banner. If none qualify, there is no banner.

The home page opens with the weekend picks, then one featured-article line, then the town map. A small Pick your town link under the intro jumps to that map. The line is muted text with an arrow, and it has no background. It is not a second banner. The rows are `_data/featured_articles.yml`. A window is a month and day that repeats each year. Today is America/Los_Angeles. When more than one window contains today, the one that started most recently is used. The ISO week picks one line from that window, so the daily rebuild changes it on Monday. A line is shown only when `articles/{article}.md` exists. March through September uses the fallback, free things to do. No em dashes.

The newsletter is one weekly Thursday email for the whole Eastside, not one per city. `_includes/newsletter.html` is a plain form that posts to the Buttondown list `madskristensen` with the tag `website`, and it stays in this tab. There is no script on the form. It sits once at the end of main, just above the footer rule: "Weekend picks by email, every Thursday", the email field and a solid Subscribe button on one row at every width, and "One email a week. Unsubscribe anytime." Subscribe uses the shared solid button. It is not in the footer, and the home page does not repeat it under the weekend list. No popup, no modal, and no filled box. Print styles hide it. After the form, `/subscribed/` asks them to confirm the note from hello@news.eastsidecalendar.com, and `/confirmed/` welcomes them to the Thursday email. Both use the default layout, say `noindex,follow`, set `sitemap: false`, and stay out of the header, the footer, and `llms.txt`. Do not add them to a menu. Do not change the form action, the hidden tag, or the Buttondown account. The redirect URLs are set in Buttondown. Buttondown adds `email_address` to the query string. The head of `/subscribed/` and `/confirmed/` drops that query with `history.replaceState` before the style sheets, and sets the referrer to the origin. Do not print the query string, and do not send it on.

The missing page uses that same choice for its seasonal tile. `404.html` does not name a season. The build in `_plugins/seasonal_hubs.rb` makes four tiles: This weekend, the current banner hub, Playgrounds, and Farmers markets. The banner tile's title, line, and photo come from that hub's `banner_title`, `hook`, and the share card with the same path. Switching the banner to Christmas switches that tile to Christmas for kids, with the Christmas share photo and the hook "Tree lightings, lights, Santa, and shows." Nothing on the missing page is edited by hand for that change. A hub can fill the tile only when `_data/share_cards.yml` has a card for its path. Every current hub has one. A new hub needs that share card, or the seasonal tile is left off.

## Farmers markets

`/farmers-markets/` is the farmers market list for the 15 cities. The rows are `_data/farmers_markets.yml`. Do not put them in a city events file. The daily prune does not delete a market when its season ends. The build compares `season_start`, `season_end`, and `extra_dates` with today in America/Los_Angeles and writes Open now or the return line on the card. When a market posts new hours or the next season, update that row. Leave the row in place out of season. Bothell has no weekly market to list until a city or market site publishes one. Photos are CC0, CC BY, CC BY-SA, or public domain, or an organizer photo credited `Photo: <name>` with `license: organizer`. No recognizable kids. Blurbs are our own words. No em dashes.

## Book ahead

`/book-ahead/` lists popular ticketed family events in the 15 cities that sell out and need a booking weeks ahead. The rows are `_data/book_ahead.yml`. Do not put them in a city events file. Do not add summer camps. A popular ticketed family event in spring or summer belongs here once the organizer posts it. Remlinger Farms has not posted a 2026 holiday ticketed event. Add that row when they do. Snowflake Lane is free, so it stays off this page.

Each row needs a name, city id, address, start, end, a date phrase in `when`, the ticket URL in `source`, a blurb, and a real photo. Price stays in the blurb as plain text. Do not set `cost`. That field becomes a price tag. `ticket_line` is the date-line sentence when tickets are not simply on sale, such as "Tickets go on sale soon." `tickets_on` is the sale date. When that date is still ahead, the card says tickets go on sale that day. Otherwise the card says tickets are on sale now. When the organizer says an event is sold out, set `sold_out: true` or delete the row. The daily prune deletes a sold-out row and a row whose end is before today in America/Los_Angeles. The build also leaves those rows off the page. Verify dates, price, and ticket status on the organizer's ticket page. Photos are CC0, CC BY, CC BY-SA, or public domain, or an organizer photo credited `Photo: <name>` with `license: organizer`. No recognizable kids. Blurbs are our own words. No em dashes.

## Summer camps

`/summer-camps/` lists day camps for summer 2027. The rows are `_data/summer_camps.yml`. Do not put them in a city events file. Do not add a camp card to a city page. The Seasons menu lists the page. There is no summer banner yet.

The build compares `reg_on` and `signup_open` with today in America/Los_Angeles. A row is three short lines: the camp name, then ages, day length, and town, then Open now, Sign-up opens Jan 19, or 2027 dates not posted yet (mid-March 2026). Omit ages when the camp did not list them. Do not put the type, the street address, or a notes paragraph on the row. `confirmed_2027` is only for a fact on the camp's own site. Price is plain text. Do not set `cost`. No recognizable kids. No em dashes. Day camps only. Skip church camps. SAMBICA's day camp stays because its 2027 registration date is posted. Newcastle and Preston can be listed. A chain such as Skyhawks gets a basic row.

Paid spots live in `_data/sponsors.yml`. Leave a name blank and that spot stays off the site. Do not put an example business in that file. The partner page previews use the same includes with names such as Example Swim School, and each preview is marked Example. `seasons.summer-camps` is the "Sponsored by" line on `/summer-camps/`. `listings` are enhanced camp rows: labeled Sponsored, with a photo and a short description, pinned at the top of that town. Grouping by age keeps the row at the top of that age. Grouping by type keeps it at the top of that type. It is not added to a sign-up group. `seasons.christmas` is the line and optional card on `/christmas/` and `/christmas/lights/`. `seasons.fall` covers `/fall/` and `/fall/decorations/`. `seasons.spring-break` covers `/spring-break/`. `cards.weekend` is pinned at the front of the weekend picks and on This weekend. `cards.cities` is the card near the top of that city page. `email` is the one labeled line in the Thursday email, not a line on the website.

The page is one list. It is grouped by town, with an anchor for each town such as `#bellevue`, and that list is in the HTML so it works with no JavaScript. A Group by row of buttons can switch the same rows to type, sign-up, or age. Within a group, rows are sorted by sign-up date, soonest first, then by name. A camp that fits several ages shows under each of those ages. There is no second list, no start-here cards, and no filter chips. A featured row can still carry a venue photo in the data file. The page does not show it.

## School calendars

`/no-school-days/` lists student no-school days for the ten Eastside districts in the 2026-27 year. The rows are `_data/no_school_days.yml`. Do not put them in a city events file. The spring break hub reads its April dates from the `break` rows in that file. Do not copy those dates back into `_data/seasonal_hubs.yml`.

The page is month calendars from the current month through June, in the same content column as the other pages. Two months sit side by side on a wide screen and one on a phone. A week with no days is left out, and the two months in a row stay the same height. The grid height does not change when the district changes. The district menu, subscribe button, hint, and weekly sentence sit in one panel. The legend is a small line above the months. The district `select` lists the ten districts and nothing else. With no `?district=` and nothing saved, the page shows Lake Washington and the line "Showing Lake Washington. Pick your district and we'll remember it." Choosing a district, or arriving with a saved one, hides that line. `?district=` wins and is saved. Otherwise a saved `no-school-district` value is used and written into the address. The head script sets `data-ns` before paint. The HTML also shows Lake Washington when that attribute is missing, so the first paint matches. Each district needs `slug` and a matching `html[data-ns]` rule in `_css/site.css`. Day cells use text and a neutral border: filled, outlined, or dashed. The day cell's title is the reason. More than one reason on the same day is separated by a new line. Do not add district colors. Do not add event cards to this page. Nothing sits below the last month except the usual footer note.

The daily prune does not delete a day when it passes. The build hides a row whose end is before today in America/Los_Angeles. `weekly` is the one sentence above the calendar for that district's regular early release or late start. One-off early release, half days, and first and last days are rows with `off: false`.

In late summer, load the next school year's calendars from each district's stable link. That is `stable` when it is set, and `source` when `source` is the resource-manager link. Replace that district's `days` and set `pdf` to the file name the link downloads. Run `python3 script/check-district-calendars.py`. It warns, and does not fail the build, when a stable link starts pointing at a new PDF.

In January and February, check the same links for snow make-up changes. A day with `conditional: true` is off unless the district uses it as a make-up day. After the trigger date named in `note`, either drop `conditional` or delete the row, matching what the district posted.

`type` is `holiday`, `teacher`, `conferences`, `break`, `snow`, `first`, `last`, `half`, or `early`. Set `grades` when the day is not for every student, for example `Grades 6-8 only` or `Elementary only`. Per-district feeds are `/calendar/no-school/{id}.ics`. Do not use `/calendar/{city}.ics` for these. That path is the city event feed.

## Navigation preview

The live header is two rows. The wordmark is its own row and is not cut off. Cities, Seasons, Guides, and Explore are a bar under that row wherever the four labels fit, and a single Menu button only when they do not. Cities lists This weekend and the 15 cities. Seasons lists Fall, Halloween, Christmas, Winter break, Spring break, Summer camps, and Worth the drive, and only when that hub exists. Halloween is the Halloween section of Fall. Guides lists the articles in season today (about five), then School calendars, bucket lists in season, and All guides last. All guides links to `/articles/`. Those dates live in `_data/featured_articles.yml` under `guides` and are read on the daily rebuild. Rainy-day indoor play and free things to do are eligible every day. Explore lists Christmas lights map, Halloween decorations map, Playgrounds, Farmers markets, and Book ahead. Worth the drive and This weekend stay in Seasons and Cities. School calendars stays in Guides. The footer is one quiet row: About, Suggest an event, Partner with us, Request a city, and Feed, plus the install link when Chrome, Edge, or Android offers it, and on iOS Safari as Install app, and the family credit. Suggest an event links to `/suggest/`. It is not a menu. The newsletter stays above the footer rule. There is no `/preview/nav/` page.

## Dedupe

One event, one row. Two sessions at different times can both stay when the page lists both. A second row with the same time and a near-duplicate name should be removed. The event check warns on same-day near-duplicates.
