---
layout: default
title: Search
description: Search family events, places, and guides across 15 Eastside cities.
permalink: /search/
---
<article class="page wrap search-page">
  <h1>Search</h1>
  {%- include search-form.html id="page-search" label="Events, places, and guides in 15 Eastside cities" -%}
  <noscript><p>Search needs JavaScript. Browse by <a href="{{ '/' | relative_url }}">city</a> or the <a href="{{ '/articles/' | relative_url }}">guides</a>.</p></noscript>
</article>
