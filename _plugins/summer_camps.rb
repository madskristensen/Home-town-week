# frozen_string_literal: true

require "date"

module EastsideCalendar
  # /summer-camps/ is a day-camp directory, not an event hub.
  # Sign-up status is computed at build from America/Los_Angeles today.
  module SummerCamps
    AGES = [
      ["preschool", "Preschool 3-5"],
      ["kids", "Kids 6-10"],
      ["tweens", "Tweens 11-13"],
      ["teens", "Teens 14+"]
    ].freeze
    TYPES = [
      ["parks", "Parks"],
      ["sports", "Sports"],
      ["stem", "STEM"],
      ["arts", "Arts"],
      ["outdoor", "Nature/outdoor"],
      ["general", "General day camp"]
    ].freeze
    EXTRAS = {
      "newcastle" => "Newcastle",
      "preston" => "Preston"
    }.freeze
    BANNED = %w[parentmap.com seattleschild.com macaronikid.com].freeze

    module_function

    def prepare(site)
      today = EventCalendar.pacific_today(site.time)
      names = city_names(site.data["cities"])
      rows = Array(site.data["summer_camps"]).select { |row| row.is_a?(Hash) }
      camps = []
      rows.each do |row|
        camp = build(row, names, today, site)
        camps << camp if camp
      end
      featured = camps.select { |camp| camp["featured"] }.sort_by { |camp| [camp["feature_rank"], camp["name"].downcase] }
      directory = camps.select { |camp| camp["in_directory"] }
      towns = group_towns(directory, names)
      signups = camps.select { |camp| camp["on_signup_list"] }.sort_by { |camp| [camp["signup_sort"], camp["name"].downcase] }
      confirmed = camps.count { |camp| camp["confirmed_2027"] }
      Jekyll.logger.info("Summer camps:", "#{directory.size} in the directory, #{confirmed} with 2027 info, #{featured.size} start-here cards")
      {
        "camps" => camps,
        "featured" => featured,
        "towns" => towns,
        "type_groups" => group_types(directory),
        "signups" => signups,
        "ages" => chips(AGES, directory) { |camp, key| Array(camp["age_groups"]).include?(key) },
        "types" => chips(TYPES, directory) { |camp, key| camp["type"] == key },
        "full_day_count" => directory.count { |camp| camp["full_day"] },
        "confirmed" => confirmed
      }
    end

    def chips(pairs, camps)
      pairs.filter_map do |key, label|
        count = camps.count { |camp| yield(camp, key) }
        next if count.zero?

        { "id" => key, "label" => label, "count" => count }
      end
    end

    def group_towns(camps, names)
      order = names.keys + EXTRAS.keys
      groups = camps.group_by { |camp| camp["town_id"] }
      order.filter_map do |town|
        rows = groups[town]
        next if rows.nil? || rows.empty?

        rows = rows.sort_by { |camp| camp["group_sort"] }
        {
          "id" => town,
          "name" => rows.first["town_name"],
          "count" => rows.size,
          "camps" => rows
        }
      end
    end

    def build(row, names, today, site)
      name = squash(row["name"])
      id = squash(row["id"])
      town = squash(row["town"])
      source = row["source"].to_s.strip
      if name.empty? || id.empty? || town.empty?
        Jekyll.logger.error("Summer camps:", "incomplete row #{name}")
        return nil
      end
      unless source.match?(%r{\Ahttps://\S+\z})
        Jekyll.logger.error("Summer camps:", "no https source for #{name}")
        return nil
      end
      host = source.sub(%r{\Ahttps://(?:www\.)?}i, "").split("/").first.to_s.downcase
      if BANNED.any? { |banned| host.end_with?(banned) }
        Jekyll.logger.error("Summer camps:", "banned source for #{name}")
        return nil
      end
      town_name = names[town] || EXTRAS[town] || squash(row["town_name"])
      if town_name.empty?
        Jekyll.logger.error("Summer camps:", "unknown town #{town} for #{name}")
        return nil
      end
      ages = Array(row["age_groups"]).map { |value| value.to_s.strip }.reject(&:empty?)
      unknown = ages.reject { |key| AGES.any? { |pair| pair[0] == key } }
      unless unknown.empty?
        Jekyll.logger.error("Summer camps:", "bad ages #{unknown.join(", ")} on #{name}")
        return nil
      end
      type = squash(row["type"])
      type_label = TYPES.assoc(type)&.last
      if type_label.nil?
        Jekyll.logger.error("Summer camps:", "bad type #{type} on #{name}")
        return nil
      end
      text = [name, row["blurb"], row["hint"], row["signup"], row["weeks"], row["price"], row["location"]].join(" ")
      if text.include?("\u2014")
        Jekyll.logger.error("Summer camps:", "em dash in #{name}")
        return nil
      end

      status = status_for(row, today)
      signup = signup_line(row, status)
      featured = row["featured"] == true
      photo = featured ? photo_for(row["photo"], name, site) : nil
      return nil if featured && photo.nil?

      camp = {
        "id" => id,
        "name" => name,
        "town_id" => town,
        "town" => town_name,
        "town_name" => town_name,
        "city_id" => names.key?(town) ? town : "",
        "type" => type,
        "type_label" => type_label,
        "age_groups" => ages,
        "full_day" => row["full_day"] == true,
        "meta" => join_bits(row["age_label"], row["day_label"]),
        "detail" => join_bits(type_label, row["location"], row["weeks"], row["price"]),
        "signup" => signup,
        "source" => source,
        "source_label" => presence(row["source_label"], "Camp site"),
        "featured" => featured,
        "feature_rank" => row["feature_rank"].to_i,
        "in_directory" => row["in_directory"] != false,
        "on_signup_list" => row["on_signup_list"] == true,
        "confirmed_2027" => row["confirmed_2027"] == true,
        "signup_sort" => signup_sort(row, today),
        "group_sort" => group_sort(row, today),
        "audiences" => audiences(row, today),
        "blurb" => squash(row["blurb"]),
        "card_when" => card_when(row, status)
      }
      if photo
        camp["image"] = photo["image"]
        camp["image_alt"] = photo["alt"]
        camp["image_credit"] = photo["credit"]
        camp["image_source"] = photo["source"]
        camp["href"] = source
        camp["external"] = true
        camp["title"] = name
        camp["when"] = camp["card_when"]
        camp["place"] = squash(row["card_place"])
        camp["city"] = town_name
        camp["place_city"] = town_name
      end
      camp
    end

    def photo_for(photo, name, site)
      return missing_photo(name) unless photo.is_a?(Hash)

      image = photo["image"].to_s.strip
      alt = squash(photo["alt"])
      credit = squash(photo["credit"])
      source = photo["source"].to_s.strip
      if image.empty? || alt.empty? || credit.empty? || !source.match?(%r{\Ahttps://\S+\z})
        return missing_photo(name)
      end
      if alt.include?("\u2014") || credit.include?("\u2014")
        Jekyll.logger.error("Summer camps:", "em dash in the photo for #{name}")
        return nil
      end
      path = File.join(site.source, image.sub(%r{\A/}, ""))
      unless File.file?(path)
        Jekyll.logger.error("Summer camps:", "missing photo file for #{name}")
        return nil
      end
      { "image" => image, "alt" => alt, "credit" => credit, "source" => source }
    end

    def missing_photo(name)
      Jekyll.logger.error("Summer camps:", "no usable photo for #{name}")
      nil
    end

    def date_status(date, open_flag, today = nil)
      return "Open now" if open_flag && date.nil?
      return "Not posted yet" unless date.is_a?(Date)

      day = today || Date.today
      days = (date - day).to_i
      return "Open now" if days <= 0
      return "Opens in 1 day" if days == 1

      "Opens in #{days} days"
    end

    def status_for(row, today)
      return "Open now" if row["signup_open"] == true

      date_status(camp_date(row["reg_on"]), false, today)
    end

    def audiences(row, today)
      lines = Array(row["audiences"]).select { |line| line.is_a?(Hash) }
      return [] if lines.empty?

      lines.map do |line|
        {
          "who" => squash(line["who"]),
          "status" => date_status(camp_date(line["reg_on"]), line["open"] == true, today),
          "hint" => squash(line["hint"])
        }
      end
    end

    def signup_line(row, status)
      custom = squash(row["signup"])
      line = custom.empty? ? default_signup(row) : custom
      line.gsub("{{status}}", status)
    end

    def default_signup(row)
      hint = squash(row["hint"])
      base = "2027 dates not posted yet."
      hint.empty? ? base : "#{base} #{hint}"
    end

    def card_when(row, status)
      custom = squash(row["card_when"])
      return custom.gsub("{{status}}", status) unless custom.empty?
      return "Open now" if row["signup_open"] == true
      return status if camp_date(row["reg_on"])

      "2027 dates not posted yet"
    end

    def group_types(camps)
      groups = camps.group_by { |camp| camp["type"] }
      TYPES.filter_map do |key, label|
        rows = groups[key]
        next if rows.nil? || rows.empty?

        {
          "id" => key,
          "name" => label,
          "count" => rows.size,
          "camps" => rows.sort_by { |camp| camp["group_sort"] }
        }
      end
    end

    # Soonest sign-up first, then name. Open now is first. A future
    # registration date is next. Not posted yet is last, by name.
    def group_sort(row, today)
      name = squash(row["name"]).downcase
      return "0-#{name}" if row["signup_open"] == true

      dates = [camp_date(row["reg_on"])]
      Array(row["audiences"]).each do |line|
        dates << camp_date(line["reg_on"]) if line.is_a?(Hash)
      end
      dates.compact!
      return "2-#{name}" if dates.empty?
      return "0-#{name}" if dates.any? { |date| date <= today }

      "1-#{dates.min.iso8601}-#{name}"
    end

    def signup_sort(row, today)
      if row["signup_open"] == true
        return "0-#{squash(row["name"]).downcase}"
      end
      dates = [camp_date(row["reg_on"])]
      dates.concat(Array(row["audiences"]).map { |line| line.is_a?(Hash) ? camp_date(line["reg_on"]) : nil })
      dates.compact!
      future = dates.select { |date| date > today }.min
      return "1-#{future.iso8601}" if future

      past = dates.select { |date| date <= today }.max
      return "0-#{past.iso8601}" if past

      ref = camp_date(row["ref_sort"]) || Date.new(2099, 12, 31)
      "2-#{ref.iso8601}"
    end

    def camp_date(value)
      Date.iso8601(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def city_names(cities)
      names = {}
      Array(cities).each do |city|
        next unless city.is_a?(Hash)

        id = city["id"].to_s
        name = city["name"].to_s.strip
        names[id] = name unless id.empty? || name.empty?
      end
      names
    end

    def join_bits(*parts)
      parts.map { |part| squash(part) }.reject(&:empty?).join(" · ")
    end

    def squash(value)
      value.to_s.gsub(/\s+/, " ").strip
    end

    def presence(value, fallback)
      text = squash(value)
      text.empty? ? fallback : text
    end
  end

  class SummerCampsGenerator < Jekyll::Generator
    priority :low

    def generate(site)
      page_data = SummerCamps.prepare(site)
      site.data["summer_camps_page"] = page_data
      places = page_data["camps"].map do |camp|
        { "name" => camp["name"], "href" => camp["source"] }
      end
      site.pages.each do |page|
        next unless page.data["camps"]

        page.data["places"] = places
      end
    end
  end
end
