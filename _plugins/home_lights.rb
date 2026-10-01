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
      names = {}
      Array(cities).each do |city|
        next unless city.is_a?(Hash)

        names[city["id"].to_s] = city["name"].to_s.strip
      end
      names
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
  end
end
