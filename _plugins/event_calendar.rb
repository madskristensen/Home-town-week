# frozen_string_literal: true

require "cgi"
require "date"
require "digest"
require "fileutils"

module EastsideCalendar
  # Dated events in {city}_events.yml become static .ics files.
  # Undated events are skipped. Clocks stay in America/Los_Angeles.
  # The city page puts an add-to-calendar icon on the gold date line.
  module EventCalendar
    ZONE = "America/Los_Angeles"
    MONTHS = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec].freeze
    GENERIC = %w[
      ages art arts baby center city club community council county downtown
      family farmers festival kids library market park preschool public story
      storytime teen time toddler
    ].freeze

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

    def normalize(text)
      text.to_s
          .unicode_normalize(:nfd)
          .gsub(/\p{Mn}/, "")
          .downcase
          .tr("’‘`", "'")
          .gsub("&", " and ")
          .gsub(/[^a-z0-9]+/, " ")
          .strip
    end

    def markdown_headings(markdown)
      headings = []
      current = nil
      markdown.to_s.each_line do |line|
        if (match = line.match(/\A###[ \t]+(.+?)[ \t]*\r?\n?\z/))
          headings << current if current
          current = { text: match[1].strip, body: +"" }
        elsif line.match(/\A\#{1,2}[ \t]+/)
          headings << current if current
          current = nil
        elsif current
          current[:body] << line
        end
      end
      headings << current if current
      headings
    end

    def plain_blurb(body)
      text = body.to_s.gsub(/\r\n?/, "\n")
      text = text.gsub(/\{%.*?%\}/m, "\n")
      text = text.gsub(/\{\{.*?\}\}/m, "\n")
      text = text.gsub(%r{<p class="event-(?:when|place)">.*?</p>}mi, "\n")
      text = drop_source_marks(text)
      text = text.gsub(/[*_]+/, "")
      text = text.gsub(/[ \t]+/, " ")
      text = text.gsub(/ *\n */, " ")
      text = text.gsub(/ {2,}/, " ").strip
      cap_text(visitor_sentences(text).join(" "), 900)
    end

    # One short blurb for a card. Drops source-link tails and notes about
    # other pages. Keeps what the event is.
    def card_blurb(input)
      shorten_blurb(visitor_sentences(drop_source_marks(input)).join(" "), 170)
    end

    # A sentence that fits ends on its period. A cut in the middle of a
    # sentence ends on one ellipsis, not a period plus dots.
    def shorten_blurb(text, max)
      cleaned = text.to_s.gsub(/\s+/, " ").strip
      return cleaned if cleaned.empty? || cleaned.length <= max

      window = cleaned[0, max]
      sentence_at = nil
      offset = 0
      while (match = window.match(/[.!?](?=\s|\z)/, offset))
        index = match.begin(0)
        rest = cleaned[(index + 1)..].to_s.sub(/\A\s+/, "")
        sentence_at = index if rest.empty? || rest.match?(/\A[A-Z0-9"']/)
        offset = index + 1
      end
      return cleaned[0, sentence_at + 1].strip if sentence_at && sentence_at >= 40

      spot = window.rindex(" ")
      trimmed = spot && spot > 40 ? window[0, spot] : window
      trimmed = trimmed.rstrip.sub(/[,:;]+\z/, "")
      loop do
        break unless trimmed.match?(/[.!?…]+\z/) || trimmed.match?(/\.{2,}\z/)

        space = trimmed.rindex(" ")
        break unless space && space > 40

        trimmed = trimmed[0, space].rstrip
      end
      "#{trimmed}…"
    end

    def drop_source_marks(text)
      raw = text.to_s
      raw = raw.gsub(/<a\b[^>]*>.*?<\/a>/mi, " ")
      raw = raw.gsub(/<br\s*\/?>/i, "\n")
      raw = raw.gsub(/<[^>]+>/, " ")
      raw = raw.gsub(/\[[^\]]+\]\([^)]+\)/, " ")
      CGI.unescapeHTML(raw)
    end

    def visitor_sentences(text)
      cleaned = text.to_s.gsub(/\s+/, " ").strip
      return [] if cleaned.empty?

      cleaned.split(/(?<=[.!?])\s+/).map(&:strip).reject(&:empty?).reject do |line|
        meta_note?(line) || source_fragment?(line)
      end
    end

    def meta_note?(sentence)
      text = sentence.to_s.downcase
      text.include?("city page") || text.include?("listed here") || text.include?("this calendar")
    end

    def source_fragment?(sentence)
      text = sentence.to_s.strip
      return true if text.empty? || text.match?(/\A[·\s]+\z/)
      return false if text.match?(/[.!?]/)

      text.match?(/·/) || (text.length < 90 && text.match?(/\bposts\z/i))
    end

    def cap_text(text, max)
      return text if text.length <= max

      cut = text[0, max]
      spot = cut.rindex(/[.!?] /)
      spot ? cut[0, spot + 1].strip : cut.rstrip
    end

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

    def match_score(event_key, heading_key)
      return 0 if event_key.empty? || heading_key.empty?
      return 100 if event_key == heading_key

      shorter, longer = [event_key, heading_key].sort_by(&:length)
      if longer.start_with?("#{shorter} ")
        long_enough = shorter.length >= 8 || (!shorter.include?(" ") && shorter.length >= 7)
        return 90 if long_enough
      end

      if shorter.length >= 12 && shorter.split.size >= 2 && tokens_in_order?(shorter, longer)
        return 60
      end
      return 65 if leading_name_match?(event_key, heading_key)

      0
    end

    def leading_name_match?(left, right)
      left_tokens = left.split
      right_tokens = right.split
      return false if left_tokens.size < 2 || right_tokens.size < 2
      return false unless left_tokens[0] == right_tokens[0] && left_tokens[1] == right_tokens[1]
      return false if GENERIC.include?(left_tokens[0]) || GENERIC.include?(left_tokens[1])

      left_tokens[0].length >= 4 && left_tokens[1].length >= 4
    end

    def tokens_in_order?(needle, haystack)
      tokens = needle.split
      return false if tokens.size < 2

      rest = haystack
      tokens.each do |token|
        found_at = nil
        from = 0
        while (idx = rest.index(token, from))
          before_ok = idx.zero? || rest[idx - 1] == " "
          after = idx + token.length
          after_ok = after == rest.length || rest[after] == " "
          if before_ok && after_ok
            found_at = after
            break
          end
          from = idx + 1
        end
        return false unless found_at

        rest = rest[(found_at + 1)..] || ""
      end
      true
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

    def render_grouped_cards(page, cards, today)
      return "" if cards.empty?

      unless today
        return render_card_grid(page, "events" => cards, "show_city" => false, "eager" => 0)
      end

      buckets = Hash.new { |hash, key| hash[key] = [] }
      cards.each do |assigns|
        iso = assigns["date"].to_s
        date = iso.empty? ? nil : Date.iso8601(iso)
        buckets[bucket_key(date, today)] << assigns
      rescue Date::Error, ArgumentError
        buckets[:later] << assigns
      end
      grouped = +""
      site = page.site
      BUCKETS.each do |key, label|
        list = buckets[key]
        next if list.nil? || list.empty?

        assigns = {
          "events" => list,
          "heading" => label,
          "show_city" => false,
          "eager" => 0
        }
        if key == :weekend
          assigns["share"] = "weekend"
          assigns["share_url"] = absolute_url(site, page.url)
          assigns["share_title"] = "This weekend in #{city_name_for(site, page)}"
        end
        grouped << render_card_grid(page, assigns)
      end
      grouped
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

    # Same-named events on different days attach to the heading whose
    # date line matches. A second session on that day uses the next heading.
    def assign_events(headings, events)
      assigned = Hash.new { |hash, key| hash[key] = [] }
      used = Hash.new(0)
      events.each do |event|
        best = nil
        best_rank = nil
        headings.each_with_index do |heading, index|
          score = match_score(event[:key], heading[:key])
          next unless score.positive?

          when_text = heading[:when_text].to_s
          clock_hit = clock_mentioned?(when_text, event[:start]) ? 0 : 1
          date_hit = month_day_mentioned?(when_text, event[:start]) ? 0 : 1
          rank = [clock_hit, date_hit, used[index], -score]
          next unless best.nil? || (rank <=> best_rank).negative?

          best = index
          best_rank = rank
        end
        next unless best

        event[:score] = match_score(event[:key], headings[best][:key])
        assigned[best] << event
        used[best] += 1
      end
      assigned
    end

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

    def visible_text(html)
      CGI.unescapeHTML(html.to_s.gsub(/<[^>]+>/, " ")).gsub(/\s+/, " ").strip
    end

    # Small calendar glyph. The link name lives on aria-label and title.
    CALENDAR_ICON = '<svg class="cal-icon" viewBox="0 0 16 16" aria-hidden="true"><use href="#icon-cal"></use></svg>'.freeze

    def calendar_label(link, count)
      name = link[:name].to_s.strip
      name = "this event" if name.empty?
      label = "Add #{name} to calendar"
      count > 1 ? "#{label}, #{link[:when_label]}" : label
    end

    def calendar_anchor(link, count)
      label = calendar_label(link, count)
      href = CGI.escapeHTML(link[:href])
      safe = CGI.escapeHTML(label)
      extra = count > 1 ? %(<span class="event-cal-when">#{CGI.escapeHTML(link[:when_label])}</span>) : ""
      %(<a class="event-cal" href="#{href}" aria-label="#{safe}" title="#{safe}">#{CALENDAR_ICON}#{extra}</a>)
    end

    def calendar_actions(links)
      anchors = links.map { |link| calendar_anchor(link, links.length) }
      joined = anchors.join
      return joined if links.length < 2

      %(<span class="event-cals">#{joined}</span>)
    end

    # Keep the icon on the same line as the last word of the date.
    # A long date may wrap, but the icon does not land alone.
    def glue_calendar(inner, snippet)
      text = inner.to_s
      core = text.sub(/\s+\z/, "")
      trail = text[core.length..] || ""
      return "#{snippet}#{trail}" if core.empty?

      if (match = core.match(/\A(.*\s)(\S+)\z/m))
        %(#{match[1]}<span class="event-when-tail">#{match[2]}#{snippet}</span>#{trail})
      else
        %(<span class="event-when-tail">#{core}#{snippet}</span>#{trail})
      end
    end

    def inject!(html, groups, dates, today, city_name = nil, labels = nil, page = nil, ends = nil, schemas = nil)
      return html unless html.is_a?(String)

      match = html.match(/<div class="event-list"[^>]*>/)
      return html unless match

      content_at = match.end(0)
      close_at = matching_div_end(html, content_at)
      return html unless close_at

      prelude, cards = collect_event_cards(html[content_at...close_at], groups, dates, city_name, labels, page, ends, schemas)
      inner = prelude + render_grouped_cards(page, cards, today)
      opener = stamp_today(html[match.begin(0)...content_at], today)
      html[0, match.begin(0)] + opener + inner + html[close_at..]
    end

    # The list attribute and the buckets share one Pacific day.
    # Liquid's date filter can print the UTC day instead.
    def stamp_today(opener, today)
      return opener unless today

      iso = iso_date(today)
      if opener.include?("data-today=")
        opener.sub(/data-today="[^"]*"/, %(data-today="#{iso}"))
      else
        opener.sub(/\A<div\b/, %(<div data-today="#{iso}"))
      end
    end

    def matching_div_end(html, from)
      depth = 1
      index = from
      while index < html.length
        next_div = html.index(/<\/?div\b/, index)
        return nil unless next_div

        if html[next_div, 5] == "</div"
          depth -= 1
          return next_div if depth.zero?

          index = next_div + 6
        else
          depth += 1
          index = next_div + 4
        end
      end
      nil
    end

    def collect_event_cards(inner, groups, dates, city_name = nil, labels = nil, page = nil, ends = nil, schemas = nil)
      groups ||= {}
      dates ||= {}
      labels ||= {}
      cursors = Hash.new(0)
      parts = inner.split(/(?=<h3\b)/)
      prelude = parts.shift.to_s
      loose = +""
      cards = []
      parts.each do |part|
        heading = part[/\A<h3\b[^>]*>.*?<\/h3>/m]
        unless heading
          loose << part
          next
        end

        key = normalize(visible_text(heading))
        bucket = groups[key]
        index = cursors[key]
        cursors[key] = index + 1
        links = bucket && bucket[index]
        snippet = links && !links.empty? ? calendar_actions(links) : nil
        iso = dates[key] && dates[key][index]
        iso = nil if iso.to_s.empty?
        end_iso = ends && ends[key] && ends[key][index]
        end_iso = nil if end_iso.to_s.empty?
        info = labels[key] && labels[key][index]
        part = link_event_place(part, city_name)
        part = mark_source_links(part)
        schema = schemas && schemas[key] && schemas[key][index]
        cards << event_card_assigns(part, iso, info, end_iso, schema, snippet)
      end
      [prelude + loose, cards]
    end

    # The place line stays plain text in the markdown. The link opens a map.
    # The query is that line plus the town, not the event title.
    def link_event_place(part, city_name)
      part.sub(%r{(<p class="event-place">)(.*?)(</p>)}m) do
        open_tag = Regexp.last_match(1)
        inner = Regexp.last_match(2)
        close_tag = Regexp.last_match(3)
        next Regexp.last_match(0) if inner.include?("<a")

        text = visible_text(inner)
        next Regexp.last_match(0) if text.empty?

        href = CGI.escapeHTML(MapLinks.href(text, city_name))
        %(#{open_tag}<a class="addr" href="#{href}"><span class="addr-text">#{inner.strip}</span></a>#{close_tag})
      end
    end

    # The outbound link under a card ("Meydenbauer calendar") is meta text.
    # A hard break before that link becomes its own line.
    def mark_source_links(part)
      part = part.gsub(%r{<br\s*/?>\s*(?=<a\b)}i, "</p>\n<p class=\"event-links\">")
      part = part.gsub(%r{<p>(\s*(?:<a\b.*?<\/a>|·|&middot;|\s)+)</p>}m) do
        %(<p class="event-links">#{Regexp.last_match(1)}</p>)
      end
      part.gsub(%r{<a(?![^>]*\bclass=")([^>]*)>}m) do
        %(<a class="event-source"#{Regexp.last_match(1)}>)
      end
    end

    def excise(html, chunk)
      return html if chunk.to_s.empty?

      at = html.index(chunk)
      return html unless at

      html[0, at] + html[(at + chunk.length)..]
    end

    # Pull the city writeup into the same fields the shared card renders.
    def extract_card_fields(part)
      html = part.to_s.dup
      heading = html.match(/<h3\b([^>]*)>(.*?)<\/h3>/m)
      title = heading ? visible_text(heading[2]) : ""
      heading_id = heading ? heading[1][/id="([^"]*)"/, 1].to_s : ""
      html = excise(html, heading[0]) if heading

      photo = ""
      while (fig = html[/<figure\b[^>]*\bclass="event-photo"[^>]*>.*?<\/figure>/m])
        photo = fig if photo.empty?
        html = excise(html, fig)
      end

      when_inner = html[/<p class="event-when"[^>]*>(.*?)<\/p>/m, 1]
      when_text = visible_text(when_inner)
      when_tag = html[/<p class="event-when"[^>]*>.*?<\/p>/m]
      html = excise(html, when_tag)

      places = html.scan(/<p class="event-place"[^>]*>.*?<\/p>/m)
      places.each { |chunk| html = excise(html, chunk) }
      links = html.scan(/<p class="event-links"[^>]*>.*?<\/p>/m)
      links.each { |chunk| html = excise(html, chunk) }

      blurbs = []
      html.scan(/<p\b[^>]*>(.*?)<\/p>/m) do
        inner = Regexp.last_match(1).to_s.strip
        next if visible_text(inner).empty?

        blurbs << %(<p class="hub-blurb">#{inner}</p>)
      end

      {
        "title" => title,
        "heading_id" => heading_id,
        "when" => when_text,
        "photo_html" => photo.strip,
        "place_html" => places.join("\n"),
        "links_html" => links.join("\n"),
        "blurb_html" => blurbs.join("\n")
      }
    end

    # One card per event heading. card-grid.html renders event-card.html.
    # The calendar icon is a separate action, not glued to the date.
    def event_card_assigns(part, iso = nil, info = nil, end_iso = nil, schema = nil, calendar_html = nil)
      body = part.sub(/\s+\z/, "")
      fields = extract_card_fields(body)
      tags = EventLabels.html(info)
      assigns = { "prebuilt" => true }
      assigns["title"] = fields["title"] unless fields["title"].empty?
      assigns["heading_id"] = fields["heading_id"] unless fields["heading_id"].empty?
      assigns["when"] = fields["when"] unless fields["when"].empty?
      assigns["photo_html"] = fields["photo_html"] unless fields["photo_html"].empty?
      assigns["place_html"] = fields["place_html"] unless fields["place_html"].empty?
      assigns["links_html"] = fields["links_html"] unless fields["links_html"].empty?
      assigns["blurb_html"] = fields["blurb_html"] unless fields["blurb_html"].empty?
      assigns["tags_html"] = tags unless tags.empty?
      assigns["calendar_html"] = calendar_html unless calendar_html.to_s.strip.empty?
      assigns["date"] = iso.to_s unless iso.to_s.empty?
      assigns["end"] = end_iso.to_s unless end_iso.to_s.empty?
      extra = EventLabels.attrs(info)
      assigns["attrs"] = extra unless extra.to_s.empty?
      if schema.is_a?(Hash)
        assigns["schema_start"] = schema["startDate"].to_s
        assigns["schema_end"] = schema["endDate"].to_s
        assigns["schema_description"] = schema["description"].to_s
        assigns["schema_url"] = schema["sameAs"].to_s
        assigns["schema_place"] = schema["place"].to_s
        assigns["schema_street"] = schema["street"].to_s
        assigns["schema_locality"] = schema["locality"].to_s
        assigns["schema_cost"] = schema["cost"].to_s
        assigns["schema_name"] = schema["name"].to_s
        assigns["schema_share_start"] = schema["shareStart"].to_s
        assigns["schema_share_end"] = schema["shareEnd"].to_s
        if assigns["schema_url"].empty?
          found = body[/<a class="event-source"[^>]*href="([^"]+)"/, 1]
          assigns["schema_url"] = CGI.unescapeHTML(found.to_s) if found
        end
        photo = body[/<img\b[^>]*\ssrc="([^"]+)"/, 1]
        assigns["schema_image"] = CGI.unescapeHTML(photo.to_s) if photo
      end
      assigns
    end

    def render_card_grid(page, assigns)
      site = page.site
      path = File.join(site.source, "_includes", "card-grid.html")
      template = site.liquid_renderer.file(path).parse(File.read(path))
      context = Liquid::Context.new(
        [site.site_payload],
        {},
        { site: site, page: { "path" => page.path.to_s } },
        true
      )
      context["include"] = assigns
      site.regenerator.add_dependency(site.in_source_dir(page.path), path)
      rendered = template.render!(context).to_s
      events = assigns["events"]
      if events.respond_to?(:any?) && events.any?
        raise "card-grid include did not render" unless rendered.include?('class="card-grid"')
        raise "card-grid include did not render an event card" unless rendered.include?('<article class="event-card"')
      end

      rendered
    end

    # Labels for the card readers see. Recurring rows that share a heading
    # use the row on that card's date.
    def card_labels(picks, date)
      return {} if picks.nil? || picks.empty?

      chosen = picks.find { |event| date && event[:start] && event[:start][:date] == date }
      chosen ||= picks.min_by { |event| sort_key(event[:start]) }
      chosen[:labels] || {}
    end

    def root_path(site, path)
      base = site.baseurl.to_s.sub(%r{/\z}, "")
      full = path.start_with?("/") ? path : "/#{path}"
      "#{base}#{full}"
    end

    def absolute_url(site, path)
      origin = site.config["url"].to_s.sub(%r{/\z}, "")
      "#{origin}#{root_path(site, path)}"
    end

    def http_url?(value)
      value.to_s.match?(%r{\Ahttps?://\S+\z})
    end

    # GitHub-flavored heading ids, matching kramdown-parser-gfm. Digits
    # stay, "&" drops out without collapsing the spaces around it, and a
    # repeated heading gets -1, -2.
    def kramdown_id(text, used)
      gen = text.to_s.downcase.gsub(/[^\p{Word}\- \t]/, "").tr(" \t", "-")
      gen = "section" if gen.empty?
      count = used.fetch(gen, -1) + 1
      used[gen] = count
      count.positive? ? "#{gen}-#{count}" : gen
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

    # A clock time stays as an offset ISO string. A date-only event stays
    # YYYY-MM-DD so a share message does not invent a midnight time.
    def share_start_value(parsed)
      return "" unless parsed && parsed[:date]
      return format_offset_time(parsed).to_s if parsed[:time]

      parsed[:date].iso8601
    end

    def share_end_value(start_parsed, end_parsed)
      return "" unless start_parsed && start_parsed[:date]
      return "" unless end_parsed && end_parsed[:date]

      if start_parsed[:time]
        return "" unless end_parsed[:time]
        return "" if sort_key(end_parsed) <= sort_key(start_parsed)

        format_offset_time(end_parsed).to_s
      else
        return "" if end_parsed[:date] <= start_parsed[:date]

        end_parsed[:date].iso8601
      end
    end

    # Venue name without the street or a repeated city.
    def venue_name(place, city_name)
      text = place.to_s.gsub(/\s+/, " ").strip
      return "" if text.empty?

      parts = text.split(/\s*,\s*/)
      street = parts.find { |part| part.match?(/\A\d{1,6}(?!st|nd|rd|th)\b/i) }
      kept = []
      parts.each do |part|
        break if street && part == street

        kept << part
      end
      kept.pop if !city_name.to_s.empty? && kept.last.to_s.casecmp(city_name.to_s).zero?
      kept.pop if kept.last.to_s.match?(/\A(?:WA|Washington)\z/i)
      kept.join(", ").strip
    end

    def place_parts(place, city_name)
      text = place.to_s.gsub(/\s+/, " ").strip
      return ["", ""] if text.empty?

      street = text.split(/\s*,\s*/).find { |part| part.match?(/\A\d{1,6}(?!st|nd|rd|th)\b/i) }
      street = street.to_s
      street = street.sub(/\s+\b(?:WA|Washington)\b.*\z/i, "")
      street = street.sub(/\s+\d{5}(?:-\d{4})?\z/, "")
      unless city_name.to_s.empty?
        street = street.sub(/\s+#{Regexp.escape(city_name)}\z/i, "")
      end
      street = street.strip
      [text, street]
    end

    def first_http_link(body)
      body.to_s[/\]\((https?:\/\/[^)\s]+)\)/, 1]
    end

    def city_name_for(site, page)
      id = page.data["city"].to_s
      row = Array(site.data["cities"]).find { |item| item.is_a?(Hash) && item["id"].to_s == id }
      name = row && row["name"].to_s.strip
      return name unless name.nil? || name.empty?

      page.data["title"].to_s.strip
    end

    def shorten_phrase(text, room)
      return "" if room <= 0
      return text if text.length <= room

      cut = text[0, room].rstrip
      spot = cut.rindex(" ")
      spot && spot >= 12 ? cut[0, spot].rstrip : cut
    end

    # About 120 to 155 characters. The named event is the first upcoming card.
    # The lead sentence is the phrase that used to show under the city name.
    def city_meta_description(city_name, event_name, soon)
      city = city_name.to_s.strip
      event = event_name.to_s.gsub(/[—–]/, " ").gsub(/\s+/, " ").strip
      when_phrase = soon ? "this week" : "coming up"
      phrase = "Family events and things to do with kids in #{city}"
      tail = " Parks, markets, library story times, and other plans for families. Updated daily."
      short_tail = " Parks, markets, and library plans. Updated daily."
      unless event.empty?
        lead = "#{phrase} #{when_phrase}, like "
        suffix = ".#{tail}"
        room = 155 - lead.length - suffix.length
        if room < 12
          suffix = ".#{short_tail}"
          room = 155 - lead.length - suffix.length
        end
        if room >= 12
          event = shorten_phrase(event, room) if event.length > room
          text = "#{lead}#{event}#{suffix}".gsub(/\s+/, " ").strip
          return text if text.length >= 120 && text.length <= 155
        end
      end

      text = "#{phrase}.#{tail}"
      text = "#{phrase}.#{short_tail}" if text.length > 155
      text.gsub(/\s+/, " ").strip
    end

    def visible_event(heading, picks, today, city_name, city_url, used_ids)
      anchor = kramdown_id(heading[:text], used_ids)
      card_date = heading_date(heading, picks, today)
      chosen = picks.find { |event| card_date && event[:start] && event[:start][:date] == card_date }
      chosen ||= picks.min_by { |event| sort_key(event[:start]) }
      start_parsed = if chosen && chosen[:start] && (card_date.nil? || chosen[:start][:date] == card_date)
                       chosen[:start]
                     elsif card_date
                       { date: card_date, time: nil }
                     end
      finish = schema_end(start_parsed, chosen && chosen[:end])
      place_html = heading[:body][/<p class="event-place">(.*?)<\/p>/m, 1]
      place = visible_text(place_html)
      place = chosen[:place].to_s if place.empty? && chosen
      place_name, street = place_parts(place, city_name)
      place_name = city_name if place_name.empty?
      blurb = plain_blurb(heading[:body])
      blurb = "#{heading[:text]} in #{city_name}." if blurb.empty?
      same = chosen && chosen[:same_as].to_s
      same = first_http_link(heading[:body]) unless http_url?(same)
      {
        "name" => heading[:text],
        "url" => "#{city_url}##{anchor}",
        "description" => blurb,
        "startDate" => format_offset_time(start_parsed).to_s,
        "endDate" => format_offset_time(finish).to_s,
        "place" => place_name,
        "street" => street.to_s,
        "locality" => city_name,
        "sameAs" => http_url?(same) ? same : "",
        "organizer" => chosen ? chosen.dig(:labels, "organizer").to_s : "",
        "organizer_url" => chosen ? chosen.dig(:labels, "organizer_url").to_s : "",
        "performer" => chosen ? chosen.dig(:labels, "performer").to_s : "",
        "added" => chosen ? chosen.dig(:labels, "added").to_s : "",
        "date" => card_date ? iso_date(card_date) : "",
        "bucket" => bucket_key(card_date, today).to_s,
        "shareStart" => share_start_value(start_parsed),
        "shareEnd" => share_end_value(start_parsed, chosen && chosen[:end])
      }
    end
  end

  class CalendarFile
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
      ".ics"
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

  class EventCalendarGenerator < Jekyll::Generator
    priority :low

    def generate(site)
      linked = 0
      feed_events = 0
      unmatched = 0
      undated = 0
      dtstamp = EventCalendar.stamp_utc(site.time)
      today = EventCalendar.pacific_today(site.time)

      site.pages.each do |page|
        next unless page.data["layout"] == "city"

        result = build_city(site, page, dtstamp, today)
        linked += result[:linked]
        feed_events += result[:feed]
        unmatched += result[:unmatched]
        undated += result[:undated]
      end

      Jekyll.logger.info(
        "Calendar:",
        "#{linked} add-to-calendar links, #{feed_events} events in city feeds, #{unmatched} dated events without a matching pick, #{undated} undated skipped."
      )
    end

    def build_city(site, page, dtstamp, today)
      events, undated = load_events(site, page)
      headings = EventCalendar.markdown_headings(page.content)
      heading_rows = headings.map do |heading|
        when_text = heading[:body][/<p class="event-when">(.*?)<\/p>/m, 1].to_s
        {
          key: EventCalendar.normalize(heading[:text]),
          text: heading[:text],
          body: heading[:body],
          when_text: when_text
        }
      end
      assigned = EventCalendar.assign_events(heading_rows, events)
      groups = Hash.new { |hash, key| hash[key] = [] }
      dates = Hash.new { |hash, key| hash[key] = [] }
      ends = Hash.new { |hash, key| hash[key] = [] }
      labels = Hash.new { |hash, key| hash[key] = [] }
      used = {}
      used_ids = {}
      feed_uids = {}
      feed = []
      schemas = Hash.new { |hash, key| hash[key] = [] }
      visible = []
      linked = 0
      city_name = EventCalendar.city_name_for(site, page)

      city_path = page.url.to_s
      city_url = EventCalendar.absolute_url(site, city_path)
      dir = "#{city_path.sub(%r{\A/}, '').sub(%r{/\z}, '')}/calendar"

      heading_rows.each_with_index do |heading, index|
        picks = (assigned[index] || []).sort_by { |event| EventCalendar.sort_key(event[:start]) }
        links = picks.map do |event|
          slug = unique_slug(used, EventCalendar.file_slug(event[:name], event[:start]))
          filename = "#{slug}.ics"
          blurb = EventCalendar.plain_blurb(heading[:body])
          page_url = event[:same_as] && EventCalendar.http_url?(event[:same_as]) ? event[:same_as] : city_url
          record = event.merge(
            uid: "#{page.data['city']}-#{slug}@eastsidecalendar.com",
            url: page_url,
            description: EventCalendar.description_for(event, blurb, city_url),
            when_label: EventCalendar.when_label(event[:start], event[:end])
          )
          href = EventCalendar.root_path(site, "/#{dir}/#{filename}")
          site.static_files << CalendarFile.new(dir, filename, EventCalendar.build_ics(record, city_url, dtstamp))
          linked += 1
          { href: href, when_label: record[:when_label], name: heading[:text] }
        end
        picks.each do |event|
          next unless EventCalendar.upcoming_event?(event, today)

          source = EventCalendar.http_url?(event[:same_as]) ? event[:same_as] : ""
          blurb = EventCalendar.plain_blurb(heading[:body])
          cost = event.dig(:labels, "cost").to_s.strip
          feed << {
            uid: EventCalendar.feed_uid(source, event[:start], heading[:text], feed_uids),
            start: event[:start],
            end: event[:end],
            name: heading[:text],
            place: event[:place].to_s,
            url: source,
            description: EventCalendar.feed_description(blurb, cost)
          }
        end
        groups[heading[:key]] << links
        date = EventCalendar.heading_date(heading, picks, today)
        dates[heading[:key]] << (date ? EventCalendar.iso_date(date) : nil)
        finish = EventCalendar.heading_end_date(heading, picks, date)
        ends[heading[:key]] << (finish ? EventCalendar.iso_date(finish) : nil)
        info = EventCalendar.card_labels(picks, date)
        labels[heading[:key]] << info
        rec = EventCalendar.visible_event(heading, picks, today, city_name, city_url, used_ids)
        rec["cost"] = info && info["cost"].to_s
        schemas[heading[:key]] << rec
        visible << rec
      end

      city_id = page.data["city"].to_s
      unless city_id.empty?
        site.static_files << CalendarFile.new(
          "calendar",
          "#{city_id}.ics",
          EventCalendar.build_feed("Eastside Family Calendar: #{city_name}", feed, dtstamp)
        )
      end

      ordered = visible.each_with_index.sort_by { |rec, index| [EventCalendar.bucket_rank(rec["bucket"]), index] }
                       .map(&:first)
      ordered.each { |rec| rec.delete("bucket") }
      page.data["visible_events"] = ordered
      today_iso = EventCalendar.iso_date(today)
      top = ordered.find { |rec| rec["date"].to_s.empty? || rec["date"] >= today_iso } || ordered.first
      soon = false
      if top && !top["date"].to_s.empty?
        begin
          soon = Date.iso8601(top["date"]) <= today + 6
        rescue Date::Error, ArgumentError
          soon = false
        end
      end
      description = EventCalendar.city_meta_description(city_name, top && top["name"], soon)
      page.data["description"] = description
      if description.length < 120 || description.length > 155
        Jekyll.logger.warn("Calendar:", "#{city_name} description is #{description.length} characters")
      end

      matched = assigned.values.sum(&:size)
      page.data["calendar_groups"] = groups
      page.data["event_dates"] = dates
      page.data["event_ends"] = ends
      page.data["event_labels"] = labels
      page.data["event_schema"] = schemas
      page.data["filter_counts"] = EventLabels.filter_counts(labels.values.flatten)
      { linked: linked, feed: feed.size, unmatched: events.size - matched, undated: undated }
    end

    def load_events(site, page)
      key = "#{page.data['city']}_events"
      rows = site.data[key]
      undated = 0
      events = []
      Array(rows).each do |item|
        next unless item.is_a?(Hash)

        start_parsed = EventCalendar.parse_when(item["start"])
        unless start_parsed
          undated += 1
          next
        end
        name = item["name"].to_s.strip
        next if name.empty?

        events << {
          name: name,
          key: EventCalendar.normalize(name),
          start: start_parsed,
          end: EventCalendar.parse_when(item["end"]),
          place: item["place"].to_s.strip,
          same_as: item["same_as"].to_s.strip,
          labels: {
            "name" => name,
            "place" => item["place"].to_s,
            "blurb" => item["blurb"].to_s,
            "same_as" => item["same_as"].to_s,
            "cost" => item["cost"],
            "organizer" => item["organizer"],
            "organizer_url" => item["organizer_url"],
            "performer" => item["performer"],
            "added" => item["added"],
            "ages" => item["ages"],
            "setting" => item["setting"],
            "drop_off" => item["drop_off"],
            "signup" => item["signup"],
            "sensory" => item["sensory"],
            "tags" => item["tags"]
          }
        }
      end
      [events, undated]
    end

    def unique_slug(used, slug)
      candidate = slug
      n = 2
      while used[candidate]
        candidate = "#{slug}-#{n}"
        n += 1
      end
      used[candidate] = true
      candidate
    end
  end
end

Jekyll::Hooks.register :pages, :post_render do |page|
  next unless page.data["layout"] == "city"

  today = EastsideCalendar::EventCalendar.pacific_today(page.site.time)
  page.output = EastsideCalendar::EventCalendar.inject!(
    page.output,
    page.data["calendar_groups"],
    page.data["event_dates"],
    today,
    EastsideCalendar::EventCalendar.city_name_for(page.site, page),
    page.data["event_labels"],
    page,
    page.data["event_ends"],
    page.data["event_schema"]
  )
end

module EastsideCalendar
  module MailEscape
    def mail_escape(input)
      input.to_s.each_byte.map do |byte|
        if byte == 45 || byte == 46 || byte == 95 || byte == 126 ||
           (byte >= 48 && byte <= 57) ||
           (byte >= 65 && byte <= 90) ||
           (byte >= 97 && byte <= 122)
          byte.chr
        else
          format("%%%02X", byte)
        end
      end.join
    end
  end
end

module EastsideCalendar
  module CardBlurbFilter
    def card_blurb(input)
      EventCalendar.card_blurb(input)
    end
  end
end

module EastsideCalendar
  module SchemaFilters
    def schema_when(input)
      EventCalendar.format_offset_time(EventCalendar.parse_when(input)).to_s
    end

    def schema_finish(input)
      start_s, end_s = input.to_s.split("|", 2)
      start_parsed = EventCalendar.parse_when(start_s)
      end_parsed = EventCalendar.parse_when(end_s)
      EventCalendar.format_offset_time(EventCalendar.schema_end(start_parsed, end_parsed)).to_s
    end

    def offer_price(input)
      EventCalendar.offer_price(input).to_s
    end

    def street_of(place, city)
      _name, street = EventCalendar.place_parts(place, city.to_s)
      street.to_s
    end

    def venue_of(place, city)
      EventCalendar.venue_name(place, city.to_s)
    end

    def share_start(input)
      EventCalendar.share_start_value(EventCalendar.parse_when(input))
    end

    def share_finish(input)
      start_s, end_s = input.to_s.split("|", 2)
      EventCalendar.share_end_value(EventCalendar.parse_when(start_s), EventCalendar.parse_when(end_s))
    end

    # Weekend picks stash one card hash per line. Liquid cannot append a hash.
    def push_card(list, json)
      cards = list.is_a?(Array) ? list.dup : []
      raw = json.to_s.strip
      return cards if raw.empty?

      parsed = JSON.parse(raw)
      raise "push_card expected an object" unless parsed.is_a?(Hash)

      cards << parsed
      cards
    end

    # Home weekend cards use the same .ics file the city page already wrote.
    # city_id is the page id. event is the row from {city}_events.
    def calendar_href(city_id, event)
      site = @context.registers[:site]
      return "" unless site && event

      cid = city_id.to_s.strip
      return "" if cid.empty?

      page = site.pages.find do |item|
        item.data["layout"].to_s == "city" && item.data["city"].to_s == cid
      end
      return "" unless page

      start = event["start_raw"].to_s
      start = event["start"].to_s if start.empty?
      EastsideCalendar::SeasonalHubs.calendar_href(page, { "name" => event["name"].to_s, "start_raw" => start })
    end

    # The city date line is already in the card body. The button hangs off
    # that line; it is not a new row.
    def with_event_share(html, button)
      snippet = button.to_s.strip
      return html.to_s if snippet.empty?

      html.to_s.sub(%r{(<p class="event-when"[^>]*>)(.*?)(</p>)}m) do
        "#{Regexp.last_match(1)}#{Regexp.last_match(2)}#{snippet}#{Regexp.last_match(3)}"
      end
    end

    # The city heading is inside the card body. Name belongs on the h3,
    # not the link, because an itemprop on an anchor uses the href.
    def event_name_prop(html)
      html.to_s.sub(/<h3\b(?![^>]*\bitemprop=)/, '<h3 itemprop="name"')
    end
  end
end

Liquid::Template.register_filter(EastsideCalendar::MailEscape)
Liquid::Template.register_filter(EastsideCalendar::CardBlurbFilter)
Liquid::Template.register_filter(EastsideCalendar::SchemaFilters)
