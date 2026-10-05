# frozen_string_literal: true

require "cgi"
require "date"

module EastsideCalendar
  # Card fields stored on the event rows. City pages are not parsed.
  module EventCalendar
    GENERIC = %w[
      ages art arts baby center city club community council county downtown
      family farmers festival kids library market park preschool public story
      storytime teen time toddler
    ].freeze


# The fields, dates, and page a city card is rendered from.
CardAssign = Struct.new(
  :fields, :iso, :info, :end_iso, :schema, :calendar_links, :city_id, :page, :city_name,
  keyword_init: true
)
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

        # One card link for every event row. A webpage in same_as wins.
        # Otherwise the link is the event's heading on its city page.
        def card_link(same_as, city_id, name)
          same = same_as.to_s.strip
          if same.include?("://")
            return { "href" => same, "external" => true }
          end

          cid = city_id.to_s.strip
          slug = Jekyll::Utils.slugify(name.to_s)
          href = ""
          href = "/#{cid}/##{slug}" unless cid.empty? || slug.to_s.empty?
          { "href" => href, "external" => false }
        end

        def stamp_card_links!(site)
          ids = Array(site.data["cities"]).filter_map { |city| city["id"].to_s if city.is_a?(Hash) }
          ids.each do |cid|
            Array(site.data["#{cid}_events"]).each do |row|
              next unless row.is_a?(Hash)

              link = card_link(row["same_as"], cid, row["name"])
              row["href"] = link["href"]
              row["external"] = link["external"]
            end
          end
          Array(site.data["worth_the_drive_events"]).each do |row|
            next unless row.is_a?(Hash)

            link = card_link(row["same_as"], "worth-the-drive", row["name"])
            row["href"] = link["href"]
            row["external"] = link["external"]
          end
        end

        def visible_text(html)
          CGI.unescapeHTML(html.to_s.gsub(/<[^>]+>/, " ")).gsub(/\s+/, " ").strip
        end

        # The calendar glyph is a CSS mask on .event-cal. The link name lives on aria-label.

        def calendar_label(link, count)
          name = link[:name].to_s.strip
          name = "this event" if name.empty?
          label = "Add #{name} to calendar"
          # A second date is visible inside the link, so the name has to include it.
          return label if count < 2

          when_label = link[:when_label].to_s.strip
          when_label.empty? ? label : "#{label}, #{when_label}"
        end

        def assigns_for_fields(card)
          fields = card.fields
          iso = card.iso
          info = card.info
          end_iso = card.end_iso
          schema = card.schema
          calendar_links = card.calendar_links
          city_id = card.city_id
          page = card.page
          city_name = card.city_name
          label_source = info.is_a?(Hash) ? info : {}
          photo = fields["photo"].is_a?(Hash) ? fields["photo"] : {}
          source_links = Array(fields["links"])
          assigns = {
            "label_ready" => true,
            "price" => EventLabels.price_text(label_source),
            "ages_text" => EventLabels.ages_text(label_source),
            "labels" => EventLabels.labels(label_source),
            "attrs" => EventLabels.attrs(label_source),
            "title" => fields["title"],
            "name" => fields["title"],
            "place_city" => city_name.to_s
          }
          assigns["heading_id"] = fields["heading_id"] unless fields["heading_id"].empty?
          assigns["when"] = fields["when"] unless fields["when"].empty?
          assigns["place"] = fields["place"] unless fields["place"].empty?
          assigns["blurbs"] = fields["blurbs"] unless fields["blurbs"].empty?
          assigns["blurb"] = fields["blurbs"].first.to_s unless fields["blurbs"].empty?
          unless photo["src"].to_s.empty?
            assigns["image"] = photo["src"]
            assigns["alt"] = photo["alt"].to_s
            assigns["credit"] = photo["credit"].to_s
            assigns["image_source"] = photo["source"].to_s
            assigns["width"] = photo["width"] unless photo["width"].to_s.empty?
            assigns["height"] = photo["height"] unless photo["height"].to_s.empty?
          end
          assigns["links"] = source_links unless source_links.empty?
          if source_links[0]
            assigns["source_href"] = source_links[0]["href"]
            assigns["source_label"] = source_links[0]["label"]
          end
          if source_links[1]
            assigns["also_href"] = source_links[1]["href"]
            assigns["also_label"] = source_links[1]["label"]
            assigns["also_source_label"] = source_links[1]["label"]
          end
          if calendar_links && !calendar_links.empty?
            count = calendar_links.length
            assigns["calendars"] = calendar_links.map do |link|
              {
                "href" => link[:href].to_s,
                "label" => calendar_label(link, count),
                "when" => count > 1 ? link[:when_label].to_s : ""
              }
            end
          end
          assigns["date"] = iso.to_s unless iso.to_s.empty?
          # City cards keep using the start day as the microdata finish day.
          # end is only the data-end attribute.
          assigns["end"] = end_iso.to_s unless end_iso.to_s.empty?
          same = label_source["same_as"]
          link = card_link(same, city_id, fields["title"])
          assigns["href"] = link["href"]
          assigns["external"] = link["external"]
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
            if assigns["schema_url"].empty? && source_links[0]
              assigns["schema_url"] = source_links[0]["href"].to_s
            end
            assigns["schema_image"] = photo["src"].to_s unless photo["src"].to_s.empty?
            assigns["schema_added"] = schema["added"].to_s
            assigns["schema_url"] = schema["url"].to_s if assigns["schema_url"].to_s.empty?
            if page
              org_event = {
                "organizer" => schema["organizer"].to_s,
                "organizer_url" => schema["organizer_url"].to_s,
                "place" => schema["place"].to_s,
                "locality" => schema["locality"].to_s,
                "city" => schema["locality"].to_s,
                "city_id" => city_id.to_s,
                "added" => schema["added"].to_s
              }
              venue = schema["place"].to_s
              org = StructuredData.organizer_for(page, org_event, assigns["schema_url"].to_s, venue)
              if org
                assigns["schema_organizer"] = org["name"].to_s
                assigns["schema_organizer_url"] = org["url"].to_s
              end
            end
          end
          assigns
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

        # Links printed into href attributes. http(s), a relative path, a
        # fragment, mailto, tel, or webcal. Anything else is dropped.
        def safe_href(value)
          text = value.to_s.strip
          return "" if text.empty? || text.match?(/\A(?:javascript|data|vbscript):/i)
          return text if text.match?(%r{\Ahttps?:\/\/}i)
          return text if text.match?(/\A(?:mailto:|tel:|webcal:)/i)
          return text if text.start_with?("#", "/", "?", "./", "../")
          return "" if text.include?(":")

          text
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

        # Rows that share a card id are one city card. Display text lives on
        # the row that has it. Order follows the old heading order.
        def card_groups(events)
          groups = []
          index = {}
          events.each do |event|
            card_id = event.dig(:labels, "card").to_s
            card_id = "row-#{groups.length}" if card_id.empty?
            if index.key?(card_id)
              groups[index[card_id]][:picks] << event
            else
              index[card_id] = groups.length
              groups << { id: card_id, picks: [event], display: event }
            end
          end
          groups.each do |group|
            display = group[:picks].find do |event|
              labels = event[:labels] || {}
              !labels["when"].to_s.empty? || Array(labels["blurbs"]).any?
            end
            group[:display] = display if display
          end
          groups.sort_by { |group| group[:display].dig(:labels, "order").to_i }
        end

        def fields_from_card(display, title)
          labels = display[:labels] || {}
          place = labels["place_line"].to_s
          place = display[:place].to_s if place.empty?
          photo = labels["photo"].is_a?(Hash) ? labels["photo"] : {}
          {
            "title" => title,
            "heading_id" => labels["heading_id"].to_s,
            "when" => labels["when"].to_s,
            "place" => place,
            "blurbs" => Array(labels["blurbs"]),
            "links" => Array(labels["links"]),
            "photo" => photo
          }
        end

        def visible_from_card(display, picks, today, city_name, city_url)
          labels = display[:labels] || {}
          title = labels["title"].to_s
          title = display[:name] if title.empty?
          when_text = labels["when"].to_s
          heading = { text: title, when_text: when_text, body: "" }
          card_date = heading_date(heading, picks, today)
          chosen = picks.find { |event| card_date && event[:start] && event[:start][:date] == card_date }
          chosen ||= picks.min_by { |event| sort_key(event[:start]) }
          start_parsed = if chosen && chosen[:start] && (card_date.nil? || chosen[:start][:date] == card_date)
                           chosen[:start]
                         elsif card_date
                           { date: card_date, time: nil }
                         end
          finish = schema_end(start_parsed, chosen && chosen[:end])
          place = labels["place_line"].to_s
          place = chosen[:place].to_s if place.empty? && chosen
          place_name, street = place_parts(place, city_name)
          place_name = city_name if place_name.empty?
          blurb = labels["description"].to_s
          blurb = "#{title} in #{city_name}." if blurb.empty?
          same = chosen && chosen[:same_as].to_s
          anchor = labels["heading_id"].to_s
          anchor = slugify(title) if anchor.empty?
          {
            "name" => title,
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
            "shareEnd" => share_end_value(start_parsed, chosen && chosen[:end]),
            "heading_id" => anchor
          }
        end
  end
end
