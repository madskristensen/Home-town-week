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
      {
        "towns" => towns,
        "pins" => pins,
        "count" => items.size
      }
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
      return nil if kids_photo?(photo["alt"], image)

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
      number = 0
      items.each do |item|
        if item["lat"].nil? || item["lng"].nil?
          item.delete("number")
        else
          number += 1
          item["number"] = number
        end
      end
      Jekyll.logger.info("Farmers markets:", "#{items.size} markets, #{number} on the map")
      pack_towns(items)
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

    def market_status(row, today)
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
