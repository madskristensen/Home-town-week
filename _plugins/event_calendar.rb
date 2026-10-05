# frozen_string_literal: true

require "date"
require "json"
require_relative "event_time"
require_relative "event_ics"
require_relative "event_cards"
require_relative "event_designed"

module EastsideCalendar
  class EventCalendarGenerator
    # Called from SitePipeline before hub cards link to these files.

    def generate(site)
      today = EventCalendar.pacific_today(site.time)
      site.data["pacific_today"] = EventCalendar.iso_date(today)
      linked = 0
      feed_events = 0
      unmatched = 0
      undated = 0
      dtstamp = EventCalendar.stamp_utc(site.time)

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
      card_groups = EventCalendar.card_groups(events)
      groups = Hash.new { |hash, key| hash[key] = [] }
      dates = Hash.new { |hash, key| hash[key] = [] }
      ends = Hash.new { |hash, key| hash[key] = [] }
      labels = Hash.new { |hash, key| hash[key] = [] }
      used = {}
      feed_uids = {}
      feed = []
      schemas = Hash.new { |hash, key| hash[key] = [] }
      visible = []
      linked = 0
      city_name = EventCalendar.city_name_for(site, page)

      city_path = page.url.to_s
      city_url = EventCalendar.absolute_url(site, city_path)
      dir = "#{city_path.sub(%r{\A/}, '').sub(%r{/\z}, '')}/calendar"

      card_assigns = []
      card_groups.each do |group|
        picks = group[:picks].sort_by { |event| EventCalendar.sort_key(event[:start]) }
        display = group[:display]
        meta = display[:labels] || {}
        title = meta["title"].to_s
        title = display[:name] if title.empty?
        heading = {
          key: EventCalendar.normalize(title),
          text: title,
          when_text: meta["when"].to_s
        }
        blurb = meta["description"].to_s
        blurb = EventCalendar.plain_blurb(Array(meta["blurbs"]).join(" ")) if blurb.empty?
        links = picks.map do |event|
          slug = unique_slug(used, EventCalendar.file_slug(event[:name], event[:start]))
          filename = "#{slug}.ics"
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
          { href: href, when_label: record[:when_label], name: title }
        end
        picks.each do |event|
          next unless EventCalendar.upcoming_event?(event, today)

          source = EventCalendar.http_url?(event[:same_as]) ? event[:same_as] : ""
          cost = event.dig(:labels, "cost").to_s.strip
          feed << {
            uid: EventCalendar.feed_uid(source, event[:start], title, feed_uids),
            start: event[:start],
            end: event[:end],
            name: title,
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
        rec = EventCalendar.visible_from_card(display, picks, today, city_name, city_url)
        rec["cost"] = info && info["cost"].to_s
        schemas[heading[:key]] << rec
        visible << rec
        fields = EventCalendar.fields_from_card(display, title)
        card_assigns << EventCalendar.assigns_for_fields(EventCalendar::CardAssign.new(
          fields: fields,
          iso: rec["date"],
          info: info,
          end_iso: finish ? EventCalendar.iso_date(finish) : nil,
          schema: rec,
          calendar_links: links,
          city_id: page.data["city"],
          page: page,
          city_name: city_name
        ))
      end
      page.data["city_card_assigns"] = card_assigns

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

      matched = card_groups.sum { |group| group[:picks].size }
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
            "tags" => item["tags"],
            "card" => item["card"].to_s,
            "order" => item["order"],
            "heading_id" => item["heading_id"].to_s,
            "title" => item["title"].to_s,
            "when" => item["when"].to_s,
            "place_line" => item["place_line"].to_s,
            "blurbs" => item["blurbs"],
            "links" => item["links"],
            "photo" => item["photo"],
            "description" => item["description"].to_s,
            "hub_blurb" => item["hub_blurb"].to_s
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

Jekyll::Hooks.register :site, :post_read do |site|
  EastsideCalendar::EventCalendar.stamp_card_links!(site)
end

module EastsideCalendar
  module MailEscape
    def mail_escape(input)
      TextUtil.encode(input)
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

    # Same start and end the old Event JSON-LD used. End is never blank
    # when a start exists.
    def google_dates(input)
      share_start, share_end, raw_start, raw_end, iso_start, iso_end = input.to_s.split("|", 6)
      event = {
        "shareStart" => share_start.to_s,
        "shareEnd" => share_end.to_s,
        "start_raw" => raw_start.to_s,
        "end_raw" => raw_end.to_s,
        "start" => raw_start.to_s,
        "end" => raw_end.to_s,
        "startDate" => iso_start.to_s,
        "endDate" => iso_end.to_s
      }
      start_on, end_on = StructuredData.google_interval(event)
      start_on = start_on.to_s
      end_on = end_on.to_s
      end_on = start_on if end_on.empty? && !start_on.empty?
      "#{start_on}|#{end_on}"
    end

    def offer_amount(input)
      amount = StructuredData.offer_amount(input)
      return "" if amount.nil?
      return amount.to_i.to_s if amount.is_a?(Float) && (amount % 1).zero?

      amount.to_s
    end

    def offer_from(input)
      site = @context.registers[:site]
      StructuredData.valid_from({ "added" => input.to_s }, site).to_s
    end

    def schema_short(input)
      StructuredData.short_description(input.to_s)
    end

    def pacific_day(_input)
      site = @context.registers[:site]
      EventCalendar.pacific_today(site.time).iso8601
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
  end
end

Liquid::Template.register_filter(EastsideCalendar::MailEscape)
Liquid::Template.register_filter(EastsideCalendar::CardBlurbFilter)
Liquid::Template.register_filter(EastsideCalendar::SchemaFilters)
