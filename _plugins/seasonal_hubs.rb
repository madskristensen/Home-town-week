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

        { "id" => section["id"].to_s, "title" => section["title"].to_s, "events" => items }
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
        sections << { "id" => city_id, "title" => city_name, "events" => items }
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
        "suggest_subject" => suggest["subject"].to_s.strip,
        "suggest_body" => suggest["body"].to_s.strip,
        "sections" => sections,
        "visible_events" => sections.flat_map { |section| section["events"] },
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

        "The season runs #{label}. This page stays up all year."
      else
        text = hub["off_season_listed"].to_s.strip
        return text unless text.empty?

        "The season runs #{label}. This page stays up all year, and dates already set are listed below."
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
      row_dates(event["name"], city_name, city_id, event["place"], event["same_as"], start_s, finish_s, site_url)
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
      return EventCalendar.when_label(parsed, finish) if parsed

      label = start_on.strftime("%b %-d")
      finish_on = date_only(finish_s)
      if finish_on && finish_on > start_on
        "#{label} to #{finish_on.strftime("%b %-d")}"
      else
        label
      end
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
  end

  class SeasonalHubsGenerator < Jekyll::Generator
    priority :low

    def generate(site)
      raw = site.data["seasonal_hubs"]
      config = raw.is_a?(Hash) ? raw : {}
      today = EventCalendar.pacific_today(site.time)
      lights = site.data["holiday_lights"]
      site_url = site.config["url"].to_s
      prepared = Array(config["hubs"]).filter_map do |hub|
        SeasonalHubs.prepare_hub(hub, site.data["cities"], site.data, lights, today, site_url)
      end

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
      page.data["last_modified_at"] = site.time
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
