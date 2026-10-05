# frozen_string_literal: true

require "date"

module EastsideCalendar
  # Pacific dates, clocks, and daylight-saving offsets. No tzinfo gem.
  module EventCalendar
    ZONE = "America/Los_Angeles"
    MONTHS = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec].freeze
    module_function


        def parse_when(value)
          case value
          when Time
            instant_to_local(value.to_datetime)
          when DateTime
            instant_to_local(value)
          when Date
            { date: value, time: nil }
          else
            str = value.to_s.strip
            return nil if str.empty?
            return { date: Date.parse(str), time: nil } if str.match?(/\A\d{4}-\d{2}-\d{2}\z/)

            instant_to_local(DateTime.parse(str))
          end
        rescue ArgumentError, TypeError
          nil
        end

        def instant_to_local(datetime)
          utc = datetime.new_offset(0)
          offset = pacific_offset_hours(utc)
          local = utc.new_offset(Rational(offset, 24))
          {
            date: Date.new(local.year, local.month, local.day),
            time: [local.hour, local.min, local.sec]
          }
        end

        def pacific_offset_hours(utc_dt)
          moment = Time.utc(utc_dt.year, utc_dt.month, utc_dt.day, utc_dt.hour, utc_dt.min, utc_dt.sec)
          year = moment.year
          dst_start = Time.utc(year, 3, nth_weekday(year, 3, 0, 2), 10, 0, 0)
          dst_end = Time.utc(year, 11, nth_weekday(year, 11, 0, 1), 9, 0, 0)
          moment >= dst_start && moment < dst_end ? -7 : -8
        end

        def nth_weekday(year, month, wday, n)
          date = Date.new(year, month, 1)
          date += 1 until date.wday == wday
          (date + (7 * (n - 1))).day
        end

        # Date buckets for a city page. Today and tomorrow win over the week
        # and the weekend. This week is every day after tomorrow and before
        # the coming Saturday, so Thursday and Friday are not filed under
        # Later while Saturday is still "This weekend". This weekend is the
        # Saturday and Sunday of the current Pacific week (Monday through
        # Sunday). A date with no usable day stays in Later.
        BUCKETS = [
          [:today, "Today"],
          [:tomorrow, "Tomorrow"],
          [:week, "This week"],
          [:weekend, "This weekend"],
          [:later, "Later"]
        ].freeze

        def pacific_today(time)
          utc = time.getutc
          utc_dt = DateTime.new(utc.year, utc.month, utc.day, utc.hour, utc.min, utc.sec, 0)
          offset = pacific_offset_hours(utc_dt)
          local = utc + (offset * 60 * 60)
          Date.new(local.year, local.month, local.day)
        end

        def iso_date(date)
          return nil unless date

          format("%04d-%02d-%02d", date.year, date.month, date.day)
        end

        # The gold date line is the date readers see. The year is the build
        # year in America/Los_Angeles, or the next year when that month and
        # day are more than 45 days behind (January listings written in December).
        def parse_when_text(text, today)
          return nil unless today

          match = text.to_s.match(/\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+(\d{1,2})\b/i)
          return nil unless match

          month = MONTHS.index { |name| name.casecmp(match[1]).zero? }
          return nil unless month

          date = Date.new(today.year, month + 1, match[2].to_i)
          date = Date.new(today.year + 1, date.month, date.day) if date < today - 45
          date
        rescue Date::Error, ArgumentError
          nil
        end

        # Last inclusive day. The matching data row wins. Otherwise the start day.
        def heading_end_date(heading, picks, start_date)
          days = []
          Array(picks).each do |event|
            days << event[:end][:date] if event[:end].is_a?(Hash) && event[:end][:date]
            days << event[:start][:date] if event[:start].is_a?(Hash) && event[:start][:date]
          end
          return days.max if days.any?

          start_date
        end

        def heading_date(heading, picks, today)
          parsed = parse_when_text(heading[:when_text], today)
          yaml_date = picks.filter_map { |event| event[:start] && event[:start][:date] }.min
          if parsed && yaml_date && parsed.month == yaml_date.month && parsed.day == yaml_date.day
            return yaml_date
          end

          parsed || yaml_date
        end

        def bucket_key(date, today)
          return :later unless date && today
          return :today if date == today
          return :tomorrow if date == today + 1

          days_to_sunday = (7 - today.wday) % 7
          sunday = today + days_to_sunday
          saturday = sunday - 1
          return :week if date > today + 1 && date < saturday
          return :weekend if date == saturday || date == sunday

          :later
        end

        def bucket_rank(key)
          name = key.to_s
          idx = BUCKETS.index { |bucket, _label| bucket.to_s == name }
          idx || BUCKETS.length
        end

        def month_day_mentioned?(text, parsed)
          return false unless parsed && parsed[:date]

          mon = MONTHS[parsed[:date].month - 1]
          day = parsed[:date].day
          text.to_s.match?(/\b#{mon}[a-z]*\.?\s+#{day}\b/i)
        end

        def clock_mentioned?(text, parsed)
          return false unless parsed && parsed[:time]

          hour, min, = parsed[:time]
          want = hour >= 12 ? "p.m." : "a.m."
          hour12 = hour % 12
          hour12 = 12 if hour12.zero?
          needle = format("%d:%02d", hour12, min)
          source = text.to_s
          offset = 0
          pattern = /(?<!\d)#{Regexp.escape(needle)}(?!\d)/
          while (match = source.match(pattern, offset))
            window = source[match.begin(0), 48].to_s
            next_clock = window.index(/\d{1,2}:\d{2}/, needle.length)
            slice = next_clock ? window[0, next_clock] : window
            mer = slice[/a\.m\.|p\.m\./i] || window[/a\.m\.|p\.m\./i]
            return true if mer && mer.downcase == want

            offset = match.end(0)
          end
          false
        end

        def month_day(date)
          "#{MONTHS[date.month - 1]} #{date.day}"
        end

        def clock(hour, min)
          suffix = hour >= 12 ? "p.m." : "a.m."
          hour12 = hour % 12
          hour12 = 12 if hour12.zero?
          format("%d:%02d %s", hour12, min, suffix)
        end

        def sort_key(parsed)
          date = parsed[:date]
          hour, min, sec = parsed[:time] || [0, 0, 0]
          Time.utc(date.year, date.month, date.day, hour, min, sec).to_i
        end

        def stamp_utc(time)
          # getutc returns a copy. Time#utc would rewrite site.time and make
          # the Updated line use UTC.
          time.getutc.strftime("%Y%m%dT%H%M%SZ")
        end

        # A Time whose calendar day is America/Los_Angeles, for the Updated line.
        def pacific_time(time)
          return nil if time.nil?

          utc = time.getutc
          utc_dt = DateTime.new(utc.year, utc.month, utc.day, utc.hour, utc.min, utc.sec, 0)
          offset = pacific_offset_hours(utc_dt)
          Time.new(utc.year, utc.month, utc.day, utc.hour, utc.min, utc.sec, "+00:00").getlocal(offset * 3600)
        end

        def offset_hours_for_local(date, hour, min)
          year = date.year
          start_day = nth_weekday(year, 3, 0, 2)
          end_day = nth_weekday(year, 11, 0, 1)
          local = DateTime.new(date.year, date.month, date.day, hour, min, 0)
          dst_start = DateTime.new(year, 3, start_day, 2, 0, 0)
          dst_end = DateTime.new(year, 11, end_day, 2, 0, 0)
          local >= dst_start && local < dst_end ? -7 : -8
        end

        def format_offset_time(parsed)
          return nil unless parsed && parsed[:date]

          date = parsed[:date]
          hour, min, sec = parsed[:time] || [0, 0, 0]
          offset = offset_hours_for_local(date, hour, min)
          sign = offset.negative? ? "-" : "+"
          format(
            "%04d-%02d-%02dT%02d:%02d:%02d%s%02d:00",
            date.year, date.month, date.day, hour, min, sec, sign, offset.abs
          )
        end

        # A timed end is used as written. A date-only end covers through that
        # day. An all-day start with no end covers that same day.
        def schema_end(start_parsed, end_parsed)
          return nil unless start_parsed && start_parsed[:date]

          if end_parsed && end_parsed[:date]
            if end_parsed[:time]
              return nil if start_parsed[:time] && sort_key(end_parsed) <= sort_key(start_parsed)

              return end_parsed
            end
            return nil if end_parsed[:date] < start_parsed[:date]
            return { date: end_parsed[:date], time: [23, 59, 59] }
          end
          return { date: start_parsed[:date], time: [23, 59, 59] } unless start_parsed[:time]

          nil
        end
  end
end
