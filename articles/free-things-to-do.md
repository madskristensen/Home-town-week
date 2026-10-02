---
layout: article
title: Free things to do with kids on the Eastside
description: Free things to do with kids in Bellevue, Kirkland, Redmond, and nearby Eastside towns. Parks, libraries, and upcoming free events.
intro: Places you can walk into for free, and the next free events on the city calendars.
article_id: free-things-to-do
permalink: /articles/free-things-to-do/
date: 2026-10-02
image: /assets/images/bellevue/botanical-garden.webp
image_alt: The entrance sign and plantings at Bellevue Botanical Garden.
places:
  - name: Bellevue Library
    blurb: Free to visit. Story times and a large children's area downtown.
    place: 1111 110th Ave NE
    city: Bellevue
    city_id: bellevue
    href: https://kcls.org/locations/bellevue/
    external: true
    image: /assets/images/bellevue/bellevue-library.webp
    alt: Bellevue Library, a glass and brick building with a covered walkway and trees in front.
    credit: "Photo: SuddenFrost, CC0"
    image_source: https://commons.wikimedia.org/wiki/File:Bellevue_Library.jpg
  - name: Kirkland Library
    blurb: Free to visit, with story times a short walk from downtown.
    place: 308 Kirkland Ave
    city: Kirkland
    city_id: kirkland
    href: https://kcls.org/locations/kirkland/
    external: true
    image: /assets/images/kirkland/kirkland-library.webp
    alt: Kirkland Library, a modern building with a glass and wood front and a covered entry.
    credit: "Photo: King County Library System."
    image_source: https://kcls.org/locations/kirkland/
  - name: Redmond Library
    blurb: Free to visit. Story times and indoor space in downtown Redmond.
    place: 15990 NE 85th St
    city: Redmond
    city_id: redmond
    href: https://kcls.org/locations/redmond/
    external: true
    image: /assets/images/redmond/redmond-library.webp
    alt: Redmond Library, a modern building with a glass front and a covered walkway.
    credit: "Photo: King County Library System."
    image_source: https://kcls.org/locations/redmond/
  - name: The Meadow at Bellevue Downtown Park
    blurb: A free downtown lawn and paths. No ticket to walk the park.
    place: 10201 NE 4th St
    city: Bellevue
    city_id: bellevue
    href: https://bellevuewa.gov/city-government/departments/parks/parks-and-trails/parks/bellevue-downtown-park
    external: true
    image: /assets/images/bellevue/downtown-park-meadow.webp
    alt: The circular lawn at Bellevue Downtown Park, with the downtown skyline beyond the water.
    credit: "Photo: Joe Mabel, CC BY-SA 3.0"
    image_source: https://commons.wikimedia.org/wiki/File:Bellevue_WA_-Downtown_Park_05A.jpg
  - name: Bellevue Botanical Garden
    blurb: Free to walk the gardens. The visitor center is on Main Street.
    place: 12001 Main St
    city: Bellevue
    city_id: bellevue
    href: https://bellevuebotanical.org/
    external: true
    image: /assets/images/bellevue/botanical-garden.webp
    alt: The entrance sign and plantings at Bellevue Botanical Garden.
    credit: "Photo: Heptazane, public domain"
    image_source: https://commons.wikimedia.org/wiki/File:Bellevue_Botanical_Garden_Entrance.jpg
  - name: Kelsey Creek Farm
    blurb: Admission and parking are free. Barn, animals, and trails.
    place: 410 130th Pl SE
    city: Bellevue
    city_id: bellevue
    href: https://bellevuewa.gov/city-government/departments/parks/community-centers/kelsey-creek-farm
    external: true
    image: /assets/images/bellevue/kelsey-creek.webp
    alt: Barn and pasture at Kelsey Creek Farm in Bellevue.
    credit: "Photo: Joe Mabel, CC BY-SA 3.0"
    image_source: https://commons.wikimedia.org/wiki/File:Kelsey_Creek_Farm_04.jpg
  - name: Marina Park
    blurb: A free waterfront park on Lake Washington in downtown Kirkland.
    place: 25 Lakeshore Plaza
    city: Kirkland
    city_id: kirkland
    href: https://www.kirklandwa.gov/Government/Departments/Parks-and-Community-Services/Find-a-Park/Marina-Park
    external: true
    image: /assets/images/kirkland/marina-fall.webp
    alt: Marina Park in fall, with yellow and orange trees along the shore of Lake Washington and the Seattle skyline across the water.
    credit: "Photo: City of Kirkland"
    image_source: https://www.kirklandwa.gov/Government/Departments/Parks-and-Community-Services/PCS-Photo-Galleries/Marina-Park-Photo-Gallery
---

A library card is free, and so is walking into a King County library. Bellevue Downtown Park, Bellevue Botanical Garden, Kelsey Creek Farm, and Marina Park do not charge admission to walk the grounds. Special events at those places sometimes do, and those prices stay on the event.

The city pages are where a dated free event shows up once the organizer posts it: [Bellevue](/bellevue/), [Kirkland](/kirkland/), [Redmond](/redmond/), and the rest of the [Eastside](/).

{% include card-grid.html events=page.places show_city=true eager=2 priority=true %}

{% assign free_count = page.free_events | size %}
{% if free_count > 0 %}
## Free events coming up

These are the next events tagged Free on the city calendars. The list changes as events are added and as they end.

{% include card-grid.html events=page.free_events show_city=true eager=0 %}
{% endif %}
