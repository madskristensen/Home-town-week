# frozen_string_literal: true

require "cgi"
require "date"
require "fileutils"

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
          sections << section_payload(district, [])
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
      dark = theme["dark"].is_a?(Hash) ? theme["dark"] : {}
      style = [
        "--season-bg-light:#{theme["background"]}",
        "--season-ink-light:#{theme["ink"]}",
        "--season-muted-light:#{theme["muted"]}",
        "--season-link-light:#{theme["link"]}",
        "--season-bg-dark:#{dark["background"]}",
        "--season-ink-dark:#{dark["ink"]}",
        "--season-muted-dark:#{dark["muted"]}",
        "--season-link-dark:#{dark["link"]}"
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
      %w[cost ages setting drop_off signup sensory].each do |key|
        raw = event[key]
        next if raw.nil? || raw == false || raw.to_s.strip.empty?
        next if key == "drop_off" && EventLabels.camp?(event)

        row[key] = raw
      end
      blurb = event["blurb"].to_s.strip
      row["blurb"] = blurb unless blurb.empty?
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

    # Own photo, then that venue, then a themed picture, then a licensed
    # seasonal pool picture. A venue photo is the place itself, so every
    # event there can use it. A theme file is used once on a page. A pool
    # file is used once, then the least-used pool picture may repeat so
    # the card stays a real photo. A designed card is not used. The city
    # hero is not in this chain.
    def attach_cards!(hub, site, pages, catalog, venues, groups, pools, hubs = nil)
      used = {}
      pool_uses = Hash.new(0)
      chosen = {}
      audit = { "own" => [], "venue" => [], "theme" => [], "pool" => [], "none" => [] }
      page_pool = pool_entries(pools, hub["id"])
      today = EventCalendar.pacific_today(site.time)
      Array(hub["sections"]).each do |section|
        Array(section["events"]).each do |event|
          page = pages[event["city_id"].to_s]
          key = "#{event["city_id"]}|#{event["name"]}"
          card = find_card(catalog, event)
          blurb = event["blurb"].to_s.strip
          if blurb.empty?
            blurb = card ? card[:blurb].to_s : ""
            blurb = "#{event["name"]} in #{event["city"]}." if blurb.empty?
            event["blurb"] = blurb
          end
          event["description"] = event["blurb"]
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
            next
          end

          photo = pick_photo(photo_candidates(event, card, venues, groups, entries), used, pool_uses)
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

    def index_card_photos!(site, pages, catalog, venues, groups, hubs, pools)
      today = EventCalendar.pacific_today(site.time)
      fallback = nil
      seasonal_default_entries(pools, hubs, today).each do |entry|
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
    def section_card!(site, hub, section)
      theme = hub["theme"] || {}
      dark = theme["dark"].is_a?(Hash) ? theme["dark"] : {}
      designed_card!(
        site,
        "#{hub["id"]}-#{section["id"]}",
        theme["background"],
        theme["ink"],
        theme["svg"],
        section["title"].to_s,
        dark["background"],
        dark["ink"]
      )
    end

    def designed_cards
      @designed_cards ||= {}
    end

    def designed_card!(site, key, background, ink, motif, label, dark_background = nil, dark_ink = nil)
      cached = designed_cards[key]
      return cached if cached

      label = label.to_s.strip
      label = "Family event" if label.empty?
      background = hex_color(background, "#f4efe6")
      ink = hex_color(ink, "#1a2822")
      dark_background = hex_color(dark_background, "#2a2433")
      dark_ink = hex_color(dark_ink, "#f6efe4")
      dir = "assets/images/hubs/designed"
      name = "#{key}.svg"
      site.static_files << DesignedCardFile.new(dir, name, designed_svg(background, ink, motif, label, dark_background, dark_ink))
      photo = {
        "src" => "/#{dir}/#{name}",
        "alt" => label,
        "credit" => "Eastside Family Calendar",
        "source" => "",
        "kind" => "designed"
      }
      designed_cards[key] = photo
    end

    def designed_svg(background, ink, motif, label, dark_background, dark_ink)
      size = if label.length > 36
               48
             elsif label.length > 24
               60
             else
               72
             end
      safe = safe_svg(motif)
      view = "0 0 24 24"
      inner = ""
      unless safe.empty?
        view = safe[/viewBox="([^"]+)"/, 1] || view
        inner = safe.sub(/\A<svg\b[^>]*>/i, "").sub(%r{</svg>\s*\z}i, "")
      end
      motif_tag = ""
      unless inner.strip.empty?
        motif_tag = %(<svg x="590" y="120" width="420" height="420" viewBox="#{esc(view)}">#{inner}</svg>)
      end
      <<~SVG
        <svg xmlns="http://www.w3.org/2000/svg" width="1600" height="900" viewBox="0 0 1600 900">
          <style>
            .card-bg { fill: #{background}; }
            .card-ink { fill: #{ink}; }
            @media (prefers-color-scheme: dark) {
              .card-bg { fill: #{dark_background}; }
              .card-ink { fill: #{dark_ink}; }
            }
          </style>
          <rect class="card-bg" width="1600" height="900"/>
          <g class="card-motif">#{motif_tag}</g>
          <text class="card-ink" x="800" y="760" text-anchor="middle" font-family="Georgia, Palatino, serif" font-size="#{size}">#{esc(label)}</text>
        </svg>
      SVG
    end

    def generic_motif
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path fill="#1e4636" d="M12 3c2.2 3.6 6 5.6 6 9.4a6 6 0 0 1-12 0C6 8.6 9.8 6.6 12 3z"/><path fill="#6b4e0e" d="M11.2 11h1.6V21h-1.6z"/></svg>'
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
      sentence = sentences.find { |line| !meta_sentence?(line) && !EventCalendar.source_fragment?(line) } || ""
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
      }
    end

    def weekend_motif
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" aria-hidden="true" focusable="false"><rect x="4" y="5" width="16" height="14" rx="1.5" fill="#1e4636"/><path d="M4 9h16" stroke="#c6a15a" stroke-width="1.4"/><path d="M8 3.5v3M16 3.5v3" stroke="#6b4e0e" stroke-width="1.4" stroke-linecap="round"/></svg>'
    end

  end

  # Written during generate. Jekyll does not copy a file that is not in
  # the source tree unless it is registered as a static file.
  class DesignedCardFile
    attr_reader :relative_path

    def initialize(dir, name, content)
      @dir = dir
      @name = name
      @content = content
      @relative_path = "#{dir}/#{name}"
    end

    def path
      nil
    end

    def url
      "/#{@dir}/#{@name}"
    end

    def extname
      ".svg"
    end

    def write?
      true
    end

    def destination(dest)
      File.join(dest, @dir, @name)
    end

    def write(dest)
      dest_path = destination(dest)
      FileUtils.mkdir_p(File.dirname(dest_path))
      File.binwrite(dest_path, @content)
      true
    end
  end

  class SeasonalHubsGenerator < Jekyll::Generator
    # After the city calendar files exist, so hub cards can link to them.
    priority :lowest

    def generate(site)
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
      prepared.each { |hub| SeasonalHubs.attach_cards!(hub, site, pages, catalog, venues, groups, pools, raw_hubs) }
      drive = SeasonalHubs.prepare_drive(site.data["worth_the_drive_events"], today, site_url)
      SeasonalHubs.attach_cards!(drive, site, pages, catalog, venues, groups, pools, raw_hubs)
      weekend = SeasonalHubs.prepare_weekend(site.data["cities"], site.data, today, site_url)
      SeasonalHubs.attach_cards!(weekend, site, pages, catalog, venues, groups, pools, raw_hubs)

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
      site.data["hub_pages"] = pages
      site.data["seasonal_hubs"] = public_hubs
      site.data["footer_seasons"] = SeasonalHubs.footer_seasons(prepared)
      HomeLights.attach!(site, prepared)
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

Jekyll::Hooks.register :pages, :pre_render do |page|
  next unless page.data["layout"] == "city"

  venues = page.site.data.dig("venue_images", "venues")
  page.content = EastsideCalendar::SeasonalHubs.with_venue_photos(page.content, venues)
end
