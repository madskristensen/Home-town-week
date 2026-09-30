# frozen_string_literal: true

require "cgi"
require "date"

module EastsideCalendar
  # Seasonal hubs and the one sitewide banner are data in
  # _data/seasonal_hubs.yml. A new season is a new entry there.
  module SeasonalHubs
    HEX = /\A#[0-9a-fA-F]{6}\z/
    MONTHS = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec].freeze

    module_function

    def banner_rule(config)
      banner = config.is_a?(Hash) ? config["banner"] : nil
      banner = {} unless banner.is_a?(Hash)
      {
        "min_events" => positive_int(banner["min_events"], 6),
        "min_towns" => positive_int(banner["min_towns"], 3)
      }
    end

    def positive_int(value, fallback)
      number = Integer(value)
      number.positive? ? number : fallback
    rescue ArgumentError, TypeError
      fallback
    end

    def normalize_path(url)
      path = url.to_s.strip
      path = path.sub(%r{\Ahttps?://[^/]+}i, "")
      path = path.sub(/\A[^\/]*/, "")
      path = "/#{path}" unless path.start_with?("/")
      path = path.sub(%r{/index\.html\z}i, "/")
      path = "#{path}/" unless path.end_with?("/")
      path
    end

    def same_page?(page_url, hub_path)
      normalize_path(page_url) == normalize_path(hub_path)
    end

    def in_season?(today, start_s, end_s)
      start_ord = month_day_ord(start_s)
      end_ord = month_day_ord(end_s)
      return false unless start_ord && end_ord

      today_ord = today.month * 100 + today.day
      if start_ord <= end_ord
        today_ord >= start_ord && today_ord <= end_ord
      else
        today_ord >= start_ord || today_ord <= end_ord
      end
    end

    # The end date of the season occurrence that contains today.
    def season_end_on(today, start_s, end_s)
      start_ord = month_day_ord(start_s)
      end_month, end_day = month_day(end_s)
      return nil unless start_ord && end_month

      year = today.year
      year += 1 if start_ord > (end_month * 100 + end_day) && (today.month * 100 + today.day) >= start_ord
      Date.new(year, end_month, end_day)
    rescue Date::Error, ArgumentError
      nil
    end

    def month_day(value)
      match = value.to_s.match(/\A(\d{1,2})-(\d{1,2})\z/)
      return nil unless match

      month = match[1].to_i
      day = match[2].to_i
      return nil unless month.between?(1, 12) && day.between?(1, 31)

      [month, day]
    end

    def month_day_ord(value)
      month, day = month_day(value)
      return nil unless month

      month * 100 + day
    end

    def season_label(start_s, end_s)
      "#{month_day_label(start_s)} through #{month_day_label(end_s)}"
    end

    def month_day_label(value)
      month, day = month_day(value)
      return value.to_s unless month

      "#{MONTHS[month - 1]} #{day}"
    end

    # A neighborhood label is fine. A street number is not.
    def public_area(value)
      text = value.to_s.gsub(/\s+/, " ").strip
      return "" if text.empty?
      return "" if text.match?(/\A\d/)
      return "" if text.match?(/\b\d{1,6}\s+\S/)

      text
    end

    def safe_svg(value)
      svg = value.to_s.strip
      return "" if svg.empty?
      return "" unless svg.match?(/\A<svg\b/i) && svg.match?(%r{</svg>\z}i)
      return "" if svg.match?(/<script|foreignObject|javascript:|on[a-z]+\s*=/i)

      svg
    end

    def hex_color(value, fallback)
      text = value.to_s.strip
      text.match?(HEX) ? text : fallback
    end

    def sections_for(hub, cities, data, lights, today, site_url)
      return town_sections(hub, cities, data, today, site_url) if hub["group"].to_s == "town"

      names = city_names(cities)
      grouped = Hash.new { |hash, key| hash[key] = [] }
      seen = Hash.new { |hash, key| hash[key] = {} }

      names.each_key do |city_id|
        Array(data["#{city_id}_events"]).each do |event|
          next unless event.is_a?(Hash)

          tags = Array(event["tags"]).map(&:to_s)
          name = event["name"].to_s.downcase
          Array(hub["sections"]).each do |section|
            next unless section.is_a?(Hash)
            next unless section_match?(tags, name, section)

            row = event_row(event, city_id, names[city_id], site_url)
            next unless upcoming_row?(row, today)

            key = "#{row["city_id"]}|#{row["name"]}|#{row["sort"]}"
            next if seen[section["id"]][key]

            seen[section["id"]][key] = true
            grouped[section["id"]] << row
          end
        end
      end

      if hub["lights"].to_s != ""
        light_section = Array(hub["sections"]).find { |section| Array(section["tags"]).map(&:to_s).include?("holiday-lights") }
        if light_section
          Array(lights).each do |row|
            # Displays in this file are the Christmas lights section, not events.
            next if row.is_a?(Hash) && LIGHT_TYPES.key?(row["type"].to_s.strip)

            item = display_row(row, names, site_url)
            next unless item && upcoming_row?(item, today)

            key = "#{item["city_id"]}|#{item["name"]}|#{item["sort"]}"
            next if seen[light_section["id"]][key]

            seen[light_section["id"]][key] = true
            grouped[light_section["id"]] << item
          end
        end
      end

      Array(hub["sections"]).filter_map do |section|
        next unless section.is_a?(Hash)

        items = grouped[section["id"]].sort_by { |item| [item["sort"], item["name"].to_s] }
        next if items.empty?

        section_payload(section, items)
      end
    end

    # group: town lists one section per city. An event matches when it has
    # one of the hub tags or its name contains one of the hub keywords.
    def town_sections(hub, cities, data, today, site_url)
      names = city_names(cities)
      tags = Array(hub["tags"]).map(&:to_s)
      keywords = phrases(hub["keywords"])
      sections = []
      Array(cities).each do |city|
        next unless city.is_a?(Hash)

        city_id = city["id"].to_s
        city_name = names[city_id].to_s
        next if city_id.empty? || city_name.empty?

        seen = {}
        items = []
        Array(data["#{city_id}_events"]).each do |event|
          next unless event.is_a?(Hash)
          next unless town_match?(event, tags, keywords)

          row = event_row(event, city_id, city_name, site_url)
          next unless upcoming_row?(row, today)

          key = "#{row["name"]}|#{row["sort"]}"
          next if seen[key]

          seen[key] = true
          items << row
        end
        next if items.empty?

        items.sort_by! { |item| [item["sort"], item["name"].to_s] }
        sections << {
          "id" => city_id,
          "title" => city_name,
          "toc" => city_name,
          "intro" => "Family events in #{city_name}.",
          "events" => items
        }
      end
      sections
    end

    def section_match?(tags, name, section)
      section_tags = Array(section["tags"]).map(&:to_s)
      return true unless (tags & section_tags).empty?

      phrases(section["keywords"]).any? { |phrase| name.include?(phrase) }
    end

    def town_match?(event, tags, keywords)
      event_tags = Array(event["tags"]).map(&:to_s)
      return true unless (event_tags & tags).empty?

      name = event["name"].to_s.downcase
      keywords.any? { |phrase| name.include?(phrase) }
    end

    def phrases(value)
      Array(value).map { |phrase| phrase.to_s.downcase.strip }.reject(&:empty?)
    end

    def banner_choice(hubs, rule, today)
      qualifying = []
      hubs.each_with_index do |hub, index|
        next unless hub["in_season"]

        identity = qualifying_identity(hub["sections"])
        next if identity[:events] < rule["min_events"]
        next if identity[:towns] < rule["min_towns"]

        qualifying << [hub["ends_on"] || Date.new(9999, 12, 31), index, hub]
      end
      return nil if qualifying.empty?

      qualifying.min_by { |ends_on, index, _hub| [ends_on, index] }[2]
    end

    def qualifying_identity(sections)
      events = {}
      Array(sections).each do |section|
        Array(section["events"]).each do |event|
          events["#{event["city_id"]}|#{event["name"]}"] = event["city_id"].to_s
        end
      end
      { events: events.length, towns: events.values.uniq.reject(&:empty?).length }
    end

    def banner_html(hub, baseurl)
      theme = hub["theme"] || {}
      href = "#{baseurl}#{hub["path"]}"
      style = [
        "--season-bg:#{theme["background"]}",
        "--season-ink:#{theme["ink"]}",
        "--season-muted:#{theme["muted"]}",
        "--season-link:#{theme["link"]}"
      ].join(";")
      <<~HTML.strip
        <nav class="season-banner" style="#{style}" aria-label="#{esc(hub["banner_title"])}">
          <div class="wrap">
            <a class="season-banner-link" href="#{esc(href)}">
              <span class="season-banner-motif" aria-hidden="true">#{theme["svg"]}</span>
              <span class="season-banner-title">#{esc(hub["banner_title"])}</span>
              <span class="season-banner-hook">#{esc(hub["hook"])}</span>
              <span class="season-banner-cta">#{esc(hub["link_label"])}</span>
            </a>
          </div>
        </nav>
      HTML
    end

    def prepare_hub(hub, cities, data, lights, today, site_url)
      return nil unless hub.is_a?(Hash)

      id = hub["id"].to_s.strip
      path = normalize_path(hub["path"])
      title = hub["title"].to_s.strip
      start_s = hub.dig("season", "start").to_s
      end_s = hub.dig("season", "end").to_s
      return nil if id.empty? || title.empty? || path == "/"
      return nil unless month_day(start_s) && month_day(end_s)

      theme = hub["theme"].is_a?(Hash) ? hub["theme"] : {}
      svg = safe_svg(theme["svg"])
      sections = sections_for(hub, cities, data, lights, today, site_url)
      label = season_label(start_s, end_s)
      in_season = in_season?(today, start_s, end_s)
      suggest = hub["suggest"].is_a?(Hash) ? hub["suggest"] : {}
      displays = light_displays(hub, lights, cities)
      {
        "id" => id,
        "path" => path,
        "title" => title,
        "description" => hub["description"].to_s.strip,
        "banner_title" => presence(hub["banner_title"], title),
        "hook" => hub["hook"].to_s.strip,
        "link_label" => presence(hub["link_label"], "See events"),
        "llms" => presence(hub["llms"], hub["hook"]),
        "season_label" => label,
        "in_season" => in_season,
        "ends_on" => season_end_on(today, start_s, end_s),
        "footer" => hub["footer"] == true,
        "footer_label" => presence(hub["footer_label"], title),
        "intro" => intro_for(hub, label, in_season, sections),
        "empty" => presence(hub["empty"], "Nothing is listed yet. City pages are where each event is written up, and this page gathers them."),
        "suggest_lead" => suggest["lead"].to_s.strip,
        "suggest_link" => presence(suggest["link"], "Tell us"),
        "suggest_subject" => suggest["subject"].to_s.lstrip,
        "suggest_body" => suggest["body"].to_s.strip,
        "sections" => sections,
        "visible_events" => sections.flat_map { |section| section["events"] },
        "lights_map" => !hub["lights"].to_s.strip.empty?,
        "light_displays" => displays,
        "light_towns" => light_towns(displays),
        "theme" => {
          "background" => hex_color(theme["background"], "#f4efe6"),
          "ink" => hex_color(theme["ink"], "#1a2822"),
          "muted" => hex_color(theme["muted"], "#3f5148"),
          "link" => hex_color(theme["link"], "#145c40"),
          "svg" => svg
        }
      }
    end

    def intro_for(hub, label, in_season, sections)
      if in_season
        text = hub["in_season_intro"].to_s.strip
        return text unless text.empty?

        return "#{hub["hook"].to_s.strip} Listed through #{label.split(" through ").last}."
      end

      if sections.empty?
        text = hub["off_season_intro"].to_s.strip
        return text unless text.empty?

        "The season runs #{label}."
      else
        text = hub["off_season_listed"].to_s.strip
        return text unless text.empty?

        "The season runs #{label}. Dates already set are listed below."
      end
    end

    def presence(value, fallback)
      text = value.to_s.strip
      text.empty? ? fallback : text
    end

    def city_names(cities)
      names = {}
      Array(cities).each do |city|
        next unless city.is_a?(Hash)

        names[city["id"].to_s] = city["name"].to_s.strip
      end
      names
    end

    def event_row(event, city_id, city_name, site_url)
      start_s = event["start"].to_s
      finish_s = event["end"].to_s
      row = row_dates(event["name"], city_name, city_id, event["place"], event["same_as"], start_s, finish_s, site_url)
      row["tags"] = Array(event["tags"]).map(&:to_s)
      row
    end

    def display_row(row, names, site_url)
      return nil unless row.is_a?(Hash)

      same = row["same_as"].to_s.strip
      return nil unless same.match?(%r{\Ahttps?://\S+\z})

      city_id = row["city"].to_s.strip
      city_name = names[city_id].to_s
      return nil if city_name.empty?

      name = row["name"].to_s.strip
      return nil if name.empty?

      start_s = row["start"].to_s
      finish_s = row["end"].to_s
      row_dates(name, city_name, city_id, public_area(row["area"] || row["place"]), same, start_s, finish_s, site_url)
    end

    def row_dates(name, city_name, city_id, place, same, start_s, finish_s, site_url)
      start_on = date_only(start_s)
      finish_on = date_only(finish_s) || start_on
      clean_name = name.to_s.strip
      place_name, street = EventCalendar.place_parts(place.to_s, city_name)
      place_name = city_name if place_name.empty?
      same_clean = same.to_s.strip
      href = if same_clean.match?(%r{\Ahttps?://\S+\z})
               same_clean
             else
               "#{site_url.to_s.sub(%r{/+\z}, "")}/#{city_id}/"
             end
      start_parsed = EventCalendar.parse_when(start_s)
      finish_parsed = EventCalendar.parse_when(finish_s)
      schema_finish = EventCalendar.schema_end(start_parsed, finish_parsed)
      {
        "name" => clean_name,
        "city" => city_name,
        "city_id" => city_id,
        "place" => place_name,
        "when" => when_text(start_s, finish_s),
        "same_as" => same_clean,
        "sort" => start_on ? start_on.iso8601 : "9999-99-99",
        "start_raw" => start_s.to_s,
        "end_raw" => finish_s.to_s,
        "end_on" => finish_on ? finish_on.iso8601 : "",
        "url" => href,
        "description" => "#{clean_name} in #{city_name}.",
        "startDate" => EventCalendar.format_offset_time(start_parsed).to_s,
        "endDate" => EventCalendar.format_offset_time(schema_finish).to_s,
        "street" => street.to_s,
        "locality" => city_name,
        "sameAs" => ""
      }
    end

    def upcoming_row?(row, today)
      finish = date_only(row["end_on"])
      finish && finish >= today
    end

    def when_text(start_s, finish_s)
      start_on = date_only(start_s)
      return "" unless start_on

      parsed = EventCalendar.parse_when(start_s)
      finish = EventCalendar.parse_when(finish_s)
      finish_on = date_only(finish_s)
      if ongoing_span?(parsed, start_on, finish_on)
        return "Through #{EventCalendar.month_day(finish_on)}"
      end
      return EventCalendar.when_label(parsed, finish) if parsed

      label = EventCalendar.month_day(start_on)
      if finish_on && finish_on > start_on
        "#{label} to #{EventCalendar.month_day(finish_on)}"
      else
        label
      end
    end

    # A date-only run of a week or more, such as a pumpkin patch.
    def ongoing_span?(parsed, start_on, finish_on)
      return false unless parsed && parsed[:time].nil? && start_on && finish_on

      (finish_on - start_on).to_i >= 7
    end

    def section_payload(section, items)
      title = section["title"].to_s
      {
        "id" => section["id"].to_s,
        "title" => title,
        "toc" => presence(section["toc"], title),
        "intro" => section["intro"].to_s.strip,
        "events" => items
      }
    end

    def date_only(value)
      str = value.to_s
      return nil unless str.match?(/\A\d{4}-\d{2}-\d{2}/)

      Date.iso8601(str[0, 10])
    rescue Date::Error, ArgumentError
      nil
    end

    LIGHT_TYPES = {
      "park" => "Park",
      "house" => "House",
      "street" => "Street"
    }.freeze

    def light_displays(hub, lights, cities)
      return [] if hub["lights"].to_s.strip.empty?

      names = city_names(cities)
      rows = Array(lights).filter_map { |row| light_row(row, names) }
      rows.sort_by! { |item| [item["city"].to_s, item["name"].to_s] }
      counts = Hash.new(0)
      rows.each do |item|
        counts[item["city_id"]] += 1
        item["number"] = counts[item["city_id"]]
      end
      rows
    end

    def light_towns(displays)
      seen = {}
      Array(displays).filter_map do |item|
        city_id = item["city_id"].to_s
        next if city_id.empty? || seen[city_id]

        seen[city_id] = true
        rows = displays.select { |row| row["city_id"].to_s == city_id }
        pins = rows.map { |row| "#{row["number"]} #{row["name"]}" }
        {
          "id" => city_id,
          "name" => item["city"].to_s,
          "count" => rows.size,
          "map" => "/assets/maps/lights/#{city_id}.svg",
          "map_alt" => "Map of #{item["city"]} with Christmas light pins: #{pins.join(", ")}."
        }
      end
    end

    def light_row(row, names)
      return nil unless row.is_a?(Hash)

      city_id = row["city"].to_s.strip
      city_name = names[city_id].to_s
      return nil if city_name.empty?

      name = row["name"].to_s.strip
      return nil if name.empty?

      type = row["type"].to_s.strip
      return nil unless LIGHT_TYPES.key?(type)

      address = row["address"].to_s.gsub(/\s+/, " ").strip
      return nil if address.empty?

      description = row["description"].to_s.gsub(/\s+/, " ").strip
      return nil if description.empty?

      source = row["source"].to_s.strip
      return nil unless source.match?(%r{\Ahttps?://\S+\z})

      begin
        lat = Float(row["lat"])
        lng = Float(row["lng"])
      rescue ArgumentError, TypeError
        return nil
      end
      return nil unless lat.between?(45.0, 49.5) && lng.between?(-125.0, -116.0)

      slug = light_slug(row["id"], name)
      {
        "id" => slug,
        "name" => name,
        "type" => type,
        "type_label" => LIGHT_TYPES[type],
        "city" => city_name,
        "city_id" => city_id,
        "address" => address,
        "description" => description,
        "nights" => row["nights"].to_s.gsub(/\s+/, " ").strip,
        "hours" => row["hours"].to_s.gsub(/\s+/, " ").strip,
        "source" => source,
        "free" => row["free"] == true,
        "last_verified" => row["last_verified"].to_s.strip
      }
    end

    def light_slug(id, name)
      raw = id.to_s.strip
      raw = name.to_s if raw.empty?
      slug = raw.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|\-\z/, "")
      slug.empty? ? "display" : slug
    end

    def esc(text)
      CGI.escapeHTML(text.to_s)
    end

    # Own photo, then that venue, then a themed picture, then a text card
    # with no image. A venue or theme file is used once on a page. The
    # city hero is not in this chain.
    def attach_cards!(hub, site, pages, catalog, venues, groups)
      used = {}
      chosen = {}
      audit = { "own" => [], "venue" => [], "theme" => [], "none" => [] }
      Array(hub["sections"]).each do |section|
        Array(section["events"]).each do |event|
          page = pages[event["city_id"].to_s]
          key = "#{event["city_id"]}|#{event["name"]}"
          card = find_card(catalog, event)
          blurb = card ? card[:blurb].to_s : ""
          blurb = "#{event["name"]} in #{event["city"]}." if blurb.empty?
          event["blurb"] = blurb
          event["description"] = blurb
          event["calendar"] = calendar_href(page, event)
          event["calendar"] = write_calendar(site, event) if event["calendar"].empty?

          if chosen.key?(key)
            prev = chosen[key]
            # The same event in a second section may repeat its own photo.
            # A venue or theme file stays once on the page.
            photo = prev && prev["kind"] == "own" ? prev : nil
            apply_photo!(event, photo)
            record_photo!(audit, event, photo)
            next
          end

          photo = pick_photo(photo_candidates(event, card, venues, groups), used)
          chosen[key] = photo
          apply_photo!(event, photo)
          record_photo!(audit, event, photo)
        end
      end
      parts = audit.map { |kind, names| "#{kind} #{names.size}" }
      Jekyll.logger.info("Hub photos:", "#{hub["path"]} #{parts.join(", ")}")
      audit.each do |kind, names|
        next if names.empty?

        Jekyll.logger.info("Hub photos:", "  #{kind}: #{names.join("; ")}")
      end
    end

    def index_card_photos!(site, pages, catalog, venues, groups)
      options = {}
      Array(site.data["cities"]).each do |city|
        next unless city.is_a?(Hash)

        city_id = city["id"].to_s
        next if city_id.empty?

        bucket = {}
        Array(site.data["#{city_id}_events"]).each do |event|
          next unless event.is_a?(Hash)

          name = event["name"].to_s
          next if name.empty?

          row = event.merge("city_id" => city_id, "city" => city["name"].to_s)
          card = find_card(catalog, row)
          bucket[name] = photo_candidates(row, card, venues, groups).map { |photo| public_photo(photo) }
        end
        options[city_id] = bucket
      end
      site.data["card_photo_options"] = options
    end

    def photo_candidates(event, card, venues, groups)
      list = []
      own = usable_own(card && card[:photo])
      list << own if own
      matching_venues(event, venues).each do |entry|
        photo = listed_photo(entry, "venue")
        list << photo if photo
      end
      theme = matching_theme(event, groups)
      Array(theme && theme["images"]).each do |entry|
        photo = listed_photo(entry, "theme")
        list << photo if photo
      end
      list.uniq { |photo| photo["src"] }
    end

    def pick_photo(candidates, used)
      candidates.each do |photo|
        next if photo["kind"] != "own" && used[photo["src"]]

        used[photo["src"]] = true if photo["kind"] != "own"
        return photo
      end
      nil
    end

    def apply_photo!(event, photo)
      if photo
        alt = photo["alt"].to_s.strip
        alt = "#{event["name"]} in #{event["city"]}" if alt.empty? || alt.start_with?("Photo:")
        event["image"] = photo["src"]
        event["image_alt"] = alt
        event["image_credit"] = photo["credit"].to_s
        event["image_source"] = photo["source"].to_s
        event["image_kind"] = photo["kind"]
      else
        event.delete("image")
        event["image_kind"] = "none"
      end
    end

    def record_photo!(audit, event, photo)
      kind = photo ? photo["kind"] : "none"
      label = "#{event["name"]} (#{event["city"]})"
      label = "#{label} [#{File.basename(photo["src"])}]" if photo
      audit[kind] << label
    end

    def public_photo(photo)
      {
        "src" => photo["src"],
        "alt" => photo["alt"],
        "credit" => photo["credit"],
        "source" => photo["source"],
        "kind" => photo["kind"]
      }
    end

    def usable_own(photo)
      licensed = licensed_photo(photo)
      return nil unless licensed
      return nil if people_photo?(licensed)

      licensed.merge("kind" => "own")
    end

    def listed_photo(entry, kind)
      return nil unless entry.is_a?(Hash)

      photo = licensed_photo(
        "src" => entry["image"],
        "alt" => entry["alt"],
        "credit" => entry["credit"],
        "source" => entry["source"]
      )
      return nil unless photo
      return nil if people_photo?(photo)

      photo.merge("kind" => kind)
    end

    def matching_venues(event, venues)
      hay = "#{event["name"]} #{event["place"]}".downcase
      Array(venues).select do |venue|
        keys_hit?(venue, hay, [])
      end
    end

    # A specific event type in the name or place wins over a broad tag,
    # so a pumpkin patch that is also tagged as a maze still shows
    # pumpkins. A trunk-or-treat tag wins over a title that only says
    # "fall festival".
    def matching_theme(event, groups)
      tags = Array(event["tags"]).map { |tag| tag.to_s.downcase }
      hay = "#{event["name"]} #{event["place"]}".downcase
      if tags.include?("trunk-or-treat") || hay.include?("trunk-or-treat") || hay.include?("trunk or treat")
        trunk = Array(groups).find { |group| keys_hit?(group, "trunk or treat", []) }
        return trunk if trunk
      end

      named = Array(groups).find { |group| keys_hit?(group, hay, []) }
      return named if named

      Array(groups).find { |group| keys_hit?(group, "", tags) }
    end

    def keys_hit?(entry, hay, tags)
      Array(entry["keys"]).any? do |key|
        text = key.to_s.downcase.strip
        next false if text.empty?

        tags.include?(text) || (!hay.empty? && hay.include?(text))
      end
    end

    def people_photo?(photo)
      src = photo["src"].to_s
      return true if src.include?("teen-lounge") || src.include?("red-barn-festival")

      alt = photo["alt"].to_s.gsub(/children's museum/i, "")
      alt.match?(/\b(child|children|teen|teens|toddler|baby)\b/i)
    end

    def city_pages(site)
      pages = {}
      site.pages.each do |page|
        next unless page.data["layout"] == "city"

        pages[page.data["city"].to_s] = page
      end
      pages
    end

    def card_catalog(pages)
      catalog = Hash.new { |hash, key| hash[key] = [] }
      pages.each do |city_id, page|
        EventCalendar.markdown_headings(page.content).each do |heading|
          catalog[city_id] << {
            key: EventCalendar.normalize(heading[:text]),
            blurb: one_line_blurb(heading[:body]),
            photo: parse_photo_include(heading[:body])
          }
        end
      end
      catalog
    end

    def find_card(catalog, event)
      cards = catalog[event["city_id"].to_s] || []
      key = EventCalendar.normalize(event["name"])
      exact = cards.find { |card| card[:key] == key }
      return exact if exact

      best = nil
      best_score = 0
      cards.each do |card|
        score = EventCalendar.match_score(key, card[:key])
        next unless score > best_score

        best = card
        best_score = score
      end
      best_score >= 90 ? best : nil
    end

    def licensed_photo(photo)
      return nil unless photo.is_a?(Hash)

      src = photo["src"].to_s.strip
      credit = photo["credit"].to_s.strip
      source = photo["source"].to_s.strip
      return nil if src.empty?
      return nil if credit.empty? && source.empty?
      return nil unless src.start_with?("/")

      photo.merge("src" => src, "credit" => credit, "source" => source)
    end

    def parse_photo_include(body)
      match = body.to_s.match(/\{%\s*include\s+event-photo\.html\s+(.*?)\s*%\}/m)
      return nil unless match

      args = match[1]
      {
        "src" => liquid_arg(args, "src"),
        "alt" => liquid_arg(args, "alt"),
        "credit" => liquid_arg(args, "credit"),
        "source" => liquid_arg(args, "source")
      }
    end

    def liquid_arg(args, name)
      if (match = args.match(/#{Regexp.escape(name)}\s*=\s*"([^"]*)"/m))
        match[1]
      elsif (match = args.match(/#{Regexp.escape(name)}\s*=\s*'([^']*)'/m))
        match[1]
      else
        ""
      end
    end

    def one_line_blurb(body)
      text = body.to_s.gsub(/\r\n?/, "\n")
      text = text.gsub(/\{%.*?%\}/m, " ")
      text = text.gsub(%r{<p class="event-(?:when|place)">.*?</p>}mi, " ")
      text = text.gsub(/<[^>]+>/, " ")
      text = text.gsub(/\[[^\]]+\]\([^)]+\)/, " ")
      text = text.gsub(/[*_]+/, "")
      text = text.gsub(/\s+/, " ").strip
      return "" if text.empty?

      sentences = text.split(/(?<=[.!?])\s+/).map(&:strip).reject(&:empty?)
      sentence = sentences.find { |line| !meta_sentence?(line) } || sentences.first.to_s
      return sentence if sentence.length <= 150

      cut = sentence[0, 148]
      spot = cut.rindex(" ")
      trimmed = spot && spot > 40 ? cut[0, spot] : cut
      "#{trimmed.rstrip.sub(/[,:;]\z/, "")}..."
    end

    def meta_sentence?(sentence)
      text = sentence.to_s.downcase
      text.include?("city page") || text.include?("listed here") || text.include?("this calendar")
    end

    def calendar_href(page, event)
      return "" unless page

      groups = page.data["calendar_groups"]
      return "" unless groups.is_a?(Hash)

      start_parsed = EventCalendar.parse_when(event["start_raw"])
      return "" unless start_parsed

      want = EventCalendar.file_slug(event["name"], start_parsed)
      groups.each_value do |bucket|
        Array(bucket).flatten.each do |link|
          return link[:href].to_s if link[:href].to_s.include?(want)
        end
      end
      ""
    end

    def write_calendar(site, event)
      start_parsed = EventCalendar.parse_when(event["start_raw"])
      return "" unless start_parsed

      city_id = event["city_id"].to_s
      return "" if city_id.empty?

      slug = EventCalendar.file_slug(event["name"], start_parsed)
      dir = "#{city_id}/calendar"
      filename = "#{slug}.ics"
      href = EventCalendar.root_path(site, "/#{dir}/#{filename}")
      already = site.static_files.any? { |file| file.respond_to?(:relative_path) && file.relative_path == "#{dir}/#{filename}" }
      return href if already

      city_url = EventCalendar.absolute_url(site, "/#{city_id}/")
      same = event["same_as"].to_s
      page_url = EventCalendar.http_url?(same) ? same : city_url
      record = {
        name: event["name"],
        start: start_parsed,
        end: EventCalendar.parse_when(event["end_raw"]),
        place: event["place"].to_s,
        same_as: same,
        uid: "#{city_id}-#{slug}@eastsidecalendar.com",
        url: page_url,
        description: EventCalendar.description_for(
          { same_as: same, start: start_parsed, end: EventCalendar.parse_when(event["end_raw"]) },
          event["blurb"].to_s,
          city_url
        )
      }
      site.static_files << CalendarFile.new(dir, filename, EventCalendar.build_ics(record, city_url, EventCalendar.stamp_utc(site.time)))
      href
    end
  end

  class SeasonalHubsGenerator < Jekyll::Generator
    # After the city calendar files exist, so hub cards can link to them.
    priority :lowest

    def generate(site)
      raw = site.data["seasonal_hubs"]
      config = raw.is_a?(Hash) ? raw : {}
      today = EventCalendar.pacific_today(site.time)
      lights = site.data["holiday_lights"]
      site_url = site.config["url"].to_s
      prepared = Array(config["hubs"]).filter_map do |hub|
        SeasonalHubs.prepare_hub(hub, site.data["cities"], site.data, lights, today, site_url)
      end
      pages = SeasonalHubs.city_pages(site)
      catalog = SeasonalHubs.card_catalog(pages)
      venues = site.data.dig("venue_images", "venues")
      groups = site.data.dig("theme_images", "groups")
      SeasonalHubs.index_card_photos!(site, pages, catalog, venues, groups)
      prepared.each { |hub| SeasonalHubs.attach_cards!(hub, site, pages, catalog, venues, groups) }

      rule = SeasonalHubs.banner_rule(config)
      chosen = SeasonalHubs.banner_choice(prepared, rule, today)
      if chosen && !chosen.dig("theme", "svg").to_s.empty?
        site.data["seasonal_banner"] = {
          "path" => chosen["path"],
          "html" => SeasonalHubs.banner_html(chosen, site.baseurl.to_s)
        }
      else
        site.data["seasonal_banner"] = nil
      end

      pages = {}
      public_hubs = []
      prepared.each do |hub|
        pages[hub["id"]] = hub
        public_hubs << {
          "title" => hub["title"],
          "path" => hub["path"],
          "llms" => hub["llms"],
          "season_label" => hub["season_label"],
          "footer" => hub["footer"],
          "footer_label" => hub["footer_label"]
        }
        site.pages << hub_page(site, hub)
      end
      site.data["hub_pages"] = pages
      site.data["seasonal_hubs"] = public_hubs
    end

    def hub_page(site, hub)
      page = Jekyll::PageWithoutAFile.new(site, site.source, hub["id"], "index.html")
      page.data["layout"] = "seasonal"
      page.data["title"] = hub["title"]
      page.data["description"] = hub["description"]
      page.data["permalink"] = hub["path"]
      page.data["hub_id"] = hub["id"]
      page.data["visible_events"] = hub["visible_events"]
      page.data["last_modified_at"] = EventCalendar.pacific_time(site.time)
      page.content = ""
      page
    end
  end

  class SeasonalBannerTag < Liquid::Tag
    def render(context)
      site = context.registers[:site]
      page = context.registers[:page]
      banner = site.data["seasonal_banner"]
      return "" unless banner.is_a?(Hash)

      page_url = page.respond_to?(:[]) ? page["url"] : ""
      return "" if SeasonalHubs.same_page?(page_url, banner["path"])

      banner["html"].to_s
    end
  end

end

Liquid::Template.register_tag("seasonal_banner", EastsideCalendar::SeasonalBannerTag)
