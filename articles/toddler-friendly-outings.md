---
layout: article
title: Toddler-friendly outings on the Eastside
description: Short outings for toddlers on the Eastside, from tot lots and libraries to programs for kids under 5.
intro: Keep it short. A tot lot, a library, or the farm, and a way to leave when everyone is done.
article_id: toddler-friendly-outings
permalink: /articles/toddler-friendly-outings/
date: 2026-10-02
image: /assets/images/guides/crossroads.jpg
image_alt: Play structure and slides at Crossroads Park in Bellevue.
places:
  - name: Inspiration Playground
    blurb: The tot lot is for ages 2 to 5, in Downtown Park, with parking close by.
    place: 10201 NE 4th St
    city: Bellevue
    city_id: bellevue
    href: https://bellevuewa.gov/city-government/departments/parks/parks-and-trails/parks/bellevue-downtown-park
    external: true
    image: /assets/images/guides/inspiration.jpg
    alt: Play structure with slides and climbing nets at Inspiration Playground in Bellevue Downtown Park.
    credit: "Photo: City of Bellevue"
    image_source: https://bellevuewa.gov/city-government/departments/parks/parks-and-trails/parks/bellevue-downtown-park
  - name: Crossroads Park
    blurb: A tot lot for ages 2 to 5, next to the bigger playground.
    place: 999 164th Ave NE
    city: Bellevue
    city_id: bellevue
    href: https://bellevuewa.gov/city-government/departments/parks/parks-and-trails/parks/crossroads-park
    external: true
    image: /assets/images/guides/crossroads.jpg
    alt: Play structure and slides at Crossroads Park in Bellevue.
    credit: "Photo: City of Bellevue"
    image_source: https://bellevuewa.gov/city-government/departments/parks/parks-and-trails/parks/crossroads-park
  - name: KidsQuest Children's Museum
    blurb: Indoor exhibits for younger kids, next to Bellevue Library.
    place: 1116 108th Ave NE
    city: Bellevue
    city_id: bellevue
    href: https://www.kidsquestmuseum.org/
    external: true
    image: /assets/images/bellevue/kidsquest.webp
    alt: Front of KidsQuest Children's Museum in downtown Bellevue, with the museum sign over the entrance.
    credit: "Photo: Julian Fong, CC BY-SA 4.0"
    image_source: https://commons.wikimedia.org/wiki/File:KidsQuest_Children%27s_Museum_2.jpg
  - name: Bellevue Library
    blurb: Story times and a children's area you can roll a stroller into.
    place: 1111 110th Ave NE
    city: Bellevue
    city_id: bellevue
    href: https://kcls.org/locations/bellevue/
    external: true
    image: /assets/images/bellevue/bellevue-library.webp
    alt: Bellevue Library, a glass and brick building with a covered walkway and trees in front.
    credit: "Photo: SuddenFrost, CC0"
    image_source: https://commons.wikimedia.org/wiki/File:Bellevue_Library.jpg
  - name: Bellevue Botanical Garden
    blurb: A short walk through the gardens on Main Street.
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
    blurb: Admission and parking are free. A barn, animals, and short paths.
    place: 410 130th Pl SE
    city: Bellevue
    city_id: bellevue
    href: https://bellevuewa.gov/city-government/departments/parks/community-centers/kelsey-creek-farm
    external: true
    image: /assets/images/bellevue/kelsey-creek.webp
    alt: Barn and pasture at Kelsey Creek Farm in Bellevue.
    credit: "Photo: Joe Mabel, CC BY-SA 3.0"
    image_source: https://commons.wikimedia.org/wiki/File:Kelsey_Creek_Farm_04.jpg
---

The tot lots at [Inspiration Playground](https://bellevuewa.gov/city-government/departments/parks/parks-and-trails/parks/bellevue-downtown-park) and [Crossroads Park](https://bellevuewa.gov/city-government/departments/parks/parks-and-trails/parks/crossroads-park) are for ages 2 to 5, with a bigger playground beside each one and parking close to the play area. When it rains, KidsQuest and Bellevue Library are the same kind of short trip. More playgrounds are on the [playgrounds map](/playgrounds/).

[KidsQuest Children's Museum](https://www.kidsquestmuseum.org/) at 1116 108th Ave NE is indoor and built for younger kids. [Bellevue Library](https://kcls.org/locations/bellevue/) next door is free to walk into. [Kelsey Creek Farm](https://bellevuewa.gov/city-government/departments/parks/community-centers/kelsey-creek-farm) does not charge admission or parking. [Bellevue Botanical Garden](https://bellevuebotanical.org/) is a short walk, not a hike.

Programs for kids under 5 are listed below when one is coming up.

{% include card-grid.html events=page.places show_city=true eager=2 priority=true %}

{% assign toddler_count = page.toddler_events | size %}
{% if toddler_count > 0 %}
## Toddler events coming up

Story times and other programs for little kids. The list changes as they end.

{% include card-grid.html events=page.toddler_events show_city=true eager=0 %}
{% endif %}
