# frozen_string_literal: true

require "cgi"
require "date"

module EastsideCalendar
  # Seasonal hubs and the one sitewide banner are data in
  # _data/seasonal_hubs.yml. A new season is a new entry there.
  module SeasonalHubs
    HEX = /\A#[0-9a-fA-F]{6}\z/
    MONTHS = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec].freeze
    FULL_MONTHS = %w[January February March April May June July August September October November December].freeze
    WDAYS = %w[Sun Mon Tue Wed Thu Fri Sat].freeze

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
      TextUtil.month_day_number(value)
    end

    def season_label(start_s, end_s)
      "#{month_day_label(start_s)} through #{month_day_label(end_s)}"
    end

    def month_day_label(value)
      month, day = month_day(value)
      return value.to_s unless month

      "#{MONTHS[month - 1]} #{day}"
    end

    SVG_TAGS = %w[svg g path circle rect ellipse line polyline polygon title desc].freeze
    SVG_ATTRS = %w[
      xmlns viewbox fill d cx cy r rx ry x y width height points
      stroke stroke-width stroke-linecap stroke-linejoin
      aria-hidden focusable transform opacity fill-rule clip-rule
      x1 y1 x2 y2
    ].freeze

    # Motifs are small icons. Only those tags and presentation attributes
    # are kept. A script, a handler, or an unknown tag drops the drawing.
    def safe_svg(value)
      svg = value.to_s.strip
      return "" if svg.empty?
      return "" unless svg.match?(/\A<svg\b/i) && svg.match?(%r{</svg>\z}i)

      tags = svg.scan(%r{</?([A-Za-z0-9]+)}).flatten.map(&:downcase)
      return "" unless tags.all? { |tag| SVG_TAGS.include?(tag) }

      svg.scan(/<[^>]+>/).each do |tag|
        return "" if tag.match?(/javascript:|data:/i)

        tag.scan(/([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=/).flatten.each do |attr|
          return "" unless SVG_ATTRS.include?(attr.downcase)
        end
      end
      svg
    end

    def hex_color(value, fallback)
      text = value.to_s.strip
      text.match?(HEX) ? text : fallback
    end

    # Tags that pull Worth the drive rows onto a hub. Fall and Christmas
    # are named here. Any other hub uses its own section tags, and the
    # section is omitted when nothing matches.
    DRIVE_HUB_TAGS = {
      "fall" => %w[pumpkin-patch corn-maze u-pick harvest],
      "christmas" => %w[holiday-lights tree-farm]
    }.freeze

    DRIVE_PAGE_SECTIONS = [
      {
        "id" => "patches",
        "title" => "Pumpkin patches and corn mazes",
        "toc" => "Pumpkin patches and corn mazes",
        "intro" => "Big patches and mazes a little outside the Eastside.",
        "tags" => %w[pumpkin-patch corn-maze u-pick harvest]
      },
      {
        "id" => "family-days",
        "title" => "Family days",
        "toc" => "Family days",
        "intro" => "Kid activities and family hours, not a day at the betting windows.",
        "tags" => %w[family-day]
      },
      {
        "id" => "trees",
        "title" => "Tree farms",
        "toc" => "Tree farms",
        "intro" => "Choose-and-cut farms worth the drive.",
        "tags" => %w[tree-farm]
      },
      {
        "id" => "lights",
        "title" => "Light shows",
        "toc" => "Light shows",
        "intro" => "Big holiday light walks the kids will talk about on the way home.",
        "tags" => %w[holiday-lights]
      }
    ].freeze

    def sections_for(hub, cities, data, today, site_url)
      if hub["group"].to_s == "town"
        return append_drive_section(town_sections(hub, cities, data, today, site_url), hub, data, today, site_url)
      end

      districts = Array(hub["districts"]).select { |district| district.is_a?(Hash) }
      return district_sections(hub, districts, cities, data, today, site_url) unless districts.empty?

      names = city_names(cities)
      grouped = Hash.new { |hash, key| hash[key] = [] }
      seen = Hash.new { |hash, key| hash[key] = {} }

      names.each_key do |city_id|
        Array(data["#{city_id}_events"]).each do |event|
          next unless event.is_a?(Hash)

          Array(hub["sections"]).each do |section|
            next unless section.is_a?(Hash)
            next unless section_match?(event, section)

            row = event_row(event, city_id, names[city_id], site_url)
            next unless upcoming_row?(row, today)

            key = "#{row["city_id"]}|#{row["name"]}|#{row["sort"]}"
            next if seen[section["id"]][key]

            seen[section["id"]][key] = true
            grouped[section["id"]] << row
          end
        end
      end

      sections = Array(hub["sections"]).filter_map do |section|
        next unless section.is_a?(Hash)

        items = grouped[section["id"]].sort_by { |item| [item["sort"], item["name"].to_s] }
        next if items.empty?

        section_payload(section, items)
      end
      append_drive_section(sections, hub, data, today, site_url)
    end

    # School-district date sections, then Monday weeks of matching events.
    # Off season this returns nothing, so the page uses the shared empty state.
    def district_sections(hub, districts, cities, data, today, site_url)
      start_s = hub.dig("season", "start").to_s
      end_s = hub.dig("season", "end").to_s
      return [] unless in_season?(today, start_s, end_s)

      sections = []
      if district_year?(hub, today, start_s, end_s)
        districts.each do |district|
          sections << section_payload(district.merge("intro" => spring_break_intro(hub, district, data)), [])
        end
      end
      sections + week_sections(matching_rows(hub, cities, data, today, site_url))
    end

    def district_year?(hub, today, start_s, end_s)
      year = Integer(hub["calendar_year"])
      return false unless year.positive?

      season_end_on(today, start_s, end_s)&.year == year
    rescue ArgumentError, TypeError
      false
    end

    def matching_rows(hub, cities, data, today, site_url)
      matcher = {
        "id" => hub["id"],
        "tags" => hub["tags"],
        "keywords" => hub["keywords"]
      }
      rows = []
      seen = {}
      names = city_names(cities)
      names.each_key do |city_id|
        Array(data["#{city_id}_events"]).each do |event|
          next unless event.is_a?(Hash)
          next unless section_match?(event, matcher)

          row = event_row(event, city_id, names[city_id], site_url)
          next unless upcoming_row?(row, today)

          key = "#{row["city_id"]}|#{row["name"]}|#{row["sort"]}"
          next if seen[key]

          seen[key] = true
          rows << row
        end
      end
      rows
    end

    # An event is listed in every Monday-Sunday week its dates overlap.
    def week_sections(rows)
      buckets = Hash.new { |hash, key| hash[key] = [] }
      rows.each do |row|
        start_on = date_only(row["sort"])
        next unless start_on

        finish_on = date_only(row["end_on"]) || start_on
        finish_on = start_on if finish_on < start_on
        monday = start_on - ((start_on.wday + 6) % 7)
        last = finish_on - ((finish_on.wday + 6) % 7)
        while monday <= last
          buckets[monday] << row
          monday += 7
        end
      end
      buckets.keys.sort.map do |monday|
        items = buckets[monday].sort_by { |item| [item["sort"], item["name"].to_s] }
        label = "Week of #{Date::MONTHNAMES[monday.month]} #{monday.day}"
        {
          "id" => "week-#{monday.iso8601}",
          "title" => label,
          "toc" => label,
          "intro" => "",
          "events" => items
        }
      end
    end

    def drive_match_tags(hub)
      named = DRIVE_HUB_TAGS[hub["id"].to_s]
      return named if named

      Array(hub["sections"]).flat_map { |section| Array(section["tags"]).map(&:to_s) }.uniq
    end

    def drive_section_intro(hub)
      case hub["id"].to_s
      when "fall"
        "Corn mazes and pumpkin patches a little outside the Eastside."
      when "christmas"
        "Tree farms and big light shows a little outside the Eastside."
      else
        "A little outside the Eastside, and worth the trip."
      end
    end

    # One section at the bottom, from _data/worth_the_drive_events.yml.
    # These rows are not city events, so they stay off city pages.
    def append_drive_section(sections, hub, data, today, site_url)
      tags = drive_match_tags(hub)
      return sections if tags.empty?

      items = drive_rows(data["worth_the_drive_events"], tags, today, site_url)
      return sections if items.empty?

      sections + [section_payload({
        "id" => "worth-the-drive",
        "title" => "Worth the drive",
        "toc" => "Worth the drive",
        "intro" => drive_section_intro(hub)
      }, items)]
    end

    def drive_rows(events, tags, today, site_url)
      want = Array(tags).map(&:to_s)
      seen = {}
      items = []
      Array(events).each do |event|
        next unless event.is_a?(Hash)

        event_tags = Array(event["tags"]).map(&:to_s)
        next if (event_tags & want).empty?

        town = event["town"].to_s.strip
        town = "Nearby" if town.empty?
        row = event_row(event, "worth-the-drive", town, site_url)
        next unless upcoming_row?(row, today)

        key = "#{row["name"]}|#{row["sort"]}"
        next if seen[key]

        seen[key] = true
        items << row
      end
      items.sort_by { |item| [item["sort"], item["name"].to_s] }
    end

    def prepare_drive(events, today, site_url)
      sections = DRIVE_PAGE_SECTIONS.filter_map do |section|
        items = drive_rows(events, section["tags"], today, site_url)
        next if items.empty?

        section_payload(section, items)
      end
      {
        "id" => "worth-the-drive",
        "path" => "/worth-the-drive/",
        "title" => "Family outings worth the drive",
        "description" => "Pumpkin patches, corn mazes, tree farms, and big light shows a little outside the Eastside. Each card shows the town and a rough drive time from Bellevue.",
        "banner_title" => "Worth the drive",
        "hook" => "A little outside the Eastside, and worth the trip.",
        "link_label" => "See events",
        "llms" => "Family outings a little outside the Eastside, with the town and a rough drive time from Bellevue.",
        "season_label" => "",
        "in_season" => false,
        "ends_on" => nil,
        "footer" => false,
        "footer_label" => "Worth the drive",
        "intro" => "These places sit a little outside the Eastside. We only list them when the trip is worth it: a big pumpkin patch, a corn maze, a tree farm, or a light show the kids will still be talking about on the way home. The time on each card is a rough drive from Bellevue, before traffic.",
        "empty" => "Nothing is listed right now. We add a place only when the dates are set and the trip is worth it.",
        "suggest_lead" => "",
        "suggest_link" => "",
        "suggest_subject" => "",
        "suggest_body" => "",
        "sections" => sections,
        "visible_events" => sections.flat_map { |section| section["events"] },
        "theme" => {
          "background" => "#f4efe6",
          "ink" => "#1a2822",
          "muted" => "#3f5148",
          "link" => "#145c40",
          "dark" => {
            "background" => "#2a2433",
            "ink" => "#f6efe4",
            "muted" => "#d2c3ae",
            "link" => "#8fd4b0"
          },
          "svg" => safe_svg('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path fill="#8a5a22" d="M8.2 12.2c0-2.2 1.5-3.6 3.8-3.6s3.8 1.4 3.8 3.6c0 3.3-1.6 6.2-3.8 6.2s-3.8-2.9-3.8-6.2z"/><path fill="#6b4e0e" d="M11.2 9.2h1.6v8.4h-1.6z"/><path fill="#1e4636" d="M12 5.4c.3 1 .2 1.8-.2 2.4 1.2-.2 2-.8 2.2-1.8-.8-.5-1.5-.7-2-.6z"/></svg>')
        }
      }
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

    def section_match?(event, section)
      return false if rainy_section?(section) && EventLabels.camp?(event)

      tags = Array(event["tags"]).map(&:to_s)
      name = event["name"].to_s.downcase
      wanted = section["match_setting"].to_s.strip
      if !wanted.empty? && EventLabels.setting_label(event).casecmp(wanted).zero?
        return true
      end

      section_tags = Array(section["tags"]).map(&:to_s)
      return true unless (tags & section_tags).empty?

      phrases(section["keywords"]).any? { |phrase| name.include?(phrase) }
    end

    def rainy_section?(section)
      section["id"].to_s == "rainy-day" || Array(section["tags"]).map(&:to_s).include?("rainy-day")
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

    # Calendar order by season start. The in-season hub whose season ends
    # soonest leads, and the rest follow in that same calendar order.
    def footer_seasons(hubs)
      calendar = Array(hubs).sort_by do |hub|
        [month_day_ord(hub["season_start"]) || 9999, hub["path"].to_s]
      end
      lead = calendar.select { |hub| hub["in_season"] }.min_by do |hub|
        [hub["ends_on"] || Date.new(9999, 12, 31), month_day_ord(hub["season_start"]) || 9999]
      end
      ordered = calendar
      if lead
        index = calendar.index(lead)
        ordered = calendar.rotate(index) if index
      end
      ordered.map do |hub|
        {
          "id" => hub["id"],
          "path" => hub["path"],
          "label" => hub["footer_label"]
        }
      end
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

    # Four links for the missing page, two rows of two on a wide screen.
    # The second tile is whichever hub the seasonal banner is showing, so
    # a banner change switches that tile. Photos are the share-card pictures.
    def missing_tiles(cards, hubs, banner)
      tiles = []
      weekend = share_by_id(cards, "this-weekend")
      tiles << link_tile(weekend, "This weekend", "What's happening this weekend.") if weekend

      if banner.is_a?(Hash)
        path = banner["path"]
        hub = Array(hubs).find { |item| normalize_path(item["path"]) == normalize_path(path) }
        share = share_by_path(cards, path)
        tiles << hub_tile(hub, share) if hub && share
      end

      play = share_by_id(cards, "playgrounds")
      tiles << link_tile(play, "Playgrounds", "Find a playground near you.") if play

      markets = share_by_id(cards, "farmers-markets")
      tiles << link_tile(markets, "Farmers markets", "See which markets are open now.") if markets
      tiles
    end

    def hub_tile(hub, share)
      title = hub["banner_title"].to_s.strip
      title = hub["footer_label"].to_s.strip if title.empty?
      blurb = hub["hook"].to_s.strip
      blurb = "See what's listed." if blurb.empty?
      link_tile(share, title, blurb)
    end

    def link_tile(card, title, blurb)
      {
        "title" => title,
        "href" => normalize_path(card["path"]),
        "blurb" => blurb,
        "image" => card["image"].to_s,
        "alt" => card["alt"].to_s,
        "credit" => card["credit"].to_s,
        "stretch" => true
      }
    end

    def share_by_id(cards, id)
      Array(cards).find { |card| card.is_a?(Hash) && card["id"].to_s == id }
    end

    def share_by_path(cards, path)
      want = normalize_path(path)
      Array(cards).find { |card| card.is_a?(Hash) && normalize_path(card["path"]) == want }
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

    def theme_style(theme)
      theme = {} unless theme.is_a?(Hash)
      dark = theme["dark"].is_a?(Hash) ? theme["dark"] : {}
      [
        "--season-bg-light: #{theme["background"]}",
        "--season-ink-light: #{theme["ink"]}",
        "--season-muted-light: #{theme["muted"]}",
        "--season-link-light: #{theme["link"]}",
        "--season-bg-dark: #{dark["background"]}",
        "--season-ink-dark: #{dark["ink"]}",
        "--season-muted-dark: #{dark["muted"]}",
        "--season-link-dark: #{dark["link"]}"
      ].join("; ")
    end

    def banner_html(hub, baseurl)
      theme = hub["theme"] || {}
      href = "#{baseurl}#{hub["path"]}"
      style = theme_style(theme)
      <<~HTML.strip
        <nav class="season-banner" style="#{style}">
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

    def prepare_hub(hub, cities, data, today, site_url)
      return nil unless hub.is_a?(Hash)

      id = hub["id"].to_s.strip
      path = normalize_path(hub["path"])
      title = hub["title"].to_s.strip
      start_s = hub.dig("season", "start").to_s
      end_s = hub.dig("season", "end").to_s
      return nil if id.empty? || title.empty? || path == "/"
      return nil unless month_day(start_s) && month_day(end_s)

      theme = hub["theme"].is_a?(Hash) ? hub["theme"] : {}
      dark = theme["dark"].is_a?(Hash) ? theme["dark"] : {}
      svg = safe_svg(theme["svg"])
      sections = sections_for(hub, cities, data, today, site_url)
      label = season_label(start_s, end_s)
      in_season = in_season?(today, start_s, end_s)
      suggest = hub["suggest"].is_a?(Hash) ? hub["suggest"] : {}
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
        "season_start" => start_s,
        "in_season" => in_season,
        "ends_on" => season_end_on(today, start_s, end_s),
        "footer" => hub["footer"] == true,
        "footer_label" => presence(hub["footer_label"], presence(hub["banner_title"], title)),
        "intro" => intro_for(hub, label, in_season, sections),
        "empty" => presence(hub["empty"], "Nothing is listed yet. City pages are where each event is written up, and this page gathers them."),
        "suggest_lead" => suggest["lead"].to_s.strip,
        "suggest_link" => presence(suggest["link"], "Tell us"),
        "suggest_subject" => suggest["subject"].to_s.lstrip,
        "suggest_body" => suggest["body"].to_s.strip,
        "sections" => sections,
        "visible_events" => sections.flat_map { |section| section["events"] },
        "theme" => {
          "background" => hex_color(theme["background"], "#f4efe6"),
          "ink" => hex_color(theme["ink"], "#1a2822"),
          "muted" => hex_color(theme["muted"], "#3f5148"),
          "link" => hex_color(theme["link"], "#145c40"),
          "dark" => {
            "background" => hex_color(dark["background"], "#2a2433"),
            "ink" => hex_color(dark["ink"], "#f6efe4"),
            "muted" => hex_color(dark["muted"], "#d2c3ae"),
            "link" => hex_color(dark["link"], "#8fd4b0")
          },
          "svg" => svg
        }
      }.tap { |row| row["theme_style"] = theme_style(row["theme"]) }
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
      TextUtil.city_names(cities)
    end

    def event_row(event, city_id, city_name, site_url)
      start_s = event["start"].to_s
      finish_s = event["end"].to_s
      row = row_dates(event["name"], city_name, city_id, event["place"], event["same_as"], start_s, finish_s, site_url)
      row["tags"] = Array(event["tags"]).map(&:to_s)
      %w[cost ages setting drop_off signup sensory].each do |key|
        raw = event[key]
        next if raw.nil? || raw == false || raw.to_s.strip.empty?
        next if key == "drop_off" && EventLabels.camp?(event)

        row[key] = raw
      end
      blurb = event["blurb"].to_s.strip
      row["blurb"] = blurb unless blurb.empty?
      %w[organizer organizer_url performer added].each do |key|
        raw = event[key].to_s.strip
        row[key] = raw unless raw.empty?
      end
      drive = event["drive"].to_s.strip
      row["drive"] = drive unless drive.empty?
      row
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
      link = EventCalendar.card_link(same_clean, city_id, clean_name)
      {
        "name" => clean_name,
        "city" => city_name,
        "city_id" => city_id,
        "place" => place_name,
        "when" => when_text(start_s, finish_s),
        "same_as" => same_clean,
        "href" => link["href"],
        "external" => link["external"],
        "sort" => start_on ? start_on.iso8601 : "9999-99-99",
        "start_raw" => start_s.to_s,
        "end_raw" => finish_s.to_s,
        "end_on" => finish_on ? finish_on.iso8601 : "",
        "url" => href,
        "description" => clean_name,
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
      payload = {
        "id" => section["id"].to_s,
        "title" => title,
        "toc" => presence(section["toc"], title),
        "intro" => section["intro"].to_s.strip,
        "events" => items
      }
      source = section["source"].to_s.strip
      unless source.empty?
        payload["source"] = source
        payload["source_label"] = presence(section["source_label"], "Source")
      end
      payload
    end

    def date_only(value)
      str = value.to_s
      return nil unless str.match?(/\A\d{4}-\d{2}-\d{2}/)

      Date.iso8601(str[0, 10])
    rescue Date::Error, ArgumentError
      nil
    end

    def esc(text)
      CGI.escapeHTML(text.to_s)
    end

    # Own photo, then that venue, then a themed picture, then a seasonal
    # pool picture, then the year-round pool. Prefer a CC or public-domain
    # photo of the event or the venue. When none exists, use the
    # organizer's or venue's own photo (license: organizer), credited and
    # linked. A venue photo is the place itself, so every event there can
    # use it. A theme file is used once on a page. A pool file is used
    # once, then the least-used pool picture may repeat so the card stays
    # a real photo. A designed card is not used. The city hero is not in
    # this chain.
    def attach_cards!(hub, site, pages, catalog, venues, groups, pools, hubs = nil)
      used = {}
      pool_uses = Hash.new(0)
      chosen = {}
      audit = { "own" => [], "venue" => [], "theme" => [], "pool" => [], "none" => [] }
      page_pool = pool_entries(pools, hub["id"])
      today = EventCalendar.pacific_today(site.time)
      Array(hub["sections"]).each do |section|
        kept = []
        Array(section["events"]).each do |event|
          page = pages[event["city_id"].to_s]
          key = "#{event["city_id"]}|#{event["name"]}"
          card = find_card(catalog, event)
          blurb = event["blurb"].to_s.strip
          blurb = card[:blurb].to_s if blurb.empty? && card
          next unless real_blurb?(blurb, event)

          event["blurb"] = blurb
          event["description"] = blurb
          event["calendar"] = calendar_href(page, event)
          event["calendar"] = write_calendar(site, event) if event["calendar"].empty?

          entries = pool_list_for(event, page_pool, pools, hubs, today)
          if chosen.key?(key)
            prev = chosen[key]
            # The same event in a second section may repeat its own photo.
            # A venue or theme file stays once on the page.
            photo = if prev && prev["kind"] == "own"
                      prev
                    else
                      pick_photo(photo_candidates(event, card, venues, groups, entries), used, pool_uses)
                    end
            apply_photo!(event, photo)
            record_photo!(audit, event, photo)
            kept << event
            next
          end

          photo = pick_photo(photo_candidates(event, card, venues, groups, entries), used, pool_uses)
          chosen[key] = photo
          apply_photo!(event, photo)
          record_photo!(audit, event, photo)
          kept << event
        end
        section["events"] = kept
      end
      parts = audit.map { |kind, names| "#{kind} #{names.size}" }
      Jekyll.logger.info("Hub photos:", "#{hub["path"]} #{parts.join(", ")}")
      audit.each do |kind, names|
        next if names.empty?

        Jekyll.logger.info("Hub photos:", "  #{kind}: #{names.join("; ")}")
      end
      missing = audit["none"]
      return if missing.empty?

      raise "Hub #{hub["path"]} has #{missing.size} grid cards without an image: #{missing.join('; ')}"
    end

    def real_blurb?(blurb, event)
      text = blurb.to_s.strip
      return false if text.empty?

      name = event["name"].to_s.strip
      city = event["city"].to_s.strip
      filler = "#{name} in #{city}."
      return false if text.casecmp(filler).zero?
      return false if text.casecmp("#{name} in #{city}").zero?

      true
    end

    def index_card_photos!(site, pages, catalog, venues, groups, hubs, pools)
      today = EventCalendar.pacific_today(site.time)
      fallback = nil
      (seasonal_default_entries(pools, hubs, today) + pool_entries(pools, "general")).each do |entry|
        fallback = listed_photo(entry, "pool")
        break if fallback
      end
      site.data["card_photo_fallback"] = fallback ? public_photo(fallback) : nil

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
          entries = pool_list_for(row, [], pools, hubs, today)
          bucket[name] = photo_candidates(row, card, venues, groups, entries).map { |photo| public_photo(photo) }
        end
        options[city_id] = bucket
      end
      site.data["card_photo_options"] = options
    end

    def photo_candidates(event, card, venues, groups, pool = nil)
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
      Array(pool).each do |entry|
        photo = listed_photo(entry, "pool")
        list << photo if photo
      end
      list.uniq { |photo| photo["src"] }
    end

    # The event's own season, then this page's pool. An event with neither
    # uses the pools of hubs that are in season, so a fall weekend stays
    # with fall pictures instead of another holiday.
    def pool_list_for(event, page_pool, pools, hubs, today)
      list = []
      seen = {}
      push = lambda do |entries|
        Array(entries).each do |entry|
          next unless entry.is_a?(Hash)

          src = entry["image"].to_s
          src = entry["src"].to_s if src.empty?
          next if src.empty? || seen[src]

          seen[src] = true
          list << entry
        end
      end
      push.call(pool_entries(pools, matching_hub_id(event, hubs)))
      push.call(page_pool)
      push.call(seasonal_default_entries(pools, hubs, today)) if list.empty?
      # Year-round pool is the last fallback, including in summer when no hub is in season.
      push.call(pool_entries(pools, "general"))
      list
    end

    def seasonal_default_entries(pools, hubs, today)
      return [] unless today

      Array(hubs).flat_map do |hub|
        next [] unless hub.is_a?(Hash)

        start_s = hub.dig("season", "start").to_s
        end_s = hub.dig("season", "end").to_s
        next [] unless in_season?(today, start_s, end_s)

        pool_entries(pools, hub["id"])
      end
    end

    def pool_entries(pools, hub_id)
      return [] unless pools.is_a?(Hash) && !hub_id.to_s.empty?

      Array(pools[hub_id.to_s])
    end

    def matching_hub_id(event, hubs)
      tags = Array(event["tags"]).map { |tag| tag.to_s.downcase }
      hay = "#{event["name"]} #{event["place"]}".downcase
      Array(hubs).each do |hub|
        next unless hub.is_a?(Hash)

        Array(hub["sections"]).each do |section|
          next unless section.is_a?(Hash)

          section_tags = Array(section["tags"]).map { |tag| tag.to_s.downcase }
          return hub["id"].to_s unless (tags & section_tags).empty?

          if phrases(section["keywords"]).any? { |phrase| hay.include?(phrase) }
            return hub["id"].to_s
          end
        end
        hub_tags = Array(hub["tags"]).map { |tag| tag.to_s.downcase }
        return hub["id"].to_s unless (tags & hub_tags).empty?

        return hub["id"].to_s if phrases(hub["keywords"]).any? { |phrase| hay.include?(phrase) }
      end
      nil
    end

    # A venue photo can repeat, because each card is that same place.
    # A theme file is used once. When every candidate on the page is
    # taken, the least-used seasonal pool picture is used again.
    def pick_photo(candidates, used, pool_uses = nil)
      pool_uses ||= Hash.new(0)
      candidates.each do |photo|
        reusable = photo["kind"] == "venue" || photo["kind"] == "own"
        next if !reusable && used[photo["src"]]

        used[photo["src"]] = true unless reusable
        pool_uses[photo["src"]] += 1 if photo["kind"] == "pool"
        return photo
      end
      pools = candidates.select { |photo| photo["kind"] == "pool" && !photo["src"].to_s.empty? }
      return nil if pools.empty?

      photo = pools.min_by { |item| [pool_uses[item["src"]].to_i, item["src"].to_s] }
      pool_uses[photo["src"]] += 1
      photo
    end

    # Kept for the SVG helper. Event cards do not call this.
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
        "source" => entry["source"],
        "license" => entry["license"]
      )
      return nil unless photo
      return nil if people_photo?(photo)

      photo.merge("kind" => kind)
    end

    # The longest key wins, so "renton highlands library" is that branch
    # and not a shorter library name that also fits the text.
    def matching_venues(event, venues)
      hay = "#{event["name"]} #{event["place"]}".downcase
      ranked = Array(venues).filter_map do |venue|
        hit = Array(venue["keys"]).map { |key| key.to_s.downcase.strip }.select do |key|
          !key.empty? && hay.include?(key)
        end.max_by(&:length)
        hit ? [hit.length, venue] : nil
      end
      return [] if ranked.empty?

      best = ranked.map(&:first).max
      ranked.select { |length, _venue| length == best }.map(&:last)
    end

    # City pages show the venue photo when the writeup has none of its own.
    def with_venue_photos(markdown, venues)
      text = markdown.to_s
      return text if text.empty? || venues.nil?

      parts = text.split(/(?=^### )/m)
      parts.map { |part| venue_photo_section(part, venues) }.join
    end

    def venue_photo_section(part, venues)
      return part if part.match?(/\{%\s*include\s+event-photo\.html\b/)

      name = part[/\A###\s+(.+)\s*$/, 1].to_s
      place = part[/<p class="event-place">(.*?)<\/p>/m, 1].to_s
      place = place.gsub(/<[^>]+>/, " ")
      return part if name.empty? && place.empty?

      venue = matching_venues({ "name" => name, "place" => place }, venues).first
      photo = listed_photo(venue, "venue") if venue
      return part unless photo

      include = venue_photo_include(photo)
      if part.sub!(%r{(<p class="event-place">.*?</p>)}m) { "#{Regexp.last_match(1)}\n\n#{include}" }
        part
      elsif part.sub!(/\A(###[^\n]*\n)/) { "#{Regexp.last_match(1)}\n#{include}\n" }
        part
      else
        part
      end
    end

    def venue_photo_include(photo)
      <<~LIQUID.chomp
        {% include event-photo.html
           src="#{quote_attr(photo["src"])}"
           alt="#{quote_attr(photo["alt"])}"
           credit="#{quote_attr(photo["credit"])}"
           source="#{quote_attr(photo["source"])}" %}
      LIQUID
    end

    # A city section with no photo of its own still needs one so two-column
    # rows line up. Options were already chosen by the hub photo index.
    def with_fallback_photos(markdown, city_id, options, fallback)
      text = markdown.to_s
      return text if text.empty?

      bucket = options.is_a?(Hash) ? options[city_id.to_s] : nil
      parts = text.split(/(?=^### )/m)
      parts.map { |part| fallback_photo_section(part, bucket, fallback) }.join
    end

    def fallback_photo_section(part, bucket, fallback)
      return part if part.match?(/\{%\s*include\s+event-photo\.html\b/)
      return part unless part.start_with?("###")

      name = part[/\A###\s+(.+)\s*$/, 1].to_s.strip
      return part if name.empty?

      photo = fallback_choice(bucket, name) || fallback
      return part if photo.nil? || photo["src"].to_s.empty?

      include = venue_photo_include(photo)
      if part.sub!(/\A(###[^\n]*\n)/) { "#{Regexp.last_match(1)}\n#{include}\n" }
        part
      else
        part
      end
    end

    def fallback_choice(bucket, name)
      return nil unless bucket.is_a?(Hash)

      list = bucket[name]
      if list.nil?
        want = EventCalendar.normalize(name)
        bucket.each do |key, value|
          next unless EventCalendar.normalize(key) == want

          list = value
          break
        end
      end
      Array(list).find { |photo| photo.is_a?(Hash) && photo["kind"].to_s != "designed" && !photo["src"].to_s.empty? }
    end

    def quote_attr(value)
      value.to_s.gsub('"', "'")
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
        rows = Array(page.site.data["#{city_id}_events"])
        rows.each do |event|
          next unless event.is_a?(Hash)
          next if event["when"].to_s.empty? && Array(event["blurbs"]).empty?

          title = event["title"].to_s
          title = event["name"].to_s if title.empty?
          blurb = event["hub_blurb"].to_s
          photo = event["photo"].is_a?(Hash) ? event["photo"] : nil
          catalog[city_id] << {
            key: EventCalendar.normalize(title),
            blurb: blurb,
            photo: photo
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

    # Credit text, a source URL, and either an open license or license "organizer".
    # Open licenses are CC0, CC BY, CC BY-SA, and public domain. An organizer
    # or venue photo with no open license still runs. The credit text links
    # to the source.
    def licensed_photo(photo)
      return nil unless photo.is_a?(Hash)

      src = photo["src"].to_s.strip
      credit = photo["credit"].to_s.strip
      source = photo["source"].to_s.strip
      license = photo["license"].to_s.strip
      return nil if src.empty? || credit.empty?
      return nil unless src.start_with?("/")
      return nil unless source.match?(%r{\Ahttps?://}i)

      open_license = "#{credit} #{license}".match?(/\b(?:CC0|CC\s*BY(?:-SA)?|public domain)\b/i)
      organizer = license.match?(/\borganizer\b/i)
      return nil unless open_license || organizer

      photo.merge("src" => src, "credit" => credit, "source" => source, "license" => license)
    end

    def parse_photo_include(body)
      match = body.to_s.match(/\{%\s*include\s+event-photo\.html\s+(.*?)\s*%\}/m)
      return nil unless match

      args = match[1]
      {
        "src" => liquid_arg(args, "src"),
        "alt" => liquid_arg(args, "alt"),
        "credit" => liquid_arg(args, "credit"),
        "source" => liquid_arg(args, "source"),
        "license" => liquid_arg(args, "license")
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
      sentence = sentences.find { |line| !meta_sentence?(line) && !EventCalendar.source_fragment?(line) } || ""
      EventCalendar.shorten_blurb(sentence, 150)
    end

    def meta_sentence?(sentence)
      text = sentence.to_s.downcase
      text.include?("city page") || text.include?("listed here") || text.include?("this calendar")
    end

    def calendar_href(page, event)
      return "" unless page

      groups = page.data["calendar_groups"]
      return "" unless groups.is_a?(Hash)

      raw = event["start_raw"].to_s
      raw = event["start"].to_s if raw.empty?
      start_parsed = EventCalendar.parse_when(raw)
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

    WEEKDAY = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze

    # Friday through Sunday of the current Pacific weekend. Monday through
    # Thursday use the coming Friday. The daily rebuild moves the window.
    def weekend_bounds(today)
      wday = today.wday
      friday = if wday >= 5
                 today - (wday - 5)
               elsif wday.zero?
                 today - 2
               else
                 today + (5 - wday)
               end
      [friday, friday + 1, friday + 2]
    end

    def day_heading(day)
      "#{WEEKDAY[day.wday]}, #{EventCalendar.month_day(day)}"
    end

    def overlaps_day?(row, day)
      start_on = date_only(row["sort"])
      finish = date_only(row["end_on"]) || start_on
      return false unless start_on && finish

      start_on <= day && finish >= day
    end

    def city_rows(cities, data, today, site_url)
      names = city_names(cities)
      rows = []
      names.each do |city_id, city_name|
        Array(data["#{city_id}_events"]).each do |event|
          next unless event.is_a?(Hash)

          row = event_row(event, city_id, city_name, site_url)
          next unless upcoming_row?(row, today)

          rows << row
        end
      end
      rows
    end

    def prepare_weekend(cities, data, today, site_url)
      friday, saturday, sunday = weekend_bounds(today)
      days = [friday, saturday, sunday]
      grouped = days.map { [] }
      city_rows(cities, data, today, site_url).each do |row|
        days.each_with_index do |day, index|
          next unless overlaps_day?(row, day)

          grouped[index] << row.dup
        end
      end
      sections = []
      days.each_with_index do |day, index|
        items = grouped[index].sort_by { |item| [item["startDate"].to_s, item["city"].to_s, item["name"].to_s] }
        next if items.empty?

        ident = WEEKDAY[day.wday].downcase
        sections << {
          "id" => ident,
          "title" => day_heading(day),
          "toc" => WEEKDAY[day.wday],
          "intro" => "",
          "events" => items
        }
      end
      span = "#{day_heading(friday)} through #{day_heading(sunday)}"
      standing_page(
        "this-weekend",
        "/this-weekend/",
        "This weekend on the Eastside",
        "Friday through Sunday family events in 14 Eastside cities, grouped by day. Parks, libraries, markets, and shows, updated daily.",
        "Friday through Sunday in every city.",
        "Nothing is listed for this Friday, Saturday, or Sunday yet.",
        sections,
        weekend_motif
      )
    end

    def standing_page(id, path, title, description, intro, empty, sections, motif)
      {
        "id" => id,
        "path" => path,
        "title" => title,
        "description" => description,
        "banner_title" => title,
        "hook" => "",
        "link_label" => "See events",
        "llms" => description,
        "season_label" => "",
        "in_season" => false,
        "ends_on" => nil,
        "footer" => false,
        "footer_label" => title,
        "intro" => intro,
        "empty" => empty,
        "suggest_lead" => "",
        "suggest_link" => "",
        "suggest_subject" => "",
        "suggest_body" => "",
        "sections" => sections,
        "visible_events" => sections.flat_map { |section| section["events"] },
        "theme" => {
          "background" => "#f4efe6",
          "ink" => "#1a2822",
          "muted" => "#3f5148",
          "link" => "#145c40",
          "dark" => {
            "background" => "#2a2433",
            "ink" => "#f6efe4",
            "muted" => "#d2c3ae",
            "link" => "#8fd4b0"
          },
          "svg" => motif
        }
      }.tap { |row| row["theme_style"] = theme_style(row["theme"]) }
    end

    # April break sentence for one district, from no_school_days.yml.
    # The hub no longer stores those dates itself.
    def spring_break_intro(hub, district, data)
      year = Integer(hub["calendar_year"])
      start_md = hub.dig("season", "start").to_s
      end_md = hub.dig("season", "end").to_s
      window_start = Date.iso8601(format("%04d-%s", year, start_md))
      window_end = Date.iso8601(format("%04d-%s", year, end_md))
      entry = no_school_entry(data, district["id"])
      return "" unless entry

      ranges = []
      Array(entry["days"]).each do |day|
        next unless day.is_a?(Hash) && day["type"].to_s == "break"

        start_on = date_only(day["start"])
        finish_on = date_only(day["end"]) || start_on
        next unless start_on && finish_on
        next if finish_on < window_start || start_on > window_end

        ranges << [start_on, finish_on]
      end
      ranges.sort_by(&:first).map { |start_on, finish_on| break_sentence(start_on, finish_on) }.join(" ")
    rescue ArgumentError, TypeError
      ""
    end

    def break_sentence(start_on, end_on)
      start_name = FULL_MONTHS[start_on.month - 1]
      end_name = FULL_MONTHS[end_on.month - 1]
      if start_on == end_on
        "No school #{start_name} #{start_on.day}, #{start_on.year}."
      elsif start_on.month == end_on.month && start_on.year == end_on.year
        "No school #{start_name} #{start_on.day} through #{end_on.day}, #{end_on.year}."
      else
        "No school #{start_name} #{start_on.day} through #{end_name} #{end_on.day}, #{end_on.year}."
      end
    end

    def no_school_entry(data, district_id)
      file = data["no_school_days"]
      return nil unless file.is_a?(Hash)

      Array(file["districts"]).find { |district| district.is_a?(Hash) && district["id"].to_s == district_id.to_s }
    end

    # Remaining school-year month grids and one .ics feed per district.
    # Past closures stay in the data file. The page does not list events.
    def attach_no_school!(site, _city_pages = nil, _catalog = nil, _venues = nil, _groups = nil, _pools = nil, _hubs = nil)
      file = site.data["no_school_days"]
      return unless file.is_a?(Hash)

      today = EventCalendar.pacific_today(site.time)
      districts = Array(file["districts"]).select { |district| district.is_a?(Hash) && !district["id"].to_s.empty? }
      write_no_school_feeds!(site, districts, today)
      log_spring_break_sources!(site)
      site.data["no_school_page"] = {
        "districts" => no_school_directory(districts),
        "months" => no_school_calendars(districts, today, file["year"])
      }
    end

    def log_spring_break_sources!(site)
      config = site.data["seasonal_hubs"]
      return unless config.is_a?(Hash)

      hub = Array(config["hubs"]).find { |item| item.is_a?(Hash) && item["id"].to_s == "spring-break" }
      return unless hub.is_a?(Hash)

      Array(hub["districts"]).each do |district|
        next unless district.is_a?(Hash)

        sentence = spring_break_intro(hub, district, site.data)
        Jekyll.logger.info("Spring break:", "#{district["id"]} #{sentence}")
        raise "Spring break date missing for #{district["id"]}" if sentence.empty?
      end
    end

    def no_school_directory(districts)
      districts.map do |district|
        id = district["id"].to_s
        title = district["title"].to_s.strip
        {
          "id" => id,
          "title" => title,
          "short" => presence(district["short"], presence(district["toc"], title)),
          "abbr" => presence(district["abbr"], "NS"),
          "slug" => presence(district["slug"], id),
          "early" => district["early"].to_s.strip,
          "weekly" => presence(district["weekly"], district["early"].to_s.strip),
          "source" => district["source"].to_s.strip,
          "source_label" => presence(district["source_label"], "#{title} calendar"),
          "feed_name" => title,
          "feed_path" => "calendar/no-school/#{id}.ics"
        }
      end
    end

    def school_day_off?(day)
      return false if day["off"] == false

      !%w[first last half early].include?(day["type"].to_s)
    end

    def mark_kind(day, off)
      return "if" if off && day["conditional"] == true
      return "grade" if off && !day["grades"].to_s.strip.empty?
      return "off" if off

      "note"
    end

    def cell_text(day, off)
      return "If needed" if off && day["conditional"] == true

      grades = day["grades"].to_s.strip
      return grades if off && !grades.empty?
      return "Off" if off

      case day["type"].to_s
      when "first" then "First day"
      when "last" then "Last day"
      when "half" then "Half day"
      when "early" then "Early release"
      else day["label"].to_s.strip
      end
    end

    def reason_text(day)
      label = day["label"].to_s.strip
      grades = day["grades"].to_s.strip
      text = label
      unless grades.empty?
        piece = "#{grades[0].downcase}#{grades[1..]}"
        text = text.empty? ? grades : "#{text}, #{piece}"
      end
      if day["conditional"] == true && !text.downcase.include?("if needed")
        text = text.empty? ? "If needed" : "#{text}, if needed"
      end
      text
    end

    def span_short(start_on, end_on)
      if start_on == end_on
        "#{MONTHS[start_on.month - 1]} #{start_on.day}"
      elsif start_on.month == end_on.month && start_on.year == end_on.year
        "#{MONTHS[start_on.month - 1]} #{start_on.day} to #{end_on.day}"
      else
        "#{MONTHS[start_on.month - 1]} #{start_on.day} to #{MONTHS[end_on.month - 1]} #{end_on.day}"
      end
    end

    def line_id(slug, month_start, start_on, kind)
      "ns-#{slug}-#{format("%04d-%02d", month_start.year, month_start.month)}-#{start_on.iso8601}-#{kind}"
    end

    def no_school_by_date(districts, today)
      by_date = {}
      districts.each do |district|
        id = district["id"].to_s
        slug = presence(district["slug"], id)
        short = presence(district["short"], district["title"].to_s)
        Array(district["days"]).each do |day|
          next unless day.is_a?(Hash)

          start_on = date_only(day["start"])
          finish_on = date_only(day["end"]) || start_on
          next unless start_on && finish_on
          next if finish_on < today

          off = school_day_off?(day)
          kind = mark_kind(day, off)
          text = cell_text(day, off)
          tip = "#{short}. #{reason_text(day)}"
          cursor = start_on
          while cursor <= finish_on
            by_date[cursor] ||= {}
            by_date[cursor][id] ||= []
            by_date[cursor][id] << {
              "slug" => slug,
              "short" => short,
              "kind" => kind,
              "text" => text,
              "tip" => tip,
              "line" => line_id(slug, cursor, start_on, kind)
            }
            cursor += 1
          end
        end
      end
      by_date
    end

    # September of the school year through June, starting at the current
    # month. A trailing week with no days is omitted. Filtering does not
    # change the grid height.
    def no_school_calendars(districts, today, year_label)
      start_year = year_label.to_s[0, 4].to_i
      return [] if start_year < 2000

      by_date = no_school_by_date(districts, today)
      first = Date.new(start_year, 9, 1)
      last = Date.new(start_year + 1, 6, 1)
      cursor = Date.new(today.year, today.month, 1)
      cursor = first if cursor < first
      return [] if cursor > last

      months = []
      while cursor <= last
        months << no_school_month_grid(cursor, by_date, districts, today)
        cursor = cursor >> 1
      end
      months
    end

    def no_school_month_grid(month_start, by_date, districts, today)
      days_in = Date.new(month_start.year, month_start.month, -1).day
      cells = []
      month_start.wday.times { cells << { "pad" => true } }
      (1..days_in).each do |day_number|
        date = Date.new(month_start.year, month_start.month, day_number)
        marks = []
        districts.each do |district|
          Array(by_date.dig(date, district["id"].to_s)).each { |info| marks << info }
        end
        tips = {}
        marks.each do |info|
          slug = info["slug"].to_s
          text = info["tip"].to_s
          next if slug.empty? || text.empty?

          tips[slug] = tips[slug] ? "#{tips[slug]}\n#{text}" : text
        end
        cells << {
          "pad" => false,
          "day" => day_number,
          "iso" => date.iso8601,
          "label" => "#{FULL_MONTHS[date.month - 1]} #{date.day}",
          "past" => date < today,
          "today" => date == today,
          "marks" => marks,
          "tips" => tips
        }
      end
      cells << { "pad" => true } while (cells.size % 7) != 0
      weeks = []
      cells.each_slice(7) { |week| weeks << week }
      month_end = Date.new(month_start.year, month_start.month, days_in)
      {
        "id" => format("%04d-%02d", month_start.year, month_start.month),
        "label" => "#{FULL_MONTHS[month_start.month - 1]} #{month_start.year}",
        "weeks" => weeks,
        "lines" => month_reason_lines(districts, month_start, month_end, today)
      }
    end

    def month_reason_lines(districts, month_start, month_end, today)
      lines = []
      districts.each do |district|
        id = district["id"].to_s
        slug = presence(district["slug"], id)
        short = presence(district["short"], district["title"].to_s)
        Array(district["days"]).each do |day|
          next unless day.is_a?(Hash)

          start_on = date_only(day["start"])
          finish_on = date_only(day["end"]) || start_on
          next unless start_on && finish_on
          next if finish_on < today

          clip_start = [start_on, month_start].max
          clip_end = [finish_on, month_end].min
          next if clip_end < clip_start

          off = school_day_off?(day)
          kind = mark_kind(day, off)
          lines << {
            "id" => line_id(slug, month_start, start_on, kind),
            "slug" => slug,
            "short" => short,
            "when" => span_short(clip_start, clip_end),
            "reason" => reason_text(day),
            "sort" => clip_start.iso8601
          }
        end
      end
      lines.sort_by { |line| [line["sort"], line["short"].to_s, line["reason"].to_s] }
    end

    def write_no_school_feeds!(site, districts, today)
      dtstamp = EventCalendar.stamp_utc(site.time)
      districts.each do |district|
        id = district["id"].to_s
        title = district["title"].to_s.strip
        source = district["source"].to_s.strip
        events = []
        Array(district["days"]).each do |day|
          next unless day.is_a?(Hash)

          start_on = date_only(day["start"])
          finish_on = date_only(day["end"]) || start_on
          next unless start_on && finish_on
          next if finish_on < today

          events << {
            uid: "no-school-#{id}-#{start_on.iso8601}@eastsidecalendar.com",
            start: { date: start_on, time: nil },
            end: { date: finish_on, time: nil },
            name: closure_feed_name(day),
            place: title,
            url: source,
            description: closure_feed_description(day, title, source)
          }
        end
        site.static_files << CalendarFile.new(
          "calendar/no-school",
          "#{id}.ics",
          EventCalendar.build_feed(title, events, dtstamp)
        )
      end
    end

    def closure_feed_name(day)
      label = day["label"].to_s.strip
      grades = day["grades"].to_s.strip
      text = if school_day_off?(day)
               label = "No school" if label.empty?
               day["conditional"] == true ? "No school if needed: #{label}" : "No school: #{label}"
             else
               label.empty? ? "School day" : label
             end
      grades.empty? ? text : "#{text} (#{grades})"
    end

    def closure_feed_description(day, title, source)
      parts = [title]
      note = day["note"].to_s.strip
      if school_day_off?(day) && day["conditional"] == true
        parts << (note.empty? ? "This day is off unless the district uses it as a snow make-up day." : note)
      elsif !note.empty?
        parts << note
      elsif !school_day_off?(day)
        parts << "This is not a day off."
      end
      grades = day["grades"].to_s.strip
      parts << "Applies to #{grades}." unless grades.empty?
      parts << source unless source.empty?
      parts.join("\n\n")
    end

    def weekend_motif
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" aria-hidden="true" focusable="false"><rect x="4" y="5" width="16" height="14" rx="1.5" fill="#1e4636"/><path d="M4 9h16" stroke="#c6a15a" stroke-width="1.4"/><path d="M8 3.5v3M16 3.5v3" stroke="#6b4e0e" stroke-width="1.4" stroke-linecap="round"/></svg>'
    end

    # Home-page standouts. Curated rows in weekend_picks.yml win. Otherwise
    # the same score the old Liquid include used: festivals first, meetings
    # last, one city per card until four exist. Photos come from the catalog
    # already built for hub cards.
    def attach_home_picks!(site, pages)
      today = EventCalendar.pacific_today(site.time)
      friday, _saturday, sunday = weekend_bounds(today)
      today_s = EventCalendar.iso_date(today)
      friday_s = EventCalendar.iso_date(friday)
      sunday_s = EventCalendar.iso_date(sunday)
      week_end_s = EventCalendar.iso_date(today + 6)
      picked, weekend_ready = curated_home_lines(site, today_s, friday_s, sunday_s)
      if picked.empty?
        weekend_ready = false
        picked, weekend_ready = scored_home_lines(site, today_s, friday_s, sunday_s, week_end_s)
      end
      cards = []
      Array(site.data.dig("sponsors", "cards", "weekend")).each do |sponsor|
        next unless sponsor.is_a?(Hash)
        next if sponsor["title"].to_s.strip.empty?

        cards << sponsor
      end
      used = {}
      html_cache = {}
      picked.each do |line|
        card = home_pick_card(site, pages, line, used, html_cache)
        cards << card if card
      end
      site.data["home_picks"] = {
        "ready" => weekend_ready,
        "title" => (weekend_ready ? "This weekend on the Eastside" : "Coming up on the Eastside"),
        "cards" => cards
      }
    end

    def curated_home_lines(site, today_s, friday_s, sunday_s)
      picked = []
      ready = false
      Array(site.data["weekend_picks"]).each do |pick|
        break if picked.size >= 4
        next unless pick.is_a?(Hash)

        cid = pick["city"].to_s.strip
        want = pick["name"].to_s.strip
        next if cid.empty? || want.empty?

        found = nil
        Array(site.data["#{cid}_events"]).each_with_index do |event, idx|
          next unless event.is_a?(Hash)
          next unless event["name"].to_s.strip == want

          day = event["start"].to_s[0, 10].to_s
          next unless day.size == 10

          end_day = event["end"].to_s[0, 10].to_s
          end_day = day unless end_day.size == 10
          next if end_day < today_s

          flag = day <= sunday_s && end_day >= friday_s ? "1" : "0"
          ready = true if flag == "1"
          found = "500|#{day}|#{cid}|#{pad_index(idx)}|#{flag}"
          break
        end
        picked << found if found
      end
      [picked, ready]
    end

    def scored_home_lines(site, today_s, friday_s, sunday_s, week_end_s)
      lines = []
      Array(site.data["cities"]).each do |city|
        next unless city.is_a?(Hash)

        cid = city["id"].to_s
        Array(site.data["#{cid}_events"]).each_with_index do |event, idx|
          next unless event.is_a?(Hash)

          day = event["start"].to_s[0, 10].to_s
          next unless day.size == 10

          end_day = event["end"].to_s[0, 10].to_s
          end_day = day unless end_day.size == 10
          next if end_day < today_s || day > week_end_s

          score = home_pick_score(event)
          rank = 500 - score
          flag = day <= sunday_s && end_day >= friday_s && end_day >= today_s && score.positive? ? "1" : "0"
          lines << "#{rank}|#{day}|#{cid}|#{pad_index(idx)}|#{flag}"
        end
      end
      ranked = lines.sort
      ready = ranked.any? { |line| line.split("|", 5)[4] == "1" }
      picked = []
      seen = {}
      (1..2).each do |pass|
        break if picked.size >= 4
        break if pass == 2 && picked.size >= 3

        ranked.each do |line|
          break if picked.size >= 4
          break if pass == 2 && picked.size >= 3

          bits = line.split("|", 5)
          flag = bits[4]
          rank = bits[0].to_i
          cid = bits[2]
          next if ready && flag != "1"
          next if pass == 1 && rank >= 500
          next if picked.include?(line)
          next if pass == 1 && seen[cid]

          seen[cid] = true
          picked << line
        end
      end
      [picked, ready]
    end

    def home_pick_score(event)
      name_down = event["name"].to_s.downcase
      place_down = event["place"].to_s.downcase
      name_check = name_down.gsub("farmers", "")
      score = 0
      score += 40 if name_down.include?("festival")
      score += 40 if name_down.include?("fair")
      score += 30 if name_down.include?("parade")
      score += 30 if name_check.include?("farm")
      score += 20 if name_down.include?("market")
      score += 20 if name_down.include?("dance") || name_down.include?("ballet")
      score += 20 if name_down.include?("theatre") || name_down.include?("theater") || name_down.include?("concert")
      score += 20 if name_down.include?("halloween") || name_down.include?("pumpkin")
      score += 10 if name_down.include?("museum") || name_down.include?("music") || name_down.include?("garden") || name_down.include?("exhibit")
      score -= 50 if name_down.include?("storytime") || name_down.include?("story time") || name_down.include?("library hours")
      score -= 40 if name_down.include?("council") || name_down.include?("commission") || name_down.include?("hearing") || name_down.include?(" meeting")
      score -= 25 if name_down.include?("ales") || name_down.include?("brewery") || name_down.include?("oktoberfest") || name_down.include?("beer")
      score -= 10 if place_down.include?("library")
      score
    end

    def pad_index(idx)
      return format("%03d", idx) if idx < 100

      idx.to_s
    end

    def home_pick_card(site, pages, line, used, html_cache)
      _rank, day, cid, idx_s, _flag = line.split("|", 5)
      city = Array(site.data["cities"]).find { |row| row.is_a?(Hash) && row["id"].to_s == cid }
      return nil unless city

      event = Array(site.data["#{cid}_events"])[idx_s.to_i]
      return nil unless event.is_a?(Hash)

      page = pages[cid]
      source_row = card_display_row(site, cid, event)
      # A heading whose rendered text differs from the data name (a curly
      # apostrophe) used to miss the old HTML search, so the card showed
      # the date and no blurb.
      missed = !source_row["title"].to_s.empty? && source_row["title"].to_s != event["name"].to_s
      when_label = missed ? "" : source_row["when"].to_s.strip
      if when_label.empty?
        parsed = Date.iso8601(day)
        when_label = "#{WDAYS[parsed.wday]} #{MONTHS[parsed.month - 1]} #{parsed.day}"
      end
      place_label = missed ? "" : source_row["place_line"].to_s.strip
      place_label = event["place"].to_s if place_label.empty?
      photo, credit, source, alt = home_pick_photo(site, cid, event["name"].to_s, city["name"].to_s, used)
      blurb = missed ? "" : EventCalendar.card_blurb(Array(source_row["blurbs"]).first.to_s)
      {
        "title" => event["name"],
        "href" => event["href"],
        "external" => event["external"],
        "town" => city["name"],
        "town_href" => "/#{cid}/",
        "when" => when_label,
        "calendar" => calendar_href(page, { "name" => event["name"].to_s, "start_raw" => event["start"].to_s }),
        "image" => photo,
        "image_alt" => alt,
        "image_credit" => credit,
        "image_source" => source,
        "place" => place_label,
        "place_city" => city["name"],
        "blurb" => blurb,
        "event" => event
      }
    end

    def card_display_row(site, cid, event)
      return event unless event.is_a?(Hash)
      return event if !event["when"].to_s.empty? || Array(event["blurbs"]).any?

      card_id = event["card"].to_s
      return event if card_id.empty?

      found = Array(site.data["#{cid}_events"]).find do |row|
        row.is_a?(Hash) && row["card"].to_s == card_id && (!row["when"].to_s.empty? || Array(row["blurbs"]).any?)
      end
      found || event
    end

    # The old include read city pages after Markdown conversion, so a
    # straight apostrophe in the data no longer matched the heading.
    def home_pick_chunk(site, page, name, cache)
      content = city_search_html(site, page, cache)
      needle = "### #{name}"
      if content.include?(needle)
        content.split(needle, 2)[1].to_s.split("### ", 2)[0].to_s
      elsif content.include?("#{name}</h3>")
        content.split("#{name}</h3>", 2)[1].to_s.split("<h3", 2)[0].to_s
      else
        ""
      end
    end

    def city_search_html(site, page, cache)
      return "" unless page

      cid = page.data["city"].to_s
      return cache[cid] if cache.key?(cid)

      raw = page.content.to_s.gsub(/\{%.*?%\}/m, "\n")
      cache[cid] = site.find_converter_instance(Jekyll::Converters::Markdown).convert(raw)
    end

    def home_pick_blurb(chunk)
      blurb = ""
      if chunk.include?("<p>")
        paras = chunk.split("<p>")
        blurb = paras[1].split("</p>", 2).first.gsub(/<[^>]*>/, "").strip if paras.size > 1
      end
      return blurb unless blurb.empty?

      chunk.gsub(/\r\n?/, "\n").split("\n").each do |cline|
        cline = cline.strip
        next if cline.empty?
        next if %w[< { - # %].include?(cline[0]) || cline[0] == "["

        return cline.split(" [", 2).first.strip
      end
      ""
    end

    def home_pick_photo(site, cid, name, city_name, used)
      photo = ""
      credit = ""
      source = ""
      alt = ""
      Array(site.data.dig("card_photo_options", cid, name)).each do |option|
        next unless option.is_a?(Hash)

        src = option["src"].to_s
        next if src.empty?

        kind = option["kind"].to_s
        next if kind == "designed"
        next if kind != "own" && kind != "venue" && used[src]

        photo = src
        credit = option["credit"].to_s
        source = option["source"].to_s
        alt = option["alt"].to_s
        used[src] = true if kind != "own" && kind != "venue"
        break
      end
      if photo.empty?
        fallback = site.data["card_photo_fallback"]
        fallback = {} unless fallback.is_a?(Hash)
        photo = fallback["src"].to_s
        credit = fallback["credit"].to_s
        source = fallback["source"].to_s
        alt = fallback["alt"].to_s
      end
      alt = "#{name} in #{city_name}" if alt.empty? && !photo.empty?
      [photo, credit, source, alt]
    end

  end

  class SeasonalHubsGenerator < Jekyll::Generator
    # After the city calendar files exist, so hub cards can link to them.
    priority :lowest

    def stamp_labels!(site)
      ids = Array(site.data["cities"]).filter_map { |city| city["id"].to_s if city.is_a?(Hash) }
      ids.each do |city_id|
        Array(site.data["#{city_id}_events"]).each { |event| stamp_event!(event) }
      end
      Array(site.data["worth_the_drive_events"]).each { |event| stamp_event!(event) }
    end

    # City cards infer a blank setting at render. Hub and weekend cards read
    # the same fields, so fill them the same way before either path renders.
    def stamp_event!(event)
      return unless event.is_a?(Hash)

      if event["setting"].to_s.strip.empty?
        setting = EventLabels.setting_label(event)
        event["setting"] = setting unless setting.to_s.empty?
      end
      if event["cost"].to_s.strip.empty?
        cost = EventLabels.cost_label(event)
        event["cost"] = cost unless cost.to_s.empty?
      end
    end

    def generate(site)
      stamp_labels!(site)
      raw = site.data["seasonal_hubs"]
      config = raw.is_a?(Hash) ? raw : {}
      today = EventCalendar.pacific_today(site.time)
      site_url = site.config["url"].to_s
      prepared = Array(config["hubs"]).filter_map do |hub|
        SeasonalHubs.prepare_hub(hub, site.data["cities"], site.data, today, site_url)
      end
      pages = SeasonalHubs.city_pages(site)
      catalog = SeasonalHubs.card_catalog(pages)
      venues = site.data.dig("venue_images", "venues")
      groups = site.data.dig("theme_images", "groups")
      pools = site.data["hub_pools"]
      raw_hubs = config["hubs"]
      SeasonalHubs.index_card_photos!(site, pages, catalog, venues, groups, raw_hubs, pools)
      SeasonalHubs.attach_home_picks!(site, pages)
      prepared.each { |hub| SeasonalHubs.attach_cards!(hub, site, pages, catalog, venues, groups, pools, raw_hubs) }
      drive = SeasonalHubs.prepare_drive(site.data["worth_the_drive_events"], today, site_url)
      SeasonalHubs.attach_cards!(drive, site, pages, catalog, venues, groups, pools, raw_hubs)
      weekend = SeasonalHubs.prepare_weekend(site.data["cities"], site.data, today, site_url)
      SeasonalHubs.attach_cards!(weekend, site, pages, catalog, venues, groups, pools, raw_hubs)
      SeasonalHubs.attach_no_school!(site, pages, catalog, venues, groups, pools, raw_hubs)

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
      pages[drive["id"]] = drive
      site.pages << hub_page(site, drive)
      [weekend].each do |extra|
        pages[extra["id"]] = extra
        site.pages << hub_page(site, extra)
      end
      # The summer camps page is a real file, not an event hub. The
      # Seasons menu uses this key. Do not add a banner for it.
      if Array(site.data["summer_camps"]).any? { |row| row.is_a?(Hash) }
        pages["summer-camps"] = { "id" => "summer-camps", "path" => "/summer-camps/" }
      end
      site.data["hub_pages"] = pages
      site.data["seasonal_hubs"] = public_hubs
      site.data["footer_seasons"] = SeasonalHubs.footer_seasons(prepared)
      site.data["missing_tiles"] = SeasonalHubs.missing_tiles(
        site.data["share_cards"],
        prepared,
        site.data["seasonal_banner"]
      )
      HomeLights.attach!(site, prepared)
      # City card photos use the hub index above. Render the HTML here,
      # while page data still reaches the layout.
      site.pages.each do |page|
        next unless page.data["layout"] == "city"

        EventCalendar.finish_city_cards!(page)
      end
    end

    def hub_page(site, hub)
      page = Jekyll::PageWithoutAFile.new(site, site.source, hub["id"], "index.html")
      page.data["layout"] = "seasonal"
      page.data["title"] = hub["title"]
      page.data["description"] = hub["description"]
      page.data["permalink"] = hub["path"]
      page.data["hub_id"] = hub["id"]
      page.data["visible_events"] = hub["visible_events"]
      page.data["filter_counts"] = EventLabels.filter_counts(hub["visible_events"])
      latest = LastModified.latest_commit(site, LastModified.hub_sources(site, hub["id"]))
      page.data["last_modified_at"] = EventCalendar.pacific_time(latest) if latest
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

