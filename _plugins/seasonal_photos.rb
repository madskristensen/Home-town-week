# frozen_string_literal: true

require "date"

module EastsideCalendar
  # Photos for hub cards and city cards. A designed card is not used as a photo.
  module SeasonalHubs
    # A hub card and the photo pools it may use.
CardPass = Struct.new(
  :hub, :site, :pages, :catalog, :venues, :groups, :pools, :hubs,
  keyword_init: true
)
# The photo index shared by city cards and hub cards.
PhotoIndex = Struct.new(
  :site, :pages, :catalog, :venues, :groups, :hubs, :pools,
  keyword_init: true
)
    module_function


        # Own photo, then that venue, then a themed picture, then a seasonal
        # pool picture, then the year-round pool. Prefer a CC or public-domain
        # photo of the event or the venue. When none exists, use the
        # organizer's or venue's own photo (license: organizer), credited and
        # linked. A venue photo is the place itself, so every event there can
        # use it. A theme file is used once on a page. A pool file is used
        # once, then the least-used pool picture may repeat so the card stays
        # a real photo. A designed card is not used. The city hero is not in
        # this chain.
        def attach_cards!(pass)
          hub = pass.hub
          site = pass.site
          pages = pass.pages
          catalog = pass.catalog
          venues = pass.venues
          groups = pass.groups
          pools = pass.pools
          hubs = pass.hubs
          used = {}
          pool_uses = Hash.new(0)
          chosen = {}
          audit = { "own" => [], "venue" => [], "theme" => [], "pool" => [], "none" => [] }
          page_pool = pool_entries(pools, hub["id"])
          today = EventCalendar.pacific_today(site.time)
          Array(hub["sections"]).each do |section|
            kept = []
            Array(section["events"]).each do |event|
              page = pages[event["city_id"].to_s]
              key = "#{event["city_id"]}|#{event["name"]}"
              card = find_card(catalog, event)
              blurb = event["blurb"].to_s.strip
              blurb = card[:blurb].to_s if blurb.empty? && card
              next unless real_blurb?(blurb, event)

              event["blurb"] = blurb
              event["description"] = blurb
              event["calendar"] = calendar_href(page, event)
              event["calendar"] = write_calendar(site, event) if event["calendar"].empty?

              entries = pool_list_for(event, page_pool, pools, hubs, today)
              if chosen.key?(key)
                prev = chosen[key]
                # The same event in a second section may repeat its own photo.
                # A venue or theme file stays once on the page.
                photo = if prev && prev["kind"] == "own"
                          prev
                        else
                          pick_photo(photo_candidates(event, card, venues, groups, entries), used, pool_uses)
                        end
                apply_photo!(event, photo)
                record_photo!(audit, event, photo)
                kept << event
                next
              end

              photo = pick_photo(photo_candidates(event, card, venues, groups, entries), used, pool_uses)
              chosen[key] = photo
              apply_photo!(event, photo)
              record_photo!(audit, event, photo)
              kept << event
            end
            section["events"] = kept
          end
          parts = audit.map { |kind, names| "#{kind} #{names.size}" }
          Jekyll.logger.info("Hub photos:", "#{hub["path"]} #{parts.join(", ")}")
          audit.each do |kind, names|
            next if names.empty?

            Jekyll.logger.info("Hub photos:", "  #{kind}: #{names.join("; ")}")
          end
          missing = audit["none"]
          return if missing.empty?

          raise "Hub #{hub["path"]} has #{missing.size} grid cards without an image: #{missing.join('; ')}"
        end

        def real_blurb?(blurb, event)
          text = blurb.to_s.strip
          return false if text.empty?

          name = event["name"].to_s.strip
          city = event["city"].to_s.strip
          filler = "#{name} in #{city}."
          return false if text.casecmp(filler).zero?
          return false if text.casecmp("#{name} in #{city}").zero?

          true
        end

        def index_card_photos!(pass)
          site = pass.site
          pages = pass.pages
          catalog = pass.catalog
          venues = pass.venues
          groups = pass.groups
          hubs = pass.hubs
          pools = pass.pools
          today = EventCalendar.pacific_today(site.time)
          fallback = nil
          (seasonal_default_entries(pools, hubs, today) + pool_entries(pools, "general")).each do |entry|
            fallback = listed_photo(entry, "pool")
            break if fallback
          end
          site.data["card_photo_fallback"] = fallback ? public_photo(fallback) : nil

          options = {}
          Array(site.data["cities"]).each do |city|
            next unless city.is_a?(Hash)

            city_id = city["id"].to_s
            next if city_id.empty?

            bucket = {}
            Array(site.data["#{city_id}_events"]).each do |event|
              next unless event.is_a?(Hash)

              name = event["name"].to_s
              next if name.empty?

              row = event.merge("city_id" => city_id, "city" => city["name"].to_s)
              card = find_card(catalog, row)
              entries = pool_list_for(row, [], pools, hubs, today)
              bucket[name] = photo_candidates(row, card, venues, groups, entries).map { |photo| public_photo(photo) }
            end
            options[city_id] = bucket
          end
          site.data["card_photo_options"] = options
        end

        def photo_candidates(event, card, venues, groups, pool = nil)
          list = []
          own = usable_own(card && card[:photo])
          list << own if own
          matching_venues(event, venues).each do |entry|
            photo = listed_photo(entry, "venue")
            list << photo if photo
          end
          theme = matching_theme(event, groups)
          Array(theme && theme["images"]).each do |entry|
            photo = listed_photo(entry, "theme")
            list << photo if photo
          end
          Array(pool).each do |entry|
            photo = listed_photo(entry, "pool")
            list << photo if photo
          end
          list.uniq { |photo| photo["src"] }
        end

        # The event's own season, then this page's pool. An event with neither
        # uses the pools of hubs that are in season, so a fall weekend stays
        # with fall pictures instead of another holiday.
        def pool_list_for(event, page_pool, pools, hubs, today)
          list = []
          seen = {}
          push = lambda do |entries|
            Array(entries).each do |entry|
              next unless entry.is_a?(Hash)

              src = entry["image"].to_s
              src = entry["src"].to_s if src.empty?
              next if src.empty? || seen[src]

              seen[src] = true
              list << entry
            end
          end
          push.call(pool_entries(pools, matching_hub_id(event, hubs)))
          push.call(page_pool)
          push.call(seasonal_default_entries(pools, hubs, today)) if list.empty?
          # Year-round pool is the last fallback, including in summer when no hub is in season.
          push.call(pool_entries(pools, "general"))
          list
        end

        def seasonal_default_entries(pools, hubs, today)
          return [] unless today

          Array(hubs).flat_map do |hub|
            next [] unless hub.is_a?(Hash)

            start_s = hub.dig("season", "start").to_s
            end_s = hub.dig("season", "end").to_s
            next [] unless in_season?(today, start_s, end_s)

            pool_entries(pools, hub["id"])
          end
        end

        def pool_entries(pools, hub_id)
          return [] unless pools.is_a?(Hash) && !hub_id.to_s.empty?

          Array(pools[hub_id.to_s])
        end

        def matching_hub_id(event, hubs)
          tags = Array(event["tags"]).map { |tag| tag.to_s.downcase }
          hay = "#{event["name"]} #{event["place"]}".downcase
          Array(hubs).each do |hub|
            next unless hub.is_a?(Hash)

            Array(hub["sections"]).each do |section|
              next unless section.is_a?(Hash)

              section_tags = Array(section["tags"]).map { |tag| tag.to_s.downcase }
              return hub["id"].to_s unless (tags & section_tags).empty?

              if phrases(section["keywords"]).any? { |phrase| hay.include?(phrase) }
                return hub["id"].to_s
              end
            end
            hub_tags = Array(hub["tags"]).map { |tag| tag.to_s.downcase }
            return hub["id"].to_s unless (tags & hub_tags).empty?

            return hub["id"].to_s if phrases(hub["keywords"]).any? { |phrase| hay.include?(phrase) }
          end
          nil
        end

        # A venue photo can repeat, because each card is that same place.
        # A theme file is used once. When every candidate on the page is
        # taken, the least-used seasonal pool picture is used again.
        def pick_photo(candidates, used, pool_uses = nil)
          pool_uses ||= Hash.new(0)
          candidates.each do |photo|
            reusable = photo["kind"] == "venue" || photo["kind"] == "own"
            next if !reusable && used[photo["src"]]

            used[photo["src"]] = true unless reusable
            pool_uses[photo["src"]] += 1 if photo["kind"] == "pool"
            return photo
          end
          pools = candidates.select { |photo| photo["kind"] == "pool" && !photo["src"].to_s.empty? }
          return nil if pools.empty?

          photo = pools.min_by { |item| [pool_uses[item["src"]].to_i, item["src"].to_s] }
          pool_uses[photo["src"]] += 1
          photo
        end

        # Kept for the SVG helper. Event cards do not call this.
        def apply_photo!(event, photo)
          if photo
            alt = photo["alt"].to_s.strip
            alt = "#{event["name"]} in #{event["city"]}" if alt.empty? || alt.start_with?("Photo:")
            event["image"] = photo["src"]
            event["image_alt"] = alt
            event["image_credit"] = photo["credit"].to_s
            event["image_source"] = photo["source"].to_s
            event["image_kind"] = photo["kind"]
          else
            event.delete("image")
            event["image_kind"] = "none"
          end
        end

        def record_photo!(audit, event, photo)
          kind = photo ? photo["kind"] : "none"
          label = "#{event["name"]} (#{event["city"]})"
          label = "#{label} [#{File.basename(photo["src"])}]" if photo
          audit[kind] << label
        end

        def public_photo(photo)
          {
            "src" => photo["src"],
            "alt" => photo["alt"],
            "credit" => photo["credit"],
            "source" => photo["source"],
            "kind" => photo["kind"]
          }
        end

        def usable_own(photo)
          licensed = licensed_photo(photo)
          return nil unless licensed
          return nil if people_photo?(licensed)

          licensed.merge("kind" => "own")
        end

        def listed_photo(entry, kind)
          return nil unless entry.is_a?(Hash)

          photo = licensed_photo(
            "src" => entry["image"],
            "alt" => entry["alt"],
            "credit" => entry["credit"],
            "source" => entry["source"],
            "license" => entry["license"]
          )
          return nil unless photo
          return nil if people_photo?(photo)

          photo.merge("kind" => kind)
        end

        # The longest key wins, so "renton highlands library" is that branch
        # and not a shorter library name that also fits the text.
        def matching_venues(event, venues)
          hay = "#{event["name"]} #{event["place"]}".downcase
          ranked = Array(venues).filter_map do |venue|
            hit = Array(venue["keys"]).map { |key| key.to_s.downcase.strip }.select do |key|
              !key.empty? && hay.include?(key)
            end.max_by(&:length)
            hit ? [hit.length, venue] : nil
          end
          return [] if ranked.empty?

          best = ranked.map(&:first).max
          ranked.select { |length, _venue| length == best }.map(&:last)
        end

        def fallback_choice(bucket, name)
          return nil unless bucket.is_a?(Hash)

          list = bucket[name]
          if list.nil?
            want = EventCalendar.normalize(name)
            bucket.each do |key, value|
              next unless EventCalendar.normalize(key) == want

              list = value
              break
            end
          end
          Array(list).find { |photo| photo.is_a?(Hash) && photo["kind"].to_s != "designed" && !photo["src"].to_s.empty? }
        end

        # A specific event type in the name or place wins over a broad tag,
        # so a pumpkin patch that is also tagged as a maze still shows
        # pumpkins. A trunk-or-treat tag wins over a title that only says
        # "fall festival".
        def matching_theme(event, groups)
          tags = Array(event["tags"]).map { |tag| tag.to_s.downcase }
          hay = "#{event["name"]} #{event["place"]}".downcase
          if tags.include?("trunk-or-treat") || hay.include?("trunk-or-treat") || hay.include?("trunk or treat")
            trunk = Array(groups).find { |group| keys_hit?(group, "trunk or treat", []) }
            return trunk if trunk
          end

          named = Array(groups).find { |group| keys_hit?(group, hay, []) }
          return named if named

          Array(groups).find { |group| keys_hit?(group, "", tags) }
        end

        def keys_hit?(entry, hay, tags)
          Array(entry["keys"]).any? do |key|
            text = key.to_s.downcase.strip
            next false if text.empty?

            tags.include?(text) || (!hay.empty? && hay.include?(text))
          end
        end

        def people_photo?(photo)
          src = photo["src"].to_s
          return true if src.include?("teen-lounge") || src.include?("red-barn-festival")

          alt = photo["alt"].to_s.gsub(/children's museum/i, "")
          alt.match?(/\b(child|children|teen|teens|toddler|baby)\b/i)
        end

        # Credit text, a source URL, and either an open license or license "organizer".
        # Open licenses are CC0, CC BY, CC BY-SA, and public domain. An organizer
        # or venue photo with no open license still runs. The credit text links
        # to the source.
        def licensed_photo(photo)
          return nil unless photo.is_a?(Hash)

          src = photo["src"].to_s.strip
          credit = photo["credit"].to_s.strip
          source = photo["source"].to_s.strip
          license = photo["license"].to_s.strip
          return nil if src.empty? || credit.empty?
          return nil unless src.start_with?("/")
          return nil unless source.match?(%r{\Ahttps?://}i)

          open_license = "#{credit} #{license}".match?(/\b(?:CC0|CC\s*BY(?:-SA)?|public domain)\b/i)
          organizer = license.match?(/\borganizer\b/i)
          return nil unless open_license || organizer

          photo.merge("src" => src, "credit" => credit, "source" => source, "license" => license)
        end

        def calendar_href(page, event)
          return "" unless page

          groups = page.data["calendar_groups"]
          return "" unless groups.is_a?(Hash)

          raw = event["start_raw"].to_s
          raw = event["start"].to_s if raw.empty?
          start_parsed = EventCalendar.parse_when(raw)
          return "" unless start_parsed

          want = EventCalendar.file_slug(event["name"], start_parsed)
          groups.each_value do |bucket|
            Array(bucket).flatten.each do |link|
              return link[:href].to_s if link[:href].to_s.include?(want)
            end
          end
          ""
        end

        def write_calendar(site, event)
          start_parsed = EventCalendar.parse_when(event["start_raw"])
          return "" unless start_parsed

          city_id = event["city_id"].to_s
          return "" if city_id.empty?

          slug = EventCalendar.file_slug(event["name"], start_parsed)
          dir = "#{city_id}/calendar"
          filename = "#{slug}.ics"
          href = EventCalendar.root_path(site, "/#{dir}/#{filename}")
          already = site.static_files.any? { |file| file.respond_to?(:relative_path) && file.relative_path == "#{dir}/#{filename}" }
          return href if already

          city_url = EventCalendar.absolute_url(site, "/#{city_id}/")
          same = event["same_as"].to_s
          page_url = EventCalendar.http_url?(same) ? same : city_url
          record = {
            name: event["name"],
            start: start_parsed,
            end: EventCalendar.parse_when(event["end_raw"]),
            place: event["place"].to_s,
            same_as: same,
            uid: "#{city_id}-#{slug}@eastsidecalendar.com",
            url: page_url,
            description: EventCalendar.description_for(
              { same_as: same, start: start_parsed, end: EventCalendar.parse_when(event["end_raw"]) },
              event["blurb"].to_s,
              city_url
            )
          }
          site.static_files << CalendarFile.new(dir, filename, EventCalendar.build_ics(record, city_url, EventCalendar.stamp_utc(site.time)))
          href
        end
  end
end
