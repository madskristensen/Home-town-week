# frozen_string_literal: true

require "cgi"
require "date"
require_relative "seasonal_photos"
require_relative "seasonal_no_school"
require_relative "seasonal_home"
require_relative "seasonal_weekend"

module EastsideCalendar
  # Seasonal hubs and the sitewide banner. Data lives in _data/seasonal_hubs.yml.
  module SeasonalHubs
    HEX = /\A#[0-9a-fA-F]{6}\z/
    MONTHS = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec].freeze
    FULL_MONTHS = %w[January February March April May June July August September October November December].freeze
    WDAYS = %w[Sun Mon Tue Wed Thu Fri Sat].freeze

# One event row's name, place, and span. The hub list is built from this.
RowDates = Struct.new(
  :name, :city_name, :city_id, :place, :same, :start_s, :finish_s, :site_url,
  keyword_init: true
)
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
          row = row_dates(RowDates.new(
            name: event["name"], city_name: city_name, city_id: city_id, place: event["place"],
            same: event["same_as"], start_s: start_s, finish_s: finish_s, site_url: site_url
          ))
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

        def row_dates(row)
          name = row.name
          city_name = row.city_name
          city_id = row.city_id
          place = row.place
          same = row.same
          start_s = row.start_s
          finish_s = row.finish_s
          site_url = row.site_url
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

          label = EventCalendar.day_label(start_on)
          if finish_on && finish_on > start_on
            "#{label} to #{EventCalendar.day_label(finish_on)}"
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
  end
  class SeasonalHubsGenerator
    # Called from SitePipeline after the city calendar files exist.

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
      SeasonalHubs.index_card_photos!(SeasonalHubs::PhotoIndex.new(
        site: site, pages: pages, catalog: catalog, venues: venues, groups: groups, hubs: raw_hubs, pools: pools
      ))
      SeasonalHubs.attach_home_picks!(site, pages)
      prepared.each { |hub| SeasonalHubs.attach_cards!(SeasonalHubs::CardPass.new(hub: hub, site: site, pages: pages, catalog: catalog, venues: venues, groups: groups, pools: pools, hubs: raw_hubs)) }
      drive = SeasonalHubs.prepare_drive(site.data["worth_the_drive_events"], today, site_url)
      SeasonalHubs.attach_cards!(SeasonalHubs::CardPass.new(hub: drive, site: site, pages: pages, catalog: catalog, venues: venues, groups: groups, pools: pools, hubs: raw_hubs))
      weekend = SeasonalHubs.prepare_weekend(site.data["cities"], site.data, today, site_url)
      SeasonalHubs.attach_cards!(SeasonalHubs::CardPass.new(hub: weekend, site: site, pages: pages, catalog: catalog, venues: venues, groups: groups, pools: pools, hubs: raw_hubs))
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
      prepared.each do |hub|
        pages[hub["id"]] = hub
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
      # Keep the YAML config in site.data["seasonal_hubs"]. The short list
      # for menus is hub_pages. Do not replace the config with that list.
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

