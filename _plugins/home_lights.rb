# frozen_string_literal: true

module EastsideCalendar
  # Rows with map: true become a lights-style map.
  # holiday_lights.yml is /christmas/lights/.
  # halloween_decorations.yml is /fall/decorations/.
  module HomeLights
    module_function

    def attach!(site, _hubs)
      site.data["home_lights"] = collect(site, "holiday_lights", "christmas", "Home lights photos:")
      site.data["halloween_map"] = collect(site, "halloween_decorations", "halloween", "Halloween decorations photos:")
      site.data["farmers_market_page"] = collect_markets(site)
      site.data["book_ahead_cards"] = collect_book_ahead(site)
      site.data["birthday_page"] = collect_birthdays(site)
      site.data["indoor_play_page"] = collect_directory(site, "indoor_play", "Indoor play:")
      site.data["feature_map_pins"] = feature_map_pins(site)
    end

    def collect(site, data_key, pool_name, log_label)
      names = city_names(site.data["cities"])
      rows = Array(site.data[data_key]).select { |row| row.is_a?(Hash) && row["map"] == true }
      rows = rows.sort_by { |row| [names[row["city"].to_s].to_s.downcase, row["name"].to_s.downcase] }
      fallbacks = fallback_photos(site, pool_name)
      used = {}
      audit = Hash.new { |hash, key| hash[key] = [] }
      items = []
      rows.each do |row|
        item = light_item(row, names, items.size + 1)
        next unless item

        photo = real_photo(row["photo"], item["name"])
        if photo
          used[photo["src"]] = true
        else
          photo = next_fallback(fallbacks, used)
        end
        apply_photo!(item, photo)
        kind = photo ? photo["kind"] : "none"
        label = "#{item["name"]} (#{item["city"]})"
        label = "#{label} [#{File.basename(photo["src"])}]" if photo
        audit[kind] << label
        items << item
      end
      parts = audit.map { |kind, labels| "#{kind} #{labels.size}" }
      Jekyll.logger.info(log_label, parts.join(", "))
      audit.each do |kind, labels|
        next if labels.empty?

        Jekyll.logger.info(log_label, "  #{kind}: #{labels.join("; ")}")
      end

      towns = []
      items.each do |item|
        town = towns.last
        if town.nil? || town["id"] != item["city_id"]
          town = { "id" => item["city_id"], "name" => item["city"], "lights" => [] }
          towns << town
        end
        town["lights"] << item
      end
      pins = items.filter_map do |item|
        next if item["lat"].nil? || item["lng"].nil?

        {
          "n" => item["number"],
          "lat" => item["lat"],
          "lng" => item["lng"],
          "name" => item["name"],
          "id" => item["id"]
        }
      end
      town_groups!(towns)
      {
        "towns" => towns,
        "pins" => pins,
        "count" => items.size
      }
    end

    # Data for the shared Group by pills (Town, Distance) on each map card.
    def town_groups!(towns)
      towns.each_with_index do |town, index|
        town["count"] = town["lights"].size
        town["lights"].each_with_index do |item, spot|
          bits = [
            %(data-town="town-#{town["id"]}"), %(data-town-name="#{CGI.escapeHTML(town["name"].to_s)}"),
            %(data-town-order="#{index + 1}"), %(data-sort="#{format("%02d%03d", index + 1, spot)}")
          ]
          bits << %(data-lat="#{item["lat"]}" data-lng="#{item["lng"]}") if item["lat"] && item["lng"]
          item["group_attrs"] = bits.join(" ")
        end
      end
    end

    def city_names(cities)
      TextUtil.city_names(cities)
    end

    def light_item(row, names, number)
      city_id = row["city"].to_s.strip
      city_name = names[city_id].to_s
      return nil if city_name.empty?

      name = row["name"].to_s.strip
      return nil if name.empty?

      address = row["address"].to_s.gsub(/\s+/, " ").strip
      return nil if address.empty?

      description = row["description"].to_s.gsub(/\s+/, " ").strip
      return nil if description.empty?

      source = row["source"].to_s.strip
      return nil unless source.match?(%r{\Ahttps://\S+\z})

      also_source = row["also_source"].to_s.strip
      also_source = "" unless also_source.match?(%r{\Ahttps://\S+\z})

      {
        "id" => slug(row["id"], name),
        "number" => number,
        "name" => name,
        "city" => city_name,
        "city_id" => city_id,
        "address" => address,
        "description" => description,
        "nights" => row["nights"].to_s.gsub(/\s+/, " ").strip,
        "hours" => row["hours"].to_s.gsub(/\s+/, " ").strip,
        "source" => source,
        "source_label" => row["source_label"].to_s.strip,
        "also_source" => also_source,
        "also_source_label" => row["also_source_label"].to_s.strip,
        "trust_label" => trust_label(row["trust"]),
        "lat" => coordinate(row["lat"]),
        "lng" => coordinate(row["lng"])
      }
    end

    def trust_label(value)
      case value.to_s.strip
      when "owner" then "Listed by owner"
      when "tip" then "Community tip"
      else ""
      end
    end

    def coordinate(value)
      number = Float(value)
      number.finite? ? number : nil
    rescue ArgumentError, TypeError
      nil
    end

    def slug(id, name)
      raw = id.to_s.strip
      raw = name.to_s if raw.empty?
      text = raw.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
      text.empty? ? "stop" : text
    end

    def real_photo(photo, name)
      return nil unless photo.is_a?(Hash)

      image = photo["image"].to_s.strip
      credit = photo["credit"].to_s.strip
      source = photo["credit_url"].to_s.strip
      return nil unless image.start_with?("/assets/images/")
      return nil if credit.empty? || !source.match?(%r{\Ahttps://})
      # A logo alt can name a brand like "Soulful Kids"; it is not a photo of kids.
      return nil if !image.include?("/birthdays/logos/") && kids_photo?(photo["alt"], image)

      alt = photo["alt"].to_s.strip
      alt = name if alt.empty?
      {
        "src" => image,
        "alt" => alt,
        "credit" => credit,
        "source" => source,
        "kind" => "real"
      }
    end

    def kids_photo?(alt, image)
      return true if image.to_s.include?("teen-lounge")

      text = alt.to_s.gsub(/children's museum/i, "")
      text.match?(/\b(child|children|kid|kids|teen|teens|toddler|baby)\b/i)
    end

    def fallback_photos(site, pool_name)
      pool = Array(site.data.dig("hub_pools", pool_name))
      if pool_name == "christmas"
        lights, rest = pool.partition { |entry| entry.is_a?(Hash) && entry["image"].to_s.include?("/lights-") }
        pool = lights + rest
      end
      pool.filter_map { |entry| SeasonalHubs.listed_photo(entry, "pool") }
    end

    def next_fallback(photos, used)
      photos.each do |photo|
        next if used[photo["src"]]

        used[photo["src"]] = 1
        return photo
      end
      return nil if photos.empty?

      photo = photos.min_by { |item| [photo_use_count(used, item["src"]), item["src"].to_s] }
      used[photo["src"]] = photo_use_count(used, photo["src"]) + 1
      photo
    end

    def photo_use_count(used, src)
      value = used[src]
      return 1 if value == true
      return 0 if value.nil?

      value.to_i
    end

    def apply_photo!(item, photo)
      return unless photo

      alt = photo["alt"].to_s.strip
      alt = "#{item["name"]} in #{item["city"]}" if alt.empty?
      item["image"] = photo["src"]
      item["image_alt"] = alt
      item["image_credit"] = photo["credit"].to_s
      item["image_source"] = photo["source"].to_s
      item["image_kind"] = photo["kind"]
    end

    # Farmers markets stay in the data file after the season ends.
    # The card line is Open now or the return text, from the dates.
    def collect_markets(site)
      today = EventCalendar.pacific_today(site.time)
      names = city_names(site.data["cities"])
      rows = Array(site.data["farmers_markets"]).select { |row| row.is_a?(Hash) }
      rows = rows.sort_by { |row| [names[row["city"].to_s].to_s.downcase, row["name"].to_s.downcase] }
      items = []
      rows.each do |row|
        item = market_item(row, names, today)
        next unless item

        photo = market_photo(row["photo"], item["name"], site)
        unless photo
          Jekyll.logger.error("Farmers markets:", "no usable photo for #{item["name"]}")
          next
        end
        apply_photo!(item, photo)
        items << item
      end
      # No numbers on this page: plain pins, and each card keeps an id
      # so a pin click and #light-{id} links still land on its card.
      items.each do |item|
        item.delete("number")
        item["card_id"] = "light-#{item["id"]}"
      end
      pins = items.filter_map do |item|
        next if item["lat"].nil? || item["lng"].nil?

        { "lat" => item["lat"], "lng" => item["lng"], "name" => item["name"], "id" => item["id"] }
      end
      Jekyll.logger.info("Farmers markets:", "#{items.size} markets, #{pins.size} on the map")
      drive_rows = Array(site.data["farmers_market_drive"]).select { |row| row.is_a?(Hash) }
      drive = market_drive_items(drive_rows, names, today, site)
      stand_rows = Array(site.data["farm_stands"]).select { |row| row.is_a?(Hash) }
      stands = farm_stand_items(stand_rows, names, today, site)
      packed = pack_towns(items + stands + drive)
      stand_town = packed["towns"].find { |town| town["id"] == "farm-stands" }
      if stand_town
        stand_town["name"] = "Farm stands"
        stand_town["intro"] = "Farm stands and farm stores that sell their own harvest on the farm, checked on each farm's own page."
      end
      drive_town = packed["towns"].find { |town| town["id"] == "worth-the-drive" }
      if drive_town
        drive_town["name"] = "Worth the drive"
        drive_town["intro"] = "Just outside the Eastside, but worth the drive for a big market morning."
      end
      market_groups!(packed, rows + stand_rows + drive_rows)
      packed["pins"] = pins
      packed
    end

    # Worth the drive: standout markets just outside the 15 cities. The
    # card shows the city with the address. No number, so no map pin.
    def market_drive_items(rows, names, today, site)
      rows.filter_map do |row|
        place = row["place_city"].to_s.strip
        item = market_item(row.merge("city" => names.keys.first), names, today)
        next unless item && !place.empty?

        photo = market_photo(row["photo"], item["name"], site)
        unless photo
          Jekyll.logger.error("Farmers markets:", "no usable photo for #{item["name"]}")
          next
        end
        apply_photo!(item, photo)
        item["city"] = place
        item["city_id"] = "worth-the-drive"
        item["card_id"] = "light-#{item["id"]}"
        item["address"] = "#{item["address"]}, #{place}"
        item.delete("number")
        item
      end
    end

    # Farm stands: _data/farm_stands.yml. One group after the markets.
    # The town sits on the address line. Photo is optional: a real,
    # credited photo of that farm, or none. No number, so no map pin.
    def farm_stand_items(rows, names, today, site)
      rows.sort_by { |row| [names[row["city"].to_s].to_s.downcase, row["name"].to_s.downcase] }.filter_map do |row|
        item = market_item(row, names, today)
        unless item
          Jekyll.logger.error("Farm stands:", "skipped #{row["name"]}")
          next
        end
        photo = row["photo"] && market_photo(row["photo"], item["name"], site)
        apply_photo!(item, photo) if photo
        town = item["city"]
        item["address"] = "#{item["address"]}, #{town}" unless item["address"].include?(",")
        item["city_id"] = "farm-stands"
        item["setting"] = row["setting"].to_s.strip.empty? ? "none" : row["setting"].to_s.strip
        item["card_id"] = "light-#{item["id"]}"
        item.delete("number")
        item
      end
    end

    MARKET_DAYS = %w[Monday Tuesday Wednesday Thursday Friday Saturday Sunday].freeze

    # Data for the shared Group by pills (Town, Day, Distance) on each card.
    # Town ids stay town-{city} so old #town- links still land.
    def market_groups!(packed, rows)
      by_id = rows.to_h { |row| [slug(row["id"], row["name"]), row] }
      packed["towns"].each_with_index do |town, index|
        town["count"] = town["lights"].size
        town["lights"].each_with_index do |item, spot|
          row = by_id[item["id"]] || {}
          text = [row["when_open"], row["when_closed"], row["description"]].join(" ")
          day = MARKET_DAYS.min_by { |name| text.index(name) || 9999 }
          day = nil unless text.include?(day.to_s)
          order = MARKET_DAYS.index(day) || 9
          label = day ? "#{day}s" : "Other days"
          day ||= "other"
          if text.match?(/\bdaily\b/i)
            day, label, order = "daily", "Every day", -1
          end
          bits = [
            %(data-town="town-#{town["id"]}"), %(data-town-name="#{CGI.escapeHTML(town["name"].to_s)}"),
            %(data-town-order="#{index + 1}"), %(data-sort="#{format("%02d%03d", index + 1, spot)}"),
            %(data-day="#{day.downcase}"), %(data-day-label="#{label}"), %(data-day-order="#{order + 1}")
          ]
          bits << %(data-lat="#{item["lat"]}" data-lng="#{item["lng"]}") if item["lat"] && item["lng"]
          # Season dates for the Open now grouping, worked out in the browser.
          bits << %(data-season-start="#{row["season_start"]}") if market_date(row["season_start"])
          bits << %(data-season-end="#{row["season_end"]}") if market_date(row["season_end"])
          extra = Array(row["extra_dates"]).filter_map { |value| market_date(value)&.iso8601 }
          bits << %(data-season-extra="#{extra.join(" ")}") unless extra.empty?
          ranges = market_seasons(row).map { |start_on, end_on, _| "#{start_on.iso8601}:#{end_on.iso8601}" }
          bits << %(data-season-ranges="#{ranges.join(" ")}") unless ranges.empty?
          item["group_attrs"] = bits.join(" ")
        end
      end
    end

    def market_item(row, names, today)
      item = light_item(row, names, 0)
      return nil unless item

      status = market_status(row, today)
      return nil if status.empty?

      item["nights"] = status
      item["hours"] = ""
      item
    end

    # A row may list several seasons in a year (a farm shop with fall,
    # holiday, and summer hours). Each season has start, end, and when_open.
    def market_seasons(row)
      Array(row["seasons"]).filter_map do |season|
        next unless season.is_a?(Hash)
        start_on = market_date(season["start"])
        end_on = market_date(season["end"])
        next unless start_on && end_on
        [start_on, end_on, squash(season["when_open"])]
      end.sort
    end

    def market_status(row, today)
      seasons = market_seasons(row)
      unless seasons.empty?
        current = seasons.find { |start_on, end_on, _| today >= start_on && today <= end_on }
        return (current[2].empty? ? squash(row["when_open"]) : current[2]) if current
        upcoming = seasons.find { |start_on, _, _| start_on > today }
        template = row["when_next"].to_s.strip
        if upcoming && template.include?("%s")
          return format(template, upcoming[0].strftime("%b %-d"))
        end
        return squash(row["when_closed"])
      end

      start_on = market_date(row["season_start"])
      end_on = market_date(row["season_end"])
      extras = Array(row["extra_dates"]).filter_map { |value| market_date(value) }.sort
      if start_on && end_on && today >= start_on && today <= end_on
        return squash(row["when_open"])
      end

      upcoming = extras.select { |date| date >= today }
      unless upcoming.empty?
        date = upcoming.first
        if date == today
          today_line = squash(row["when_extra_today"])
          return today_line unless today_line.empty?
        end
        template = row["when_next"].to_s.strip
        if template.include?("%s")
          return format(template, date.strftime("%b %-d"))
        end
        return squash(template) unless template.empty?
      end

      if start_on && today < start_on
        opens = squash(row["when_opens"])
        return opens unless opens.empty?
      end
      squash(row["when_closed"])
    end

    def market_date(value)
      Date.iso8601(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def squash(value)
      TextUtil.squash(value)
    end

    def market_photo(photo, name, site)
      built = real_photo(photo, name)
      return nil unless built

      path = File.join(site.source, built["src"].sub(%r{\A/}, ""))
      return nil unless File.file?(path)

      built
    end

    # Kids birthday party venues for /birthday-venues/. Rows are
    # _data/birthday_venues.yml. Each card is the shared event card. The
    # type, setting, toddler, and party room labels are pills and chips.
    # price_level is a quiet $ to $$$$ line, never a pill.
    BIRTHDAY_LEVELS = { 1 => "$", 2 => "$$", 3 => "$$$", 4 => "$$$$" }.freeze

    def collect_birthdays(site)
      names = city_names(site.data["cities"])
      rows = Array(site.data["birthday_venues"]).select { |row| row.is_a?(Hash) }
      rows = rows.sort_by { |row| [names[row["city"].to_s].to_s.downcase, row["name"].to_s.downcase] }
      venues = Array(site.data.dig("venue_images", "venues"))
      items = []
      rows.each do |row|
        item = light_item(row, names, 0)
        unless item
          Jekyll.logger.error("Birthday venues:", "skipped #{row["name"]}")
          next
        end
        photo = market_photo(row["photo"], item["name"], site) ||
                birthday_venue_photo(venues, row, site) ||
                birthday_designed_photo(item["name"], site)
        unless photo
          Jekyll.logger.error("Birthday venues:", "no usable photo for #{item["name"]}")
          next
        end
        apply_photo!(item, photo)
        birthday_labels!(item, row)
        items << item
      end
      # No numbers on this page: plain pins, and each card keeps an id
      # so a pin click still scrolls to its card.
      items.each do |item|
        item.delete("number")
        item["card_id"] = "light-#{item["id"]}"
      end
      packed = pack_towns(items)
      packed["pins"] = items.filter_map do |item|
        next if item["lat"].nil? || item["lng"].nil?

        { "lat" => item["lat"], "lng" => item["lng"], "name" => item["name"], "id" => item["id"] }
      end
      Jekyll.logger.info("Birthday venues:", "#{items.size} venues, #{packed["pins"].size} with coordinates")
      drive = collect_birthday_drive(site)
      unless drive.empty?
        packed["towns"] << {
          "id" => "worth-the-drive", "name" => "Worth the drive", "lights" => drive,
          "intro" => "Just outside the Eastside, but a favorite drive for big parties."
        }
        packed["count"] += drive.size
      end
      mobile = collect_birthday_mobile(site)
      unless mobile.empty?
        packed["towns"] << { "id" => "comes-to-you", "name" => "Parties that come to you", "lights" => mobile }
        packed["count"] += mobile.size
      end
      packed["filters"] = birthday_filters(items + drive + mobile)
      birthday_rows!(packed)
      packed
    end

    # Parties that come to you: _data/birthday_mobile.yml. Same card, no
    # address and no pin. The service area is the card's place line.
    def collect_birthday_mobile(site)
      rows = Array(site.data["birthday_mobile"]).select { |row| row.is_a?(Hash) }
      rows = rows.sort_by { |row| row["name"].to_s.downcase }
      rows.filter_map do |row|
        name = row["name"].to_s.strip
        source = row["source"].to_s.strip
        description = row["description"].to_s.gsub(/\s+/, " ").strip
        if name.empty? || description.empty? || !source.match?(%r{\Ahttps://\S+\z})
          Jekyll.logger.error("Birthday venues:", "skipped #{name}")
          next
        end
        item = {
          "id" => slug(row["id"], name),
          "card_id" => "light-#{slug(row["id"], name)}",
          "name" => name,
          "nights" => row["service_area"].to_s.strip.then { |text| text.empty? ? "Serves the Eastside" : text },
          "blurb" => description,
          "source_href" => source,
          "source_label" => row["source_label"].to_s.strip
        }
        photo = market_photo(row["photo"], name, site) || birthday_designed_photo(name, site)
        apply_photo!(item, photo)
        birthday_labels!(item, row.merge("setting" => "Comes to you"))
        item
      end
    end

    BIRTHDAY_PRICE_GROUPS = {
      "$" => ["1", "$ · Free or under $150"], "$$" => ["2", "$$ · $150 to $299"],
      "$$$" => ["3", "$$$ · $300 to $499"], "$$$$" => ["4", "$$$$ · $500 and up"]
    }.freeze

    # The page is a camp-style list: one compact row per venue, grouped by
    # town, with the summer camps Group by pills (Town, Type, Price). A
    # sponsored venue is the camp-sponsored row with its photo and blurb,
    # pinned at the top of its town and its type.
    def birthday_rows!(packed)
      all = packed["towns"].flat_map { |town| town["lights"] }
      kinds = all.map { |item| Array(item["filter_types"]).first.to_s }.reject(&:empty?).tally
      kind_order = kinds.sort_by { |label, count| [-count, label] }.map(&:first)
      packed["towns"].each_with_index do |town, index|
        town["order"] = index + 1
        town["rows"] = []
        town["sponsored"] = []
        town["lights"].each do |item|
          kind = Array(item["filter_types"]).first.to_s
          kind = "Other" if kind.empty?
          price_group, price_label = BIRTHDAY_PRICE_GROUPS[item["price"].to_s] || ["9", "No price posted"]
          place = item["place_city"].to_s
          place = item["city"].to_s if place.empty?
          place = item["nights"].to_s if place.empty?
          meta = [Array(item["filter_types"]).join(", ")]
          meta << "Toddlers" if item["filter_toddlers"]
          meta.concat(Array(item["meta_extra"]))
          meta << place
          meta << item["price"].to_s
          meta << item["when_text"].to_s
          data = [
            %(data-town="#{CGI.escapeHTML(town["id"].to_s)}"),
            %(data-town-name="#{CGI.escapeHTML(town["name"].to_s)}"),
            %(data-town-order="#{index + 1}"),
            %(data-kind="#{slug(nil, kind)}"),
            %(data-kind-label="#{CGI.escapeHTML(kind)}"),
            %(data-kind-order="#{(kind_order.index(kind) || 98) + 1}"),
            %(data-price="#{price_group}"),
            %(data-price-label="#{CGI.escapeHTML(price_label)}"),
            %(data-price-order="#{price_group}"),
            %(data-sort="#{CGI.escapeHTML(item["name"].to_s.downcase)}"),
            item["lat"] && item["lng"] ? %(data-lat="#{item["lat"]}" data-lng="#{item["lng"]}") : "",
            item["attrs"].to_s
          ].reject(&:empty?).join(" ")
          address = item["address"].to_s
          address = item["place"].to_s if address.empty?
          row = {
            "dom_id" => "light-#{item["id"]}", "id" => item["id"], "name" => item["name"],
            "url" => (item["source_href"] || item["source"]).to_s, "meta" => meta.reject(&:empty?).join(" · "),
            "address" => address, "place_city" => place, "data" => data
          }
          if item["sponsored"]
            row.merge!(
              "blurb" => (item["blurb"] || item["description"]).to_s, "image" => item["image"],
              "alt" => item["image_alt"], "credit" => item["image_credit"], "image_source" => item["image_source"]
            )
            town["sponsored"] << row
          else
            town["rows"] << row
          end
        end
        town["count"] = town["rows"].size + town["sponsored"].size
      end
    end

    # Worth the drive: _data/birthday_drive.yml. Big venues just outside
    # the 15 cities. Same card. The city is the card's first line and the
    # address links to maps. No pins, so the map stays on the Eastside.
    def collect_birthday_drive(site)
      rows = Array(site.data["birthday_drive"]).select { |row| row.is_a?(Hash) }
      rows = rows.sort_by { |row| [row["place_city"].to_s.downcase, row["name"].to_s.downcase] }
      rows.filter_map do |row|
        name = row["name"].to_s.strip
        city = row["place_city"].to_s.strip
        address = row["address"].to_s.gsub(/\s+/, " ").strip
        source = row["source"].to_s.strip
        description = row["description"].to_s.gsub(/\s+/, " ").strip
        if name.empty? || city.empty? || address.empty? || description.empty? || !source.match?(%r{\Ahttps://\S+\z})
          Jekyll.logger.error("Birthday venues:", "skipped #{name}")
          next
        end
        id = slug(row["id"], name)
        item = {
          "id" => id, "card_id" => "light-#{id}", "name" => name, "nights" => city,
          "place" => address, "place_city" => city, "blurb" => description,
          "lat" => coordinate(row["lat"]), "lng" => coordinate(row["lng"]),
          "source_href" => source, "source_label" => row["source_label"].to_s.strip
        }
        photo = market_photo(row["photo"], name, site) || birthday_designed_photo(name, site)
        apply_photo!(item, photo)
        birthday_labels!(item, row)
        item
      end
    end

    # The designed party card, used when there is no photo of the venue.
    BIRTHDAY_DESIGNED = "/assets/images/birthdays/party-card.webp"

    def birthday_designed_photo(_name, site)
      return nil unless File.file?(File.join(site.source, BIRTHDAY_DESIGNED.sub(%r{\A/}, "")))

      { "src" => BIRTHDAY_DESIGNED, "alt" => "Illustration of three party balloons and confetti.", "credit" => "", "source" => "", "kind" => "designed" }
    end

    def birthday_labels!(item, row)
      setting = row["setting"].to_s.strip
      setting = "" unless ["Indoor", "Outdoor", "Comes to you"].include?(setting)
      types = Array(row["types"]).map { |value| value.to_s.strip }.reject(&:empty?)
      labels = []
      labels << setting unless setting.empty?
      labels << "Toddlers" if row["toddlers"] == true
      labels.concat(types)
      labels << "Party room" if row["party_room"] == true
      bits = []
      bits << %(data-setting="#{CGI.escapeHTML(setting)}") unless setting.empty?
      bits << 'data-ages="Toddlers"' if row["toddlers"] == true
      bits << %(data-type="#{CGI.escapeHTML(types.join("|"))}") unless types.empty?
      bits << 'data-room="1"' if row["party_room"] == true
      level = BIRTHDAY_LEVELS[row["price_level"].to_i].to_s
      item["label_ready"] = true
      item["price"] = level
      item["ages_text"] = ""
      item["labels"] = labels
      item["attrs"] = bits.join(" ")
      item["filter_setting"] = setting
      item["filter_types"] = types
      item["filter_toddlers"] = row["toddlers"] == true
      item["sponsored"] = row["sponsored"] == true
      item["filter_room"] = row["party_room"] == true
    end

    # Chips come from the data: a chip shows when at least one card has it.
    def birthday_filters(items)
      chips = []
      ["Indoor", "Outdoor", "Comes to you"].each do |setting|
        chips << { "label" => setting, "group" => "setting", "value" => setting } if items.any? { |item| item["filter_setting"] == setting }
      end
      chips << { "label" => "Toddlers", "group" => "ages", "value" => "Toddlers" } if items.any? { |item| item["filter_toddlers"] }
      types = items.flat_map { |item| item["filter_types"] }.tally
      types.sort_by { |label, count| [-count, label] }.each do |label, _count|
        chips << { "label" => label, "group" => "type", "value" => label }
      end
      chips << { "label" => "Party room", "group" => "room", "value" => "1" } if items.any? { |item| item["filter_room"] }
      chips
    end

    def birthday_venue_photo(venues, row, site)
      wanted = row["photo_key"].to_s.downcase.strip
      best = nil
      best_len = 0
      venues.each do |venue|
        next unless venue.is_a?(Hash)

        Array(venue["keys"]).each do |key|
          key = key.to_s.downcase
          next if key.empty?
          next unless key == wanted
          next unless key.length > best_len

          best = venue
          best_len = key.length
        end
      end
      return nil unless best

      photo = {
        "image" => best["image"], "alt" => best["alt"],
        "credit" => best["credit"], "credit_url" => best["source"]
      }
      built = market_photo(photo, row["name"], site)
      built["kind"] = "venue" if built
      built
    end

    # Directory pages in the birthday list style with no price: /indoor-play/
    # from _data/indoor_play.yml. A row with birthday_id reuses name, city,
    # address, lat, and lng from that birthday venue. Chips are Toddlers,
    # Free, Drop-in, then the types. The when line joins the meta line.
    def collect_directory(site, data_key, log_label)
      names = city_names(site.data["cities"])
      parties = Array(site.data["birthday_venues"]).select { |row| row.is_a?(Hash) }.to_h { |row| [row["id"].to_s, row] }
      rows = Array(site.data[data_key]).select { |row| row.is_a?(Hash) }.map do |row|
        base = parties[row["birthday_id"].to_s]
        next row unless base

        merged = row.dup
        %w[name city address lat lng].each { |key| merged[key] = base[key] if merged[key].to_s.strip.empty? }
        merged
      end
      rows = rows.sort_by { |row| [names[row["city"].to_s].to_s.downcase, row["name"].to_s.downcase] }
      items = rows.filter_map do |row|
        item = light_item(row, names, 0)
        unless item
          Jekyll.logger.error(log_label, "skipped #{row["name"] || row["id"]}")
          next
        end
        item.delete("number")
        item["card_id"] = "light-#{item["id"]}"
        directory_labels!(item, row)
        item
      end
      packed = pack_towns(items)
      packed["pins"] = []
      packed["filters"] = directory_filters(items)
      packed["no_price"] = true
      birthday_rows!(packed)
      Jekyll.logger.info(log_label, "#{items.size} places, #{items.count { |item| item["lat"] }} with coordinates")
      packed
    end

    def directory_labels!(item, row)
      types = Array(row["types"]).map { |value| value.to_s.strip }.reject(&:empty?)
      flags = []
      flags << "Toddlers" if row["toddlers"] == true
      flags << "Free" if row["free"] == true
      flags << "Drop-in" if row["drop_in"] == true
      bits = []
      bits << %(data-type="#{CGI.escapeHTML(types.join("|"))}") unless types.empty?
      bits << 'data-ages="Toddlers"' if row["toddlers"] == true
      bits << 'data-cost="Free"' if row["free"] == true
      bits << 'data-drop="Drop-in"' if row["drop_in"] == true
      item["label_ready"] = true
      item["price"] = ""
      item["ages_text"] = ""
      item["labels"] = types + flags
      item["attrs"] = bits.join(" ")
      item["filter_types"] = types
      item["filter_flags"] = flags
      item["filter_toddlers"] = false
      item["meta_extra"] = flags
      item["when_text"] = row["when"].to_s.gsub(/\s+/, " ").strip
      item["sponsored"] = row["sponsored"] == true
    end

    def directory_filters(items)
      chips = []
      [["Toddlers", "ages"], ["Free", "cost"], ["Drop-in", "drop"]].each do |label, group|
        chips << { "label" => label, "group" => group, "value" => label } if items.any? { |item| Array(item["filter_flags"]).include?(label) }
      end
      items.flat_map { |item| item["filter_types"] }.tally.sort_by { |label, count| [-count, label] }.each do |label, _count|
        chips << { "label" => label, "group" => "type", "value" => label }
      end
      chips
    end

    # Book-ahead rows leave the page when the last day has passed or the
    # organizer marks the event sold out. The daily prune deletes those rows.
    def collect_book_ahead(site)
      today = EventCalendar.pacific_today(site.time)
      names = city_names(site.data["cities"])
      rows = Array(site.data["book_ahead"]).select { |row| row.is_a?(Hash) }
      items = []
      rows.each do |row|
        item = book_item(row, names, today, site)
        items << item if item
      end
      items.sort_by! { |item| [item["sort_on"].to_s, item["name"].to_s.downcase] }
      items.each { |item| item.delete("sort_on") }
      Jekyll.logger.info("Book ahead:", "#{items.size} events")
      items
    end

    def book_item(row, names, today, site)
      return nil if sold_out?(row)

      start_on = book_date(row["start"])
      end_on = book_date(row["end"]) || start_on
      return nil unless start_on
      return nil if end_on < today

      city_id = row["city"].to_s.strip
      city_name = names[city_id].to_s
      name = squash(row["name"])
      if city_name.empty?
        Jekyll.logger.error("Book ahead:", "unknown city for #{name}")
        return nil
      end

      address = squash(row["address"])
      description = squash(row["description"])
      when_text = squash(row["when"])
      source = row["source"].to_s.strip
      if name.empty? || address.empty? || description.empty? || when_text.empty?
        Jekyll.logger.error("Book ahead:", "incomplete row #{name}")
        return nil
      end
      unless source.match?(%r{\Ahttps://\S+\z})
        Jekyll.logger.error("Book ahead:", "no ticket link for #{name}")
        return nil
      end

      photo = market_photo(row["photo"], name, site)
      unless photo
        Jekyll.logger.error("Book ahead:", "no usable photo for #{name}")
        return nil
      end

      label = squash(row["source_label"])
      label = "Tickets" if label.empty?
      joiner = when_text.end_with?(".") ? " " : ". "
      item = {
        "id" => slug(row["id"], name),
        "name" => name,
        "city" => city_name,
        "city_id" => city_id,
        "address" => address,
        "description" => description,
        "nights" => "#{when_text}#{joiner}#{ticket_status(row, today)}",
        "source" => source,
        "source_label" => label,
        "start" => start_on.iso8601,
        "end" => end_on.iso8601,
        "sort_on" => start_on.iso8601
      }
      apply_photo!(item, photo)
      item
    end

    def ticket_status(row, today)
      line = squash(row["ticket_line"])
      return line unless line.empty?

      on_sale = book_date(row["tickets_on"])
      if on_sale && today < on_sale
        return "Tickets go on sale #{on_sale.strftime("%b %-d")}."
      end

      "Tickets are on sale now."
    end

    def sold_out?(row)
      value = row["sold_out"]
      value == true || value.to_s.strip.casecmp("true").zero?
    end

    def book_date(value)
      return value if value.is_a?(Date)
      return Date.new(value.year, value.month, value.day) if value.is_a?(Time) || value.is_a?(DateTime)

      text = value.to_s.strip
      return nil if text.empty?

      Date.iso8601(text[0, 10])
    rescue ArgumentError, TypeError
      nil
    end

    def pack_towns(items)
      towns = []
      items.each do |item|
        town = towns.last
        if town.nil? || town["id"] != item["city_id"]
          town = { "id" => item["city_id"], "name" => item["city"], "lights" => [] }
          towns << town
        end
        town["lights"] << item
      end
      pins = items.filter_map do |item|
        next if item["lat"].nil? || item["lng"].nil? || item["number"].nil?

        {
          "n" => item["number"],
          "lat" => item["lat"],
          "lng" => item["lng"],
          "name" => item["name"],
          "id" => item["id"]
        }
      end
      { "towns" => towns, "pins" => pins, "count" => items.size }
    end

    # Place map pins on the hand-drawn Eastside map. City centers in
    # cities.yml and the city dots in eastside-map.html fix the fit.
    def feature_map_pins(site)
      x_coeff, y_coeff = map_fit(site)
      return { "halloween" => [], "christmas" => [], "playgrounds" => [] } if x_coeff.nil?

      {
        "halloween" => project_pins(site.data.dig("halloween_map", "pins"), x_coeff, y_coeff),
        "christmas" => project_pins(site.data.dig("home_lights", "pins"), x_coeff, y_coeff),
        "playgrounds" => project_pins(playground_pins(site), x_coeff, y_coeff)
      }
    end

    def map_fit(site)
      samples = map_samples(site)
      return [nil, nil] if samples.size < 3

      [solve_axis(samples, :x), solve_axis(samples, :y)]
    end

    def map_samples(site)
      centers = {}
      Array(site.data["cities"]).each do |city|
        next unless city.is_a?(Hash)

        lat = coordinate(city["lat"])
        lon = coordinate(city["lon"])
        next if lat.nil? || lon.nil?

        centers[city["id"].to_s] = [lon, lat]
      end
      path = File.join(site.source, "_includes", "eastside-map.html")
      html = File.read(path)
      samples = []
      html.scan(%r{href="\{\{ '/([^']+)/' \| relative_url \}\}">\s*<circle class="city-hit" cx="([^"]+)" cy="([^"]+)"}) do |id, x, y|
        center = centers[id]
        next unless center

        samples << [center[0], center[1], Float(x), Float(y)]
      end
      samples
    end

    def playground_pins(site)
      groups = site.data.dig("guides", "playgrounds", "groups")
      Array(groups).flat_map do |group|
        next [] unless group.is_a?(Hash)

        Array(group["entries"]).filter_map do |entry|
          next unless entry.is_a?(Hash)

          {
            "name" => entry["name"].to_s,
            "lat" => entry["lat"],
            "lng" => entry["lng"]
          }
        end
      end
    end

    def project_pins(pins, x_coeff, y_coeff)
      Array(pins).filter_map do |pin|
        lat = coordinate(pin["lat"])
        lng = coordinate(pin["lng"])
        next if lat.nil? || lng.nil?

        {
          "name" => pin["name"].to_s,
          "x" => format("%.1f", (x_coeff[0] * lng) + (x_coeff[1] * lat) + x_coeff[2]),
          "y" => format("%.1f", (y_coeff[0] * lng) + (y_coeff[1] * lat) + y_coeff[2])
        }
      end
    end

    def solve_axis(samples, axis)
      ata = Array.new(3) { Array.new(3, 0.0) }
      atb = Array.new(3, 0.0)
      samples.each do |lon, lat, x, y|
        row = [lon, lat, 1.0]
        target = axis == :x ? x : y
        3.times do |i|
          atb[i] += row[i] * target
          3.times { |j| ata[i][j] += row[i] * row[j] }
        end
      end
      solve3(ata, atb)
    end

    def solve3(matrix, vector)
      coeff = matrix.map(&:dup)
      values = vector.dup
      3.times do |col|
        pivot = (col...3).max_by { |row| coeff[row][col].abs }
        coeff[col], coeff[pivot] = coeff[pivot], coeff[col]
        values[col], values[pivot] = values[pivot], values[col]
        scale = coeff[col][col]
        return [0.0, 0.0, 0.0] if scale.abs < 1e-9

        ((col + 1)...3).each do |row|
          factor = coeff[row][col] / scale
          3.times { |k| coeff[row][k] -= factor * coeff[col][k] }
          values[row] -= factor * values[col]
        end
      end
      solved = Array.new(3, 0.0)
      2.downto(0) do |row|
        sum = values[row]
        ((row + 1)...3).each { |k| sum -= coeff[row][k] * solved[k] }
        solved[row] = sum / coeff[row][row]
      end
      solved
    end
  end
end
