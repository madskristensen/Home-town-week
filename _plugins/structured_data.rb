# frozen_string_literal: true

require "date"
require "json"
require "uri"

module EastsideCalendar
  # One JSON-LD graph per page, shaped for Google's event rich results
  # plus sitewide WebSite and Organization markup.
  module StructuredData
    ORGANIZERS = {
      "kcls.org" => ["King County Library System", "https://kcls.org/"],
      "bibliocommons.com" => ["King County Library System", "https://kcls.org/"],
      "bellevuewa.gov" => ["City of Bellevue", "https://bellevuewa.gov/"],
      "kirklandwa.gov" => ["City of Kirkland", "https://www.kirklandwa.gov/"],
      "redmond.gov" => ["City of Redmond", "https://www.redmond.gov/"],
      "issaquahwa.gov" => ["City of Issaquah", "https://www.issaquahwa.gov/"],
      "sammamish.us" => ["City of Sammamish", "https://www.sammamish.us/"],
      "bothellwa.gov" => ["City of Bothell", "https://www.bothellwa.gov/"],
      "mercerisland.gov" => ["City of Mercer Island", "https://www.mercerisland.gov/"],
      "rentonwa.gov" => ["City of Renton", "https://www.rentonwa.gov/"],
      "woodinvillewa.gov" => ["City of Woodinville", "https://www.ci.woodinville.wa.us/"],
      "woodinville.gov" => ["City of Woodinville", "https://www.woodinville.gov/"],
      "ci.woodinville.wa.us" => ["City of Woodinville", "https://www.woodinville.gov/"],
      "maplevalleywa.gov" => ["City of Maple Valley", "https://www.maplevalleywa.gov/"],
      "covingtonwa.gov" => ["City of Covington", "https://www.covingtonwa.gov/"],
      "duvallwa.gov" => ["City of Duvall", "https://www.duvallwa.gov/"],
      "carnationwa.gov" => ["City of Carnation", "https://www.carnationwa.gov/"],
      "kenmorewa.gov" => ["City of Kenmore", "https://www.kenmorewa.gov/"],
      "northbendwa.gov" => ["City of North Bend", "https://northbendwa.gov/"],
      "snoqualmiewa.gov" => ["City of Snoqualmie", "https://www.snoqualmiewa.gov/"],
      "kidsquestmuseum.org" => ["KidsQuest Children's Museum", "https://www.kidsquestmuseum.org/"],
      "kpcenter.org" => ["Kirkland Performance Center", "https://www.kpcenter.org/"],
      "eastsideaudubon.org" => ["Eastside Audubon", "https://www.eastsideaudubon.org/"],
      "snokinghockey.com" => ["Sno-King Hockey", "https://snokinghockey.com/"],
      "theatre33.ludus.com" => ["Theatre33", "https://www.theatre33wa.org/"]
    }.freeze

    # Ticket and news hosts are not the organizer. A path can still name
    # the city that sells the registration.
    PATH_ORGANIZERS = [
      ["amilia.com", %r{/city-of-redmond/}i, "City of Redmond", "https://www.redmond.gov/"],
      ["rec1.com", %r{/city-of-kirkland/}i, "City of Kirkland", "https://www.kirklandwa.gov/"]
    ].freeze
    LISTING_HOSTS = %w[
      eventbrite.com allevents.in meetup.com runsignup.com amilia.com rec1.com
      livingsnoqualmie.com valleyrecord.com donate.melanoma.org
    ].freeze

    module_function

    def attach(page)
      graph = build(page)
      page.data["json_ld"] = dump("@context" => "https://schema.org", "@graph" => graph)
    end

    def dump(obj)
      JSON.generate(obj).gsub("<", "\\u003c")
    end

    def home_page?(page)
      page.url.to_s == "/" || page.data["layout"].to_s == "home"
    end

    def origin(site)
      site.config["url"].to_s.sub(%r{/+\z}, "")
    end

    def abs(site, path)
      value = path.to_s.strip
      return "" if value.empty?
      return value if value.match?(%r{\Ahttps?://}i)

      EventCalendar.absolute_url(site, value.start_with?("/") ? value : "/#{value}")
    end

    # Rich results and feeds use a sized AVIF file. The card template
    # still receives the source path and builds its own srcset.
    def avif_source(site, path)
      raw = path.to_s.strip
      return raw if raw.empty? || raw.match?(%r{\Ahttps?://}i)

      file = raw.split("/").last.to_s
      stem = file.sub(/\.[A-Za-z0-9]+\z/, "")
      folder = raw.split("/")[-2].to_s
      return raw if folder.empty? || stem.empty?

      entry = site.data.dig("image_variants", folder, stem)
      return raw unless entry.is_a?(Hash)

      widths = Array(entry["avif"]).map { |width| width.to_i }.select(&:positive?)
      return raw if widths.empty?

      pick = widths.select { |width| width <= 1200 }.max || widths.max
      base = raw.sub(%r{[^/]+\z}, "")
      "#{base}#{stem}-#{pick}.avif"
    end

    def build(page)
      site = page.site
      root = origin(site)
      canonical = abs(site, page.url)
      org_id = "#{root}/#organization"
      site_id = "#{root}/#website"
      person_id = "#{root}/about/#person"
      logo = abs(site, site.config["logo"])
      nodes = []
      if home_page?(page)
        nodes << website_node(site, root, site_id, org_id, person_id)
        nodes << organization_node(site, root, org_id, logo)
        nodes << person_node(site, root, person_id)
      end
      crumbs = breadcrumbs(page, root)
      nodes << crumbs if crumbs
      events = event_nodes(page, canonical)
      list = item_list(page, canonical, events)
      list = map_list(page, canonical) if list.nil?
      nodes << page_node(page, site, canonical, site_id, org_id, person_id, logo, list)
      nodes << list if list
      nodes.concat(events.map { |event| event[:node] })
      nodes
    end

    def inject(page)
      return if page.url.to_s == "/404.html"
      return if page.data["sitemap"] == false

      json = page.data["json_ld"].to_s
      return if json.empty?

      html = page.output.to_s
      return if html.include?('"@graph"')
      return unless html.include?("</body>")

      script = %(<script type="application/ld+json">#{json}</script>\n)
      page.output = html.sub("</body>", "#{script}</body>")
    end

    def website_node(site, root, site_id, org_id, person_id)
      {
        "@type" => "WebSite",
        "@id" => site_id,
        "url" => "#{root}/",
        "name" => site.config["title"].to_s,
        "description" => site.config["description"].to_s,
        "inLanguage" => "en-US",
        "publisher" => { "@id" => org_id },
        "author" => { "@id" => person_id }
      }
    end

    def organization_node(site, root, org_id, logo)
      node = {
        "@type" => "Organization",
        "@id" => org_id,
        "name" => site.config["title"].to_s,
        "url" => "#{root}/",
        "logo" => {
          "@type" => "ImageObject",
          "@id" => "#{root}/#logo",
          "url" => logo,
          "width" => 512,
          "height" => 512
        }
      }
      links = Array(site.config.dig("social", "links")).map(&:to_s).reject(&:empty?)
      node["sameAs"] = links unless links.empty?
      node
    end

    def person_node(site, root, person_id)
      author = site.config["author"].is_a?(Hash) ? site.config["author"] : {}
      node = {
        "@type" => "Person",
        "@id" => person_id,
        "name" => author["name"].to_s,
        "url" => "#{root}/about/"
      }
      twitter = author["twitter"].to_s.strip
      node["sameAs"] = ["https://twitter.com/#{twitter}"] unless twitter.empty?
      node
    end

    def breadcrumbs(page, root)
      url = page.url.to_s
      return nil if url == "/" || url == "/404.html"

      home = { "name" => "Home", "item" => "#{root}/" }
      items = nil
      if page.data["layout"].to_s == "city"
        name = city_name(page)
        items = [home, { "name" => name, "item" => "#{root}#{url}" }] unless name.empty?
      elsif page.data["article_index"]
        items = [home, { "name" => "Articles", "item" => "#{root}#{url}" }]
      elsif page.data["layout"].to_s == "article" && url.start_with?("/fall/")
        items = [
          home,
          { "name" => "Fall", "item" => "#{root}/fall/" },
          { "name" => page.data["title"].to_s, "item" => "#{root}#{url}" }
        ]
      elsif page.data["layout"].to_s == "article"
        items = [
          home,
          { "name" => "Articles", "item" => "#{root}/articles/" },
          { "name" => page.data["title"].to_s, "item" => "#{root}#{url}" }
        ]
      elsif page.data["layout"].to_s == "guide"
        items = [home, { "name" => page.data["title"].to_s, "item" => "#{root}#{url}" }]
      elsif page.data["camps"]
        label = page.data["heading"].to_s.strip
        label = page.data["title"].to_s if label.empty?
        items = [home, { "name" => label, "item" => "#{root}#{url}" }]
      elsif page.data["layout"].to_s == "seasonal" || !page.data["hub_id"].to_s.empty?
        items = [home]
        if url.start_with?("/christmas/") && url != "/christmas/"
          items << { "name" => "Christmas", "item" => "#{root}/christmas/" }
        elsif url.start_with?("/fall/") && url != "/fall/"
          items << { "name" => "Fall", "item" => "#{root}/fall/" }
        end
        items << { "name" => page.data["title"].to_s, "item" => "#{root}#{url}" }
      end
      return nil if items.nil? || items.empty?

      {
        "@type" => "BreadcrumbList",
        "@id" => "#{root}#{url}#breadcrumb",
        "itemListElement" => items.each_with_index.map do |item, index|
          {
            "@type" => "ListItem",
            "position" => index + 1,
            "name" => item["name"],
            "item" => item["item"]
          }
        end
      }
    end

    def city_name(page)
      id = page.data["city"].to_s
      row = Array(page.site.data["cities"]).find { |item| item.is_a?(Hash) && item["id"].to_s == id }
      name = row && row["name"].to_s.strip
      return name unless name.nil? || name.empty?

      page.data["title"].to_s.strip
    end

    def page_node(page, site, canonical, site_id, org_id, person_id, logo, list)
      title = page_title(page)
      description = page.data["description"].to_s.strip
      description = site.config["description"].to_s if description.empty?
      image = page_image(page)
      if page.data["layout"].to_s == "article" && !page.data["article_index"]
        published = published_day(page)
        node = {
          "@type" => "Article",
          "@id" => "#{canonical}#article",
          "headline" => title.to_s[0, 110],
          "description" => description,
          "url" => canonical,
          "mainEntityOfPage" => canonical,
          "inLanguage" => "en-US",
          "isPartOf" => { "@id" => site_id },
          "datePublished" => published,
          "dateModified" => modified_day(page, published),
          "author" => {
            "@type" => "Person",
            "@id" => person_id,
            "name" => site.config.dig("author", "name").to_s,
            "url" => "#{origin(site)}/about/"
          },
          "publisher" => {
            "@type" => "Organization",
            "@id" => org_id,
            "name" => site.config["title"].to_s,
            "logo" => {
              "@type" => "ImageObject",
              "url" => logo,
              "width" => 512,
              "height" => 512
            }
          }
        }
        node["image"] = [image] unless image.empty?
        node["mainEntity"] = { "@id" => list["@id"] } if list
        return node
      end

      type = collection?(page) ? "CollectionPage" : "WebPage"
      node = {
        "@type" => type,
        "@id" => canonical,
        "name" => title,
        "description" => description,
        "url" => canonical,
        "inLanguage" => "en-US",
        "isPartOf" => { "@id" => site_id },
        "publisher" => { "@id" => org_id }
      }
      node["image"] = image unless image.empty?
      node["mainEntity"] = { "@id" => list["@id"] } if list
      node
    end

    def collection?(page)
      return false if page.data["home_lights"]
      return true if page.data["article_index"]
      return true if page.data["layout"].to_s == "city"
      return true if page.data["camps"]

      page.data["layout"].to_s == "seasonal" && !Array(page.data["visible_events"]).empty?
    end

    def page_title(page)
      if page.data["layout"].to_s == "city"
        "Family events and things to do with kids in #{city_name(page)} | #{page.site.config["title"]}"
      elsif page.url == "/"
        "Things to do with kids on the Eastside | #{page.site.config["title"]}"
      elsif page.data["title"].to_s == page.site.config["title"].to_s
        "#{page.site.config["title"]} | #{page.site.config["tagline"]}"
      else
        "#{page.data["title"]} | #{page.site.config["title"]}"
      end
    end

    def page_image(page)
      manifest = page.site.data["share_manifest"]
      if manifest.is_a?(Array)
        card = manifest.find { |row| row.is_a?(Hash) && row["path"].to_s == page.url.to_s }
        found = card && card["image"].to_s
        return abs(page.site, found) unless found.nil? || found.empty?
      end
      image = page.data["image"].to_s
      return abs(page.site, avif_source(page.site, image)) unless image.empty?
      return abs(page.site, page.site.config["image"]) if page.url == "/"

      hero = nil
      if page.data["layout"].to_s == "city"
        row = Array(page.site.data["cities"]).find { |item| item.is_a?(Hash) && item["id"].to_s == page.data["city"].to_s }
        hero = row && row.dig("hero", "image").to_s
      end
      return abs(page.site, avif_source(page.site, hero)) unless hero.nil? || hero.empty?

      ""
    end

    def published_day(page)
      day = page.data["date"].to_s[/\A(\d{4}-\d{2}-\d{2})/, 1]
      day || EventCalendar.pacific_today(page.site.time).iso8601
    end

    def modified_day(page, published)
      day = page.data["last_modified_at"].to_s[/\A(\d{4}-\d{2}-\d{2})/, 1]
      day || published
    end

    def item_list(page, canonical, events)
      if events.any?
        return {
          "@type" => "ItemList",
          "@id" => "#{canonical}#events",
          "name" => list_name(page),
          "itemListOrder" => "https://schema.org/ItemListOrderAscending",
          "numberOfItems" => events.length,
          "itemListElement" => events.each_with_index.map do |event, index|
            {
              "@type" => "ListItem",
              "position" => index + 1,
              "item" => { "@id" => event[:node]["@id"] }
            }
          end
        }
      end

      places = guide_items(page)
      return nil if places.empty?

      {
        "@type" => "ItemList",
        "@id" => "#{canonical}#places",
        "name" => page.data["title"].to_s,
        "itemListOrder" => "https://schema.org/ItemListOrderAscending",
        "numberOfItems" => places.length,
        "itemListElement" => places.each_with_index.map do |place, index|
          href = place["href"].to_s
          href = abs(page.site, href) unless href.match?(%r{\Ahttps?://}i)
          {
            "@type" => "ListItem",
            "position" => index + 1,
            "name" => place["name"].to_s,
            "url" => href
          }
        end
      }
    end

    def map_list(page, canonical)
      return nil unless page.data["home_lights"]

      data = map_data(page)
      return nil unless data.is_a?(Hash)

      places = Array(data["towns"]).flat_map { |town| Array(town["lights"]) }
      return nil if places.empty?

      {
        "@type" => "ItemList",
        "@id" => "#{canonical}#places",
        "name" => page.data["title"].to_s,
        "itemListOrder" => "https://schema.org/ItemListOrderAscending",
        "numberOfItems" => places.length,
        "itemListElement" => places.each_with_index.map do |place, index|
          item = {
            "@type" => "Place",
            "name" => place["name"].to_s,
            "description" => place["description"].to_s,
            "url" => "#{canonical}#light-#{place["id"]}",
            "address" => {
              "@type" => "PostalAddress",
              "streetAddress" => place["address"].to_s,
              "addressLocality" => place["city"].to_s,
              "addressRegion" => "WA",
              "addressCountry" => "US"
            }
          }
          source = place["source"].to_s
          item["sameAs"] = source if source.match?(%r{\Ahttps://})
          image = place["image"].to_s
          item["image"] = abs(page.site, avif_source(page.site, image)) unless image.empty?
          {
            "@type" => "ListItem",
            "position" => index + 1,
            "item" => item
          }
        end
      }
    end

    def map_data(page)
      case page.data["map_id"].to_s
      when "halloween" then page.site.data["halloween_map"]
      when "markets" then page.site.data["farmers_market_page"]
      else page.site.data["home_lights"]
      end
    end

    def list_name(page)
      return "Upcoming events in #{city_name(page)}" if page.data["layout"].to_s == "city"
      return "Free events coming up" if page.data["article_id"].to_s == "free-things-to-do"
      return "Toddler events coming up" if page.data["article_id"].to_s == "toddler-friendly-outings"

      page.data["title"].to_s
    end

    def guide_items(page)
      if page.data["article_index"]
        return Array(page.site.data["articles"]).select { |row| row.is_a?(Hash) }
      end

      Array(page.data["places"]).select { |row| row.is_a?(Hash) && !row["href"].to_s.empty? }
    end

    def event_nodes(page, canonical)
      return [] unless event_page?(page)

      today = EventCalendar.pacific_today(page.site.time)
      sections = section_index(page.content)
      used = {}
      nodes = []
      Array(page.data["visible_events"]).each do |event|
        next unless event.is_a?(Hash)
        next unless current_event?(event, today)

        extra = sections[event["name"].to_s]
        extra ||= sections[EventCalendar.normalize(event["name"])]
        node = event_node(page, event, extra || {}, canonical, nodes.length + 1, used)
        nodes << { node: node } if node
      end
      nodes
    end

    def event_page?(page)
      layout = page.data["layout"].to_s
      return true if layout == "city" || layout == "seasonal"
      id = page.data["article_id"].to_s
      return true if id == "free-things-to-do" || id == "toddler-friendly-outings"

      false
    end

    def current_event?(event, today)
      finish = event["end_on"].to_s[/\A\d{4}-\d{2}-\d{2}/]
      finish ||= event["date"].to_s[/\A\d{4}-\d{2}-\d{2}/]
      finish ||= event["endDate"].to_s[/\A\d{4}-\d{2}-\d{2}/]
      finish ||= event["startDate"].to_s[/\A\d{4}-\d{2}-\d{2}/]
      return true if finish.nil? || finish.empty?

      Date.iso8601(finish) >= today
    rescue Date::Error, ArgumentError
      true
    end

    def section_index(markdown)
      index = {}
      markdown.to_s.split(/(?=^### )/m).each do |part|
        name = part[/\A###[ \t]+([^\n]+)/, 1].to_s.strip
        next if name.empty?

        src = part[/\{%\s*include\s+event-photo\.html\b.*?src="([^"]+)"/m, 1]
        label = part[/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/, 1]
        url = part[/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/, 2]
        info = { "image" => src.to_s, "link_label" => label.to_s, "link_url" => url.to_s }
        index[name] = info
        index[EventCalendar.normalize(name)] = info
      end
      index
    end

    def event_node(page, event, extra, canonical, position, used)
      name = event["name"].to_s.strip
      return nil if name.empty?

      start_on, end_on = google_interval(event)
      return nil if start_on.nil? || start_on.empty?

      locality = event["locality"].to_s.strip
      locality = event["city"].to_s.strip if locality.empty?
      locality = event["town"].to_s.strip if locality.empty?
      place = event["place"].to_s
      venue = EventCalendar.venue_name(place, locality)
      venue = locality if venue.empty? || venue.casecmp(name).zero?
      return nil if venue.empty?

      street = event["street"].to_s.strip
      street = EventCalendar.place_parts(place, locality).last.to_s if street.empty?
      slug = unique_slug(used, name)
      fragment = "#{canonical}##{slug}"
      official = first_http(event["sameAs"], event["same_as"], extra["link_url"])
      event_url = official || fragment
      node = {
        "@type" => "Event",
        "@id" => event_url,
        "name" => name,
        "startDate" => start_on,
        "eventStatus" => "https://schema.org/EventScheduled",
        "eventAttendanceMode" => "https://schema.org/OfflineEventAttendanceMode",
        "url" => event_url,
        "location" => location_node(venue, street, locality, place)
      }
      node["endDate"] = end_on unless end_on.nil? || end_on.empty?
      description = event["description"].to_s.strip
      description = event["blurb"].to_s.strip if description.empty? || description.casecmp(name).zero?
      node["description"] = short_description(description) unless description.empty?
      image = event["image"].to_s
      image = extra["image"].to_s if image.empty?
      node["image"] = [abs(page.site, avif_source(page.site, image))] unless image.empty?
      organizer = organizer_for(page, event, official, venue)
      node["organizer"] = organizer if organizer
      offer = offer_node(event, event_url, page.site)
      if offer
        node["offers"] = offer
        node["isAccessibleForFree"] = true if offer["price"].to_s == "0" || offer["price"] == 0
      end
      node
    end

    # Rich results use a short description. Longer copy stays on the card.
    def short_description(text)
      clean = text.to_s.gsub(/\s+/, " ").strip
      return clean if clean.length <= 180

      cut = clean[0, 180]
      space = cut.rindex(" ")
      cut = cut[0...space] if space && space > 80
      cut = cut.sub(/[\s,;:]+$/, "")
      return cut if cut.end_with?(".", "!", "?")

      "#{cut}."
    end

    def location_node(venue, street, locality, place)
      address = {
        "@type" => "PostalAddress",
        "addressRegion" => "WA",
        "addressCountry" => "US"
      }
      address["streetAddress"] = street unless street.empty?
      address["addressLocality"] = locality unless locality.empty?
      zip = place.to_s[/\b(\d{5})(?:-\d{4})?\b/, 1]
      address["postalCode"] = zip if zip
      {
        "@type" => "Place",
        "name" => venue,
        "address" => address
      }
    end

    def organization(name, url)
      { "@type" => "Organization", "name" => name, "url" => url }
    end

    # The host on the source URL, then a city source with that host, then
    # the venue and the source site. An explicit organizer on the event wins.
    def organizer_for(page, event, url, venue)
      explicit_name = event["organizer"].to_s.strip
      explicit_url = first_http(event["organizer_url"])
      return organization(explicit_name, explicit_url) if !explicit_name.empty? && explicit_url
      return nil if url.nil? || url.empty?

      host = bare_host(url)
      return nil if host.empty?

      listed = path_organizer(host, url)
      return organization(listed[0], listed[1]) if listed

      known = organizers_for(host)
      return organization(known[0], known[1]) if known

      city_id = event["city_id"].to_s
      city_id = page.data["city"].to_s if city_id.empty?
      city_name = event["city"].to_s.strip
      city_name = event["locality"].to_s.strip if city_name.empty?
      picked = pick_source(page.site, host, url, city_id, city_name, venue)
      return organization(source_org_name(picked["name"]), picked["url"]) if picked
      return nil if listing_host?(host)

      origin = origin_of(url)
      return nil if origin.nil?

      candidate = venue.to_s.strip
      unless organization_like?(candidate)
        head = candidate.split(",").first.to_s.strip
        candidate = head if organization_like?(head)
      end
      return nil unless organization_like?(candidate)

      organization(candidate, origin)
    end

    def path_organizer(host, url)
      PATH_ORGANIZERS.each do |key, pattern, name, org_url|
        next unless host == key || host.end_with?(".#{key}")
        return [name, org_url] if url.match?(pattern)
      end
      nil
    end

    def organizers_for(host)
      ORGANIZERS.each do |key, value|
        return value if host == key || host.end_with?(".#{key}")
      end
      nil
    end

    def listing_host?(host)
      LISTING_HOSTS.any? { |key| host == key || host.end_with?(".#{key}") }
    end

    def pick_source(site, host, url, city_id, city_name, venue)
      cands = source_rows(site).select { |row| row["host"] == host || host.end_with?(".#{row["host"]}") }
      cands.reject! { |row| %w[allevents news].include?(row["type"]) }
      return nil if cands.empty?

      names = cands.map { |row| row["name"] }.uniq
      return cands.min_by { |row| row["path"].length } if names.size == 1

      path = URI.parse(url).path.to_s.sub(%r{/\z}, "")
      prefixed = cands.select do |row|
        base = row["path"]
        !base.empty? && (path == base || path.start_with?("#{base}/"))
      end
      return prefixed.max_by { |row| row["path"].length } unless prefixed.empty?

      [city_id, city_name].each do |token|
        next if token.to_s.empty?

        city_rows = if token == city_id
                      cands.select { |row| row["city_id"] == city_id }
                    else
                      cands.select { |row| row["city"].casecmp(city_name).zero? }
                    end
        next unless city_rows.map { |row| row["name"] }.uniq.size == 1

        return city_rows.min_by { |row| row["path"].length }
      end
      cands.find { |row| row["name"].casecmp(venue.to_s).zero? }
    rescue URI::InvalidURIError
      nil
    end

    def source_rows(site)
      @source_rows ||= {}
      @source_rows[site.object_id] ||= Array(site.data["cities"]).flat_map do |city|
        next [] unless city.is_a?(Hash)

        Array(city["sources"]).filter_map do |source|
          next unless source.is_a?(Hash)

          raw = source["url"].to_s.strip
          next if raw.empty?

          uri = URI.parse(raw)
          host = uri.host.to_s.downcase.sub(/\Awww\./, "")
          next if host.empty?

          name = source["name"].to_s.strip
          next if name.empty?

          {
            "name" => name,
            "url" => raw,
            "type" => source["type"].to_s,
            "host" => host,
            "path" => uri.path.to_s.sub(%r{/\z}, ""),
            "city_id" => city["id"].to_s,
            "city" => city["name"].to_s
          }
        rescue URI::InvalidURIError
          nil
        end
      end
    end

    def source_org_name(name)
      text = name.to_s.strip.sub(/\s+(?:events|calendar)\z/i, "")
      text.empty? ? name.to_s.strip : text
    end

    def organization_like?(name)
      text = name.to_s.strip
      return false if text.empty? || text.length > 80
      return false if text.match?(/\A\d/)
      return false if text.match?(/\bbetween\b/i)

      street = /\b(?:Ave|Avenue|St|Street|Rd|Road|Blvd|Boulevard|Dr|Drive|Way|Ln|Lane|Pl|NE|NW|SE|SW)\b/i
      place = /\b(?:Park|Library|Center|Centre|Museum|Theatre|Theater|Market|Farm|Zoo|Church|Club|Gym|YMCA|School|Gallery|Hall|Depot|Station)\b/i
      return false if text.match?(street) && !text.match?(place)

      true
    end

    def performer_node(event)
      name = event["performer"].to_s.strip
      return nil if name.empty?

      { "@type" => "Person", "name" => name }
    end

    # Free is 0 USD. A published price, or the low end of a range, is
    # that number in USD. An unknown price is left off so the offer is
    # never missing price or priceCurrency.
    def offer_node(event, url, site)
      return nil if url.nil? || url.empty?

      amount = offer_amount(event["cost"])
      return nil if amount.nil?

      from = valid_from(event, site)
      return nil if from.empty?

      {
        "@type" => "Offer",
        "url" => url,
        "availability" => "https://schema.org/InStock",
        "price" => amount,
        "priceCurrency" => "USD",
        "validFrom" => from
      }
    end

    def valid_from(event, site)
      added = event["added"].to_s.strip
      unless added.empty?
        parsed = EventCalendar.parse_when(added)
        if parsed && parsed[:date]
          clock = parsed[:time] || [12, 0, 0]
          clock = [12, 0, 0] if clock == [0, 0, 0]
          stamped = EventCalendar.format_offset_time(date: parsed[:date], time: clock)
          return stamped unless stamped.nil? || stamped.empty?
        end
      end
      local = EventCalendar.pacific_time(site.time)
      return "" if local.nil?

      local.strftime("%Y-%m-%dT%H:%M:%S%:z")
    end

    def offer_amount(cost)
      text = cost.to_s.strip
      return 0 if text.casecmp("free").zero?
      exact = EventCalendar.offer_price(text)
      return number_price(exact) unless exact.empty?
      return nil unless text.match?(/\A\$[\d,]+(?:\.\d{1,2})?(?:\s+to\s+\$[\d,]+(?:\.\d{1,2})?)?\z/)

      amounts = text.scan(/[\d,]+(?:\.\d{1,2})?/).map { |part| part.delete(",") }
      return nil if amounts.empty?

      number_price(amounts.min_by(&:to_f))
    end

    def number_price(text)
      return text.to_i if text.match?(/\A\d+\z/)
      return text.to_f if text.match?(/\A\d+\.\d+\z/)

      nil
    end

    def google_interval(event)
      start_parsed = bound(event, :start)
      return [nil, nil] unless start_parsed && start_parsed[:date]

      end_parsed = bound(event, :end)
      if start_parsed[:time]
        start_on = EventCalendar.format_offset_time(start_parsed)
        [start_on, timed_end(start_parsed, end_parsed)]
      else
        start_on = start_parsed[:date].iso8601
        end_on = if end_parsed && end_parsed[:date] && end_parsed[:date] >= start_parsed[:date]
                   end_parsed[:date].iso8601
                 else
                   start_on
                 end
        [start_on, end_on]
      end
    end

    # A later clock is that end. A later date with no clock stays a date.
    # Otherwise the end is two hours after the start, in local time.
    def timed_end(start_parsed, end_parsed)
      if end_parsed && end_parsed[:time] && EventCalendar.sort_key(end_parsed) > EventCalendar.sort_key(start_parsed)
        return EventCalendar.format_offset_time(end_parsed)
      end
      if end_parsed && end_parsed[:date] && end_parsed[:time].nil? && end_parsed[:date] > start_parsed[:date]
        return end_parsed[:date].iso8601
      end

      EventCalendar.format_offset_time(shift_hours(start_parsed, 2))
    end

    def shift_hours(parsed, hours)
      hour, min, sec = parsed[:time]
      total = (hour * 3600) + (min * 60) + sec + (hours * 3600)
      days = total.div(86_400)
      total %= 86_400
      {
        date: parsed[:date] + days,
        time: [total / 3600, (total % 3600) / 60, total % 60]
      }
    end

    def bound(event, which)
      if which == :start
        share = event["shareStart"].to_s
        return EventCalendar.parse_when(share) unless share.empty?
      else
        share = event["shareEnd"].to_s
        return EventCalendar.parse_when(share) unless share.empty?
      end
      raw_key = which == :start ? "start_raw" : "end_raw"
      plain_key = which == :start ? "start" : "end"
      iso_key = which == :start ? "startDate" : "endDate"
      raw = event[raw_key].to_s
      raw = event[plain_key].to_s if raw.empty?
      parsed = EventCalendar.parse_when(raw) unless raw.empty?
      return parsed if parsed

      iso = event[iso_key].to_s
      return nil if iso.empty?
      if iso.include?("T00:00:00") || iso.include?("T23:59:59")
        return { date: Date.iso8601(iso[0, 10]), time: nil }
      end

      EventCalendar.parse_when(iso)
    rescue Date::Error, ArgumentError
      nil
    end

    def first_http(*values)
      values.each do |value|
        text = value.to_s.strip
        return text if text.match?(%r{\Ahttps?://\S+\z})
      end
      nil
    end

    def bare_host(url)
      URI.parse(url).host.to_s.downcase.sub(/\Awww\./, "")
    rescue URI::InvalidURIError
      ""
    end

    def origin_of(url)
      uri = URI.parse(url)
      return nil if uri.host.to_s.empty?

      "#{uri.scheme}://#{uri.host}/"
    rescue URI::InvalidURIError
      nil
    end

    def unique_slug(used, name)
      base = name.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
      base = "event" if base.empty?
      count = used[base].to_i + 1
      used[base] = count
      count == 1 ? "event-#{base}" : "event-#{base}-#{count}"
    end

    def attach_free_events(site)
      page = site.pages.find { |item| item.data["article_id"].to_s == "free-things-to-do" }
      return unless page

      pages = SeasonalHubs.city_pages(site)
      catalog = SeasonalHubs.card_catalog(pages)
      venues = Array(site.data.dig("venue_images", "venues"))
      names = {}
      Array(site.data["cities"]).each do |row|
        next unless row.is_a?(Hash)

        names[row["id"].to_s] = row["name"].to_s
      end
      today = EventCalendar.pacific_today(site.time)
      root = origin(site)
      rows = []
      site.data.each do |key, records|
        name = key.to_s
        next unless name.end_with?("_events")
        next if name == "worth_the_drive_events"

        city_id = name.sub(/_events\z/, "")
        city_name = names[city_id].to_s
        next if city_name.empty?

        Array(records).each do |event|
          next unless event.is_a?(Hash)
          next unless event["cost"].to_s.strip.casecmp("free").zero?

          row = SeasonalHubs.event_row(event, city_id, city_name, root)
          next unless SeasonalHubs.upcoming_row?(row, today)

          card = SeasonalHubs.find_card(catalog, row)
          blurb = card && card[:blurb].to_s.strip
          next if blurb.nil? || blurb.empty?

          photo = photo_for(card, row, venues)
          next unless photo

          row["blurb"] = blurb
          row["description"] = blurb
          row["cost"] = "Free"
          row["image"] = photo["src"]
          row["alt"] = photo["alt"].to_s
          row["image_alt"] = photo["alt"].to_s
          row["credit"] = photo["credit"].to_s
          row["image_credit"] = photo["credit"].to_s
          row["image_source"] = photo["source"].to_s
          rows << row
        end
      end
      rows.sort_by! { |row| [row["sort"].to_s, row["city"].to_s, row["name"].to_s] }
      seen = {}
      picked = []
      rows.each do |row|
        key = "#{row["city_id"]}|#{EventCalendar.normalize(row["name"])}|#{row["sort"]}"
        next if seen[key]

        seen[key] = true
        picked << row
        break if picked.length >= 12
      end
      page.data["free_events"] = picked
      page.data["visible_events"] = picked
    end

    def attach_toddler_events(site)
      page = site.pages.find { |item| item.data["article_id"].to_s == "toddler-friendly-outings" }
      return unless page

      pages = SeasonalHubs.city_pages(site)
      catalog = SeasonalHubs.card_catalog(pages)
      venues = Array(site.data.dig("venue_images", "venues"))
      names = {}
      Array(site.data["cities"]).each do |row|
        next unless row.is_a?(Hash)

        names[row["id"].to_s] = row["name"].to_s
      end
      today = EventCalendar.pacific_today(site.time)
      root = origin(site)
      rows = []
      site.data.each do |key, records|
        name = key.to_s
        next unless name.end_with?("_events")
        next if name == "worth_the_drive_events"

        city_id = name.sub(/_events\z/, "")
        city_name = names[city_id].to_s
        next if city_name.empty?

        Array(records).each do |event|
          next unless event.is_a?(Hash)
          next unless event["ages"].to_s.strip == "Toddlers"

          row = SeasonalHubs.event_row(event, city_id, city_name, root)
          next unless SeasonalHubs.upcoming_row?(row, today)

          card = SeasonalHubs.find_card(catalog, row)
          blurb = card && card[:blurb].to_s.strip
          next if blurb.nil? || blurb.empty?

          photo = photo_for(card, row, venues)
          next unless photo

          row["blurb"] = blurb
          row["description"] = blurb
          row["image"] = photo["src"]
          row["alt"] = photo["alt"].to_s
          row["image_alt"] = photo["alt"].to_s
          row["credit"] = photo["credit"].to_s
          row["image_credit"] = photo["credit"].to_s
          row["image_source"] = photo["source"].to_s
          rows << row
        end
      end
      rows.sort_by! { |row| [row["sort"].to_s, row["city"].to_s, row["name"].to_s] }
      seen = {}
      picked = []
      rows.each do |row|
        key = "#{row["city_id"]}|#{EventCalendar.normalize(row["name"])}|#{row["sort"]}"
        next if seen[key]

        seen[key] = true
        picked << row
        break if picked.length >= 12
      end
      page.data["toddler_events"] = picked
      page.data["visible_events"] = picked
    end

    def attach_playground_places(site)
      page = site.pages.find { |item| item.data["article_id"].to_s == "best-playgrounds" }
      return unless page

      groups = site.data.dig("guides", "playgrounds", "groups")
      places = []
      Array(groups).each do |group|
        next unless group.is_a?(Hash)

        Array(group["entries"]).each do |entry|
          next unless entry.is_a?(Hash)

          text = entry["text"].to_s.strip
          blurb = text.split(/(?<=[.!?])\s+/, 2).first.to_s.strip
          next if blurb.empty?

          street = entry["address"].to_s.split(",").first.to_s.strip
          href = entry["page"].to_s.strip
          next if href.empty?

          places << {
            "name" => entry["name"].to_s,
            "blurb" => blurb,
            "place" => street,
            "city" => group["city"].to_s,
            "city_id" => group["id"].to_s,
            "href" => href,
            "external" => true,
            "image" => entry["image"].to_s,
            "alt" => entry["alt"].to_s,
            "credit" => entry["credit"].to_s,
            "image_source" => entry["source"].to_s
          }
        end
      end
      page.data["places"] = places
    end

    def photo_for(card, row, venues)
      if card && card[:photo].is_a?(Hash)
        own = SeasonalHubs.licensed_photo(card[:photo])
        return own if own && !SeasonalHubs.people_photo?(own)
      end
      venue = SeasonalHubs.matching_venues(row, venues).first
      SeasonalHubs.listed_photo(venue, "venue") if venue
    end
  end

  class StructuredDataGenerator < Jekyll::Generator
    priority :lowest

    def generate(site)
      StructuredData.attach_free_events(site)
      StructuredData.attach_toddler_events(site)
      StructuredData.attach_playground_places(site)
    end
  end
end

Jekyll::Hooks.register :pages, :pre_render do |page|
  EastsideCalendar::StructuredData.attach(page)
end

Jekyll::Hooks.register :pages, :post_render do |page|
  EastsideCalendar::StructuredData.inject(page)
end
