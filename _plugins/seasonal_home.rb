# frozen_string_literal: true

require "date"

module EastsideCalendar
  # Home page picks. Curated rows win. The rest are scored from the event files.
  module SeasonalHubs
    
    module_function


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
end
