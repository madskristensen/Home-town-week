# frozen_string_literal: true

require "date"
require "digest"

module EastsideCalendar
  # Static .ics files for one event and for a city feed.
  module EventCalendar
    VTIMEZONE = <<~ICS.gsub("\n", "\r\n")
      BEGIN:VTIMEZONE
      TZID:America/Los_Angeles
      X-LIC-LOCATION:America/Los_Angeles
      BEGIN:DAYLIGHT
      TZOFFSETFROM:-0800
      TZOFFSETTO:-0700
      TZNAME:PDT
      DTSTART:19700308T020000
      RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU
      END:DAYLIGHT
      BEGIN:STANDARD
      TZOFFSETFROM:-0700
      TZOFFSETTO:-0800
      TZNAME:PST
      DTSTART:19701101T020000
      RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU
      END:STANDARD
      END:VTIMEZONE
    ICS
    module_function


        def slugify(text)
          text.to_s
              .downcase
              .gsub(/['’]/, "")
              .gsub(/[^a-z0-9]+/, "-")
              .gsub(/\A-+|-+\z/, "")
        end

        def file_slug(name, parsed)
          base = slugify(name)
          base = "event" if base.empty?
          date = parsed[:date]
          stamp = format("%04d%02d%02d", date.year, date.month, date.day)
          if parsed[:time]
            hour, min, = parsed[:time]
            stamp = format("%s-%02d%02d", stamp, hour, min)
          end
          "#{base}-#{stamp}"
        end

        def when_label(parsed, finish)
          start_date = parsed[:date]
          if parsed[:time]
            hour, min, = parsed[:time]
            "#{month_day(start_date)}, #{clock(hour, min)}"
          elsif finish && !finish[:time] && finish[:date] > start_date
            "#{month_day(start_date)} to #{month_day(finish[:date])}"
          else
            month_day(start_date)
          end
        end

        def escape_text(text)
          text.to_s.gsub(/\r\n?/, "\n").gsub(/[\\,;\n]/) do |char|
            case char
            when "\\" then "\\\\"
            when "\n" then "\\n"
            when "," then "\\,"
            when ";" then "\\;"
            end
          end
        end

        def fold(line)
          bytes = line.to_s.b
          chunks = []
          limit = 75
          while bytes.bytesize > limit
            cut = limit
            cut -= 1 while cut.positive? && (bytes.getbyte(cut) & 0xC0) == 0x80
            cut = 1 if cut.zero?
            chunks << bytes.byteslice(0, cut)
            bytes = bytes.byteslice(cut..)
            limit = 74
          end
          chunks << bytes unless bytes.empty?
          chunks.each_with_index.map { |chunk, index| index.zero? ? chunk : " #{chunk}" }.join("\r\n")
        end

        def format_dt(name, parsed)
          date = parsed[:date]
          if parsed[:time]
            hour, min, sec = parsed[:time]
            format(
              "%s;TZID=%s:%04d%02d%02dT%02d%02d%02d",
              name, ZONE, date.year, date.month, date.day, hour, min, sec
            )
          else
            format("%s;VALUE=DATE:%04d%02d%02d", name, date.year, date.month, date.day)
          end
        end

        def format_dtend(start_parsed, end_parsed)
          if !start_parsed[:time] && end_parsed.nil?
            exclusive = start_parsed[:date] + 1
            return format("DTEND;VALUE=DATE:%04d%02d%02d", exclusive.year, exclusive.month, exclusive.day)
          end
          return nil unless end_parsed

          if start_parsed[:time]
            if end_parsed[:time]
              finish = end_parsed
              return nil if sort_key(finish) <= sort_key(start_parsed)

              format_dt("DTEND", finish)
            else
              return nil if end_parsed[:date] < start_parsed[:date]

              # Through the end date, as a DATE-TIME so it matches DTSTART.
              next_day = end_parsed[:date] + 1
              format_dt("DTEND", { date: next_day, time: [0, 0, 0] })
            end
          else
            finish_date = end_parsed[:date]
            finish_date = start_parsed[:date] if finish_date < start_parsed[:date]
            exclusive = finish_date + 1
            format("%s;VALUE=DATE:%04d%02d%02d", "DTEND", exclusive.year, exclusive.month, exclusive.day)
          end
        end

        # Stable across builds. The source URL and the local start identify
        # the event. A second event with the same pair gets a numbered hash.
        def feed_uid(source, start_parsed, name, used)
          date = start_parsed[:date].strftime("%Y%m%d")
          if start_parsed[:time]
            hour, min, sec = start_parsed[:time]
            date += format("T%02d%02d%02d", hour, min, sec)
          end
          identity = source.to_s.strip
          identity = name.to_s.strip if identity.empty?
          key = "#{identity}|#{date}"
          digest = Digest::SHA256.hexdigest(key)
          n = 2
          while used[digest]
            digest = Digest::SHA256.hexdigest("#{key}|#{n}")
            n += 1
          end
          used[digest] = true
          "#{digest}@eastsidecalendar.com"
        end

        def feed_description(blurb, cost)
          text = blurb.to_s.strip
          price = cost.to_s.strip
          parts = []
          parts << text unless text.empty?
          unless price.empty? || text.downcase.include?(price.downcase)
            parts << price
          end
          parts.join("\n\n")
        end

        # Free is 0. A single amount such as "$12" or "$12.50" is that number.
        # A range or a note is not a single price, so the offer is omitted.
        def offer_price(cost)
          text = cost.to_s.strip
          return "0" if text.casecmp("free").zero?
          return "" unless text.match?(/\A\$[\d,]+(?:\.\d{1,2})?\z/)

          text.delete("$,")
        end

        def upcoming_event?(event, today)
          return true unless today

          finish = event[:end]&.[](:date) || event[:start][:date]
          finish >= today
        end

        def build_feed(calname, events, dtstamp)
          lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Eastside Family Calendar//eastsidecalendar.com//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "X-WR-CALNAME:#{escape_text(calname)}",
            "X-WR-TIMEZONE:#{ZONE}",
            "REFRESH-INTERVAL;VALUE=DURATION:PT6H",
            "X-PUBLISHED-TTL:PT6H"
          ]
          lines.concat(VTIMEZONE.strip.split("\r\n"))
          Array(events).each do |event|
            lines << "BEGIN:VEVENT"
            lines << "UID:#{event[:uid]}"
            lines << "DTSTAMP:#{dtstamp}"
            lines << format_dt("DTSTART", event[:start])
            dtend = format_dtend(event[:start], event[:end])
            lines << dtend if dtend
            lines << "SUMMARY:#{escape_text(event[:name])}"
            place = event[:place].to_s
            lines << "LOCATION:#{escape_text(place)}" unless place.empty?
            url = event[:url].to_s
            lines << "URL:#{url}" unless url.empty?
            description = event[:description].to_s
            lines << "DESCRIPTION:#{escape_text(description)}" unless description.empty?
            lines << "END:VEVENT"
          end
          lines << "END:VCALENDAR"
          "#{lines.map { |line| fold(line) }.join("\r\n")}\r\n"
        end

        def build_ics(event, issue_url, dtstamp)
          start_parsed = event[:start]
          lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Eastside Family Calendar//eastsidecalendar.com//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "X-WR-TIMEZONE:#{ZONE}"
          ]
          lines.concat(VTIMEZONE.strip.split("\r\n"))
          lines << "BEGIN:VEVENT"
          lines << "UID:#{event[:uid]}"
          lines << "DTSTAMP:#{dtstamp}"
          lines << format_dt("DTSTART", start_parsed)
          dtend = format_dtend(start_parsed, event[:end])
          lines << dtend if dtend
          lines << "SUMMARY:#{escape_text(event[:name])}"
          lines << "LOCATION:#{escape_text(event[:place])}" if event[:place] && !event[:place].empty?
          lines << "URL:#{event[:url]}" if event[:url]
          lines << "DESCRIPTION:#{escape_text(event[:description])}"
          lines << "END:VEVENT"
          lines << "END:VCALENDAR"
          "#{lines.map { |line| fold(line) }.join("\r\n")}\r\n"
        end

        def description_for(event, blurb, issue_url)
          parts = []
          parts << blurb unless blurb.to_s.empty?
          if event[:same_as] && !blurb.to_s.include?(event[:same_as])
            parts << "Details: #{event[:same_as]}"
          end
          parts << "End time was not listed." if event[:start][:time] && !event[:end]
          parts << "Eastside Family Calendar: #{issue_url}"
          parts.join("\n\n")
        end
  end
end
