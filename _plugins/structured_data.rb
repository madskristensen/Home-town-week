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
      "maplevalleywa.gov" => ["City of Maple Valley", "https://www.maplevalleywa.gov/"],
      "duvallwa.gov" => ["City of Duvall", "https://www.duvallwa.gov/"],
      "carnationwa.gov" => ["City of Carnation", "https://www.carnationwa.gov/"],
      "kenmorewa.gov" => ["City of Kenmore", "https://www.kenmorewa.gov/"],
      "northbendwa.gov" => ["City of North Bend", "https://northbendwa.gov/"],
      "snoqualmiewa.gov" => ["City of Snoqualmie", "https://www.snoqualmiewa.gov/"],
      "kidsquestmuseum.org" => ["KidsQuest Children's Museum", "https://www.kidsquestmuseum.org/"],
      "kpcenter.org" => ["Kirkland Performance Center", "https://www.kpcenter.org/"],
      "eastsideaudubon.org" => ["Eastside Audubon", "https://www.eastsideaudubon.org/"],
      "snokinghockey.com" => ["Sno-King Hockey", "https://snokinghockey.com/"]
    }.freeze

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
      elsif page.data["layout"].to_s == "article"
        items = [
          home,
          { "name" => "Articles", "item" => "#{root}/articles/" },
          { "name" => page.data["title"].to_s, "item" => "#{root}#{url}" }
        ]
      elsif page.data["layout"].to_s == "guide"
        items = [home, { "name" => page.data["title"].to_s, "item" => "#{root}#{url}" }]
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
      return abs(page.site, image) unless image.empty?
      return abs(page.site, page.site.config["image"]) if page.url == "/"

      hero = nil
      if page.data["layout"].to_s == "city"
        row = Array(page.site.data["cities"]).find { |item| item.is_a?(Hash) && item["id"].to_s == page.data["city"].to_s }
        hero = row && row.dig("hero", "image").to_s
      end
      return abs(page.site, hero) unless hero.nil? || hero.empty?

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
              "name" => event[:node]["name"],
              "url" => event[:node]["url"],
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
          item["image"] = abs(page.site, image) unless image.empty?
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
      return true if page.data["article_id"].to_s == "free-things-to-do"

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
      node["description"] = description unless description.empty?
      image = event["image"].to_s
      image = extra["image"].to_s if image.empty?
      node["image"] = [abs(page.site, image)] unless image.empty?
      organizer = organizer_node(official, extra["link_label"], name, venue)
      node["organizer"] = organizer if organizer
      node["sameAs"] = official if official && official != event_url
      offer = offer_node(event, official || event_url)
      if offer
        node["offers"] = offer
        node["isAccessibleForFree"] = true if offer["price"].to_s == "0" || offer["price"] == 0
      end
      node
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

    def organizer_node(url, label, event_name, venue)
      return nil if url.nil? || url.empty?

      host = host_key(url)
      known = host && ORGANIZERS[host]
      name = known ? known[0] : ""
      org_url = known ? known[1] : origin_of(url)
      if name.empty?
        text = label.to_s.strip
        name = text if !text.empty? && !text.casecmp(event_name).zero? && text.length <= 80
      end
      name = venue if name.empty? && !venue.empty? && !venue.casecmp(event_name).zero?
      return nil if name.empty? || org_url.nil? || org_url.empty?

      { "@type" => "Organization", "name" => name, "url" => org_url }
    end

    def offer_node(event, url)
      amount = offer_amount(event["cost"])
      return nil if amount.nil?

      {
        "@type" => "Offer",
        "price" => amount,
        "priceCurrency" => "USD",
        "availability" => "https://schema.org/InStock",
        "url" => url
      }
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
        end_on = nil
        if end_parsed && end_parsed[:time] && EventCalendar.sort_key(end_parsed) > EventCalendar.sort_key(start_parsed)
          end_on = EventCalendar.format_offset_time(end_parsed)
        elsif end_parsed && end_parsed[:date] && end_parsed[:time].nil? && end_parsed[:date] > start_parsed[:date]
          end_on = end_parsed[:date].iso8601
        end
        [start_on, end_on]
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

    def host_key(url)
      host = URI.parse(url).host.to_s.downcase.sub(/\Awww\./, "")
      return nil if host.empty?

      ORGANIZERS.each_key do |key|
        return key if host == key || host.end_with?(".#{key}")
      end
      nil
    rescue URI::InvalidURIError
      nil
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
    end
  end
end

Jekyll::Hooks.register :pages, :pre_render do |page|
  EastsideCalendar::StructuredData.attach(page)
end

Jekyll::Hooks.register :pages, :post_render do |page|
  EastsideCalendar::StructuredData.inject(page)
end
