# frozen_string_literal: true

require "cgi"
require "date"
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
      text = visitor_sentences(drop_source_marks(input)).join(" ")
      return "" if text.empty?
      return text if text.length <= 170

      cut = text[0, 167]
      spot = cut.rindex(" ")
      trimmed = spot && spot > 40 ? cut[0, spot] : cut
      "#{trimmed.rstrip.sub(/[,:;]\z/, "")}..."
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

    def group_events(inner, today)
      return inner unless today

      parts = inner.split(/(?=<article class="event-card")/)
      prelude = parts.shift.to_s
      buckets = Hash.new { |hash, key| hash[key] = [] }
      parts.each do |part|
        iso = part[/\bdata-date="(\d{4}-\d{2}-\d{2})"/, 1]
        date = iso ? Date.iso8601(iso) : nil
        buckets[bucket_key(date, today)] << part
      rescue Date::Error, ArgumentError
        buckets[:later] << part
      end
      grouped = +prelude
      BUCKETS.each do |key, label|
        cards = buckets[key]
        next if cards.nil? || cards.empty?

        grouped << %(<h2 class="event-bucket">#{label}</h2>\n)
        grouped << cards.join
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
    CALENDAR_ICON = '<svg class="cal-icon" viewBox="0 0 16 16" aria-hidden="true" focusable="false"><rect x="1.75" y="2.75" width="12.5" height="11.5" rx="1.4" fill="none" stroke="currentColor" stroke-width="1.4"></rect><path d="M1.75 6.4h12.5M5 1.35v2.5M11 1.35v2.5" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"></path></svg>'.freeze

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
      %(<span class="event-cals">#{anchors.join}</span>)
    end

    def inject!(html, groups, dates, today, city_name = nil, labels = nil)
      return html unless html.is_a?(String)

      match = html.match(/<div class="prose"[^>]*>/)
      return html unless match

      content_at = match.end(0)
      close_at = matching_div_end(html, content_at)
      return html unless close_at

      inner = inject_inner(html[content_at...close_at], groups, dates, city_name, labels)
      inner = group_events(inner, today)
      opener = stamp_today(html[match.begin(0)...content_at], today)
      html[0, match.begin(0)] + opener + inner + html[close_at..]
    end

    # The prose attribute and the buckets share one Pacific day.
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

    def inject_inner(inner, groups, dates, city_name = nil, labels = nil)
      groups ||= {}
      dates ||= {}
      labels ||= {}
      cursors = Hash.new(0)
      parts = inner.split(/(?=<h3\b)/)
      prelude = parts.shift.to_s
      rendered = parts.map do |part|
        heading = part[/\A<h3\b[^>]*>.*?<\/h3>/m]
        next part unless heading

        key = normalize(visible_text(heading))
        bucket = groups[key]
        index = cursors[key]
        cursors[key] = index + 1
        links = bucket && bucket[index]
        if links && !links.empty?
          snippet = calendar_actions(links)
          unless part.sub!(%r{(<p class="event-when"[^>]*>)(.*?)(</p>)}m) {
            "#{Regexp.last_match(1)}#{Regexp.last_match(2)}#{snippet}#{Regexp.last_match(3)}"
          }
            part.sub!(%r{</h3>}) { "#{Regexp.last_match(0)}\n<p class=\"event-when\">#{snippet}</p>" }
          end
        end
        iso = dates[key] && dates[key][index]
        iso = nil if iso.to_s.empty?
        info = labels[key] && labels[key][index]
        part = link_event_place(part, city_name)
        part = mark_source_links(part)
        wrap_event_card(part, iso, info)
      end
      prelude + rendered.join
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
        %(#{open_tag}<a class="addr" href="#{href}">#{MapLinks.pin}<span class="addr-text">#{inner.strip}</span></a>#{close_tag})
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

    # One card per event heading. The calendar icon is already on the date line.
    def wrap_event_card(part, iso = nil, info = nil)
      body = part.sub(/\s+\z/, "")
      trail = part[body.length..] || ""
      tags = EventLabels.html(info)
      body = body.sub(%r{</h3>}) { "#{Regexp.last_match(0)}\n#{tags}" } unless tags.empty?
      date_attr = iso ? %( data-date="#{iso}") : ""
      extra = EventLabels.attrs(info)
      extra = extra.empty? ? "" : " #{extra}"
      %(<article class="event-card"#{date_attr}#{extra}>\n#{body}\n</article>#{trail})
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
        "date" => card_date ? iso_date(card_date) : "",
        "bucket" => bucket_key(card_date, today).to_s
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
      unmatched = 0
      undated = 0
      dtstamp = EventCalendar.stamp_utc(site.time)
      today = EventCalendar.pacific_today(site.time)

      site.pages.each do |page|
        next unless page.data["layout"] == "city"

        result = build_city(site, page, dtstamp, today)
        linked += result[:linked]
        unmatched += result[:unmatched]
        undated += result[:undated]
      end

      Jekyll.logger.info(
        "Calendar:",
        "#{linked} add-to-calendar links, #{unmatched} dated events without a matching pick, #{undated} undated skipped."
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
      labels = Hash.new { |hash, key| hash[key] = [] }
      used = {}
      used_ids = {}
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
        groups[heading[:key]] << links
        date = EventCalendar.heading_date(heading, picks, today)
        dates[heading[:key]] << (date ? EventCalendar.iso_date(date) : nil)
        labels[heading[:key]] << EventCalendar.card_labels(picks, date)
        visible << EventCalendar.visible_event(heading, picks, today, city_name, city_url, used_ids)
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
      page.data["event_labels"] = labels
      page.data["filter_counts"] = EventLabels.filter_counts(labels.values.flatten)
      { linked: linked, unmatched: events.size - matched, undated: undated }
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
            "cost" => item["cost"],
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
    page.data["event_labels"]
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

Liquid::Template.register_filter(EastsideCalendar::MailEscape)
Liquid::Template.register_filter(EastsideCalendar::CardBlurbFilter)
