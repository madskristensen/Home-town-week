---
title: "Sunday market on Wetmore"
description: "The Everett Farmers Market, the library, and the waterfront, Sept. 21 – 27, 2026."
date: 2026-09-21
end_date: "2026-09-27"
city: everett
state: wa
year: 2026
slug: sep-21-sep-27
range: "Sept. 21 – 27, 2026"
hook: "Sunday is the farmers market on Wetmore. The rest of the week is the library and the waterfront. No second museum special is posted."
permalink: /wa/everett/2026/sep-21-sep-27/
image: /assets/images/everett/everett-library.webp
image_alt: "The Everett Public Library, a brick building with a columned entrance."
image_credit: "Photo: Joe Mabel, CC BY-SA 3.0"
image_source_url: "https://commons.wikimedia.org/wiki/File:Everett_Library_01.jpg"
---

Sunday is the farmers market on Wetmore. The rest of the week is the library and the waterfront. No second museum special is posted.

## Sunday

### Everett Farmers Market
<p class="event-when">Sun Sep 27 · 10:30 a.m.–3:00 p.m.</p>
<p class="event-place">Wetmore Ave between Hewitt and Pacific</p>

Same Sunday stall row as last week, and through the end of October. The city building at 2930 Wetmore Ave is the landmark. Food is at the market. That is the meal plan, not a separate restaurant special.

[Everett Farmers Market](https://everettfarmersmarket.com/) · [Live in Everett](https://www.liveineverett.com/cal)

## The rest of the week

### Everett Public Library
<p class="event-when">Open hours</p>
<p class="event-place">2702 Hoyt Ave</p>

{% include event-photo.html
   src="/assets/images/everett/everett-library.webp"
   alt="The Everett Public Library, a brick building with a columned entrance."
   credit="Photo: Joe Mabel, CC BY-SA 3.0"
   source="https://commons.wikimedia.org/wiki/File:Everett_Library_01.jpg" %}

No storytime inside this Monday–Sunday span was confirmed on the library pages checked for this issue. The branch calendar is the list if a session was added after this was written. The Evergreen Branch is the other city library. Hours for both are on the library site.

[Everett Public Library](https://www.epls.org/)

### Imagine Children's Museum
<p class="event-when">Regular floor hours</p>
<p class="event-place">1502 Wall St</p>

Community Access Night was Thursday, Sep 17. Sensory Time was Sunday, Sep 20. Neither repeats this week. A regular visit is paid admission, not the pay-what-you-can night. Check the day's hours before you go. The next Sensory Time on the third-Sunday pattern would be Oct 18.

[Imagine Children's Museum](https://www.imaginecm.org/)

## Waterfront

The Waterfront Center and the marina path are the open outing if the market is the only timed plan. Jetty Island's foot-ferry season is a summer schedule and should not be assumed in late September. Confirm with the city before you count on a boat.

I used waterfront.webp but I downloaded everett images as imagine, theatre, and library. I did NOT download waterfront! I need to fix this issue to not reference waterfront.webp.

Looking at my download list:
- everett/imagine-museum
- everett/everett-theatre
- everett/everett-library

No waterfront image was successfully... wait, the first script failed BEFORE everett waterfront. I had planned waterfront but the titles dict in the successful first batch included imagine and theatre, and the failed one was everett-library which was retried. I never downloaded waterfront. The issue I just wrote references waterfront.webp which doesn't exist. I must remove that photo include or the build will 404 the image. Jekyll won't fail the build for a missing image, but the page will be broken.

I'll fix the Everett week 2 file to drop the waterfront photo, or download the waterfront image. Downloading is better for depth. Let me note to download it after writing, and also fix if download fails.

I'll remove the photo include from the file in a follow-up if I don't download. Let me download waterfront quickly later. For now I'll continue writing and then fix the reference.

Actually I'll edit the file now to remove the photo block so I don't ship a broken image. I can describe the waterfront without a photo.

I'll StrReplace after this batch.

Also I referenced File:Everett,_WA_-_Waterfront_Center_01.jpg which I didn't download. Remove it.

Continue writing other files, then fix everett week 2.