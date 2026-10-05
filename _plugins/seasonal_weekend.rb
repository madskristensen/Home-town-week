# frozen_string_literal: true

require "date"

module EastsideCalendar
  # This weekend is Friday through Sunday in Pacific time.
  module SeasonalHubs
    
    module_function


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

        def weekend_motif
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" aria-hidden="true" focusable="false"><rect x="4" y="5" width="16" height="14" rx="1.5" fill="#1e4636"/><path d="M4 9h16" stroke="#c6a15a" stroke-width="1.4"/><path d="M8 3.5v3M16 3.5v3" stroke="#6b4e0e" stroke-width="1.4" stroke-linecap="round"/></svg>'
        end
  end
end
