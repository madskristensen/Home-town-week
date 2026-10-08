# frozen_string_literal: true

require "date"

module EastsideCalendar
  # School-year month grids and one no-school feed per district.
  module SeasonalHubs
    
    module_function


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
            EventCalendar.day_label(start_on)
          else
            "#{EventCalendar.day_label(start_on)} to #{EventCalendar.day_label(end_on)}"
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
  end
end
