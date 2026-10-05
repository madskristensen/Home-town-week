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

    # The coming summer. After August, camps are posting next year's dates.
    def season_year(today)
      today.month >= 9 ? today.year + 1 : today.year
    end

    def prepare(site)
      today = EventCalendar.pacific_today(site.time)
      year = season_year(today)
      names = city_names(site.data["cities"])
      sanitize_sponsors(site, names)
      rows = Array(site.data["summer_camps"]).select { |row| row.is_a?(Hash) }
      camps = []
      rows.each do |row|
        camp = build(row, names, today, year, site)
        camps << camp if camp
      end
      directory = camps.select { |camp| camp["in_directory"] }
      towns = group_towns(directory, names)
      confirmed = camps.count { |camp| camp["confirmed_#{year}"] }
      towns.each_with_index do |town, index|
        town["camps"].each { |camp| camp["town_order"] = index }
      end
      Jekyll.logger.info("Summer camps:", "#{directory.size} in the directory, #{confirmed} with #{year} info")
      {
        "camps" => camps,
        "towns" => towns,
        "confirmed" => confirmed
      }
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

    def build(row, names, today, year, site)
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
      bucket = signup_bucket(row, today)
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
        "type_order" => TYPES.index { |pair| pair[0] == type } || 9,
        "age_groups" => ages,
        "full_day" => row["full_day"] == true,
        "meta" => skim_meta(row, town_name),
        "signup" => skim_signup(row, today, year),
        "source" => source,
        "source_label" => presence(row["source_label"], "Camp site"),
        "featured" => featured,
        "feature_rank" => row["feature_rank"].to_i,
        "in_directory" => row["in_directory"] != false,
        "on_signup_list" => row["on_signup_list"] == true,
        "confirmed_#{year}" => row["confirmed_#{year}"] == true,
        "signup_sort" => signup_sort(row, today),
        "group_sort" => "#{bucket["order"]}-#{name.downcase}",
        "signup_group" => bucket["id"],
        "signup_label" => bucket["label"],
        "signup_order" => bucket["order"],
        "audiences" => audiences(row, today),
        "blurb" => squash(row["blurb"]),
        "card_when" => card_when(row, status, year)
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

    # Three short facts. Ages are omitted when the page did not list them.
    # Day length is Full day or Half or full day. The town is always there.
    def skim_meta(row, town_name)
      join_bits(known_age(row), short_day(row), town_name)
    end

    def known_age(row)
      label = squash(row["age_label"])
      return nil if label.empty?
      return nil if label.match?(/\Aages (on the|vary)\b/i)

      label
    end

    def short_day(row)
      label = squash(row["day_label"]).downcase
      half = label.include?("half")
      full = row["full_day"] == true || label.include?("full day")
      return "Half or full day" if half && full
      return "Full day" if full

      nil
    end

    # Open now, Sign-up opens Jan 19, or a one-line not-posted note.
    def skim_signup(row, today, year)
      return "Open now" if row["signup_open"] == true

      dates = [camp_date(row["reg_on"])]
      Array(row["audiences"]).each do |line|
        dates << camp_date(line["reg_on"]) if line.is_a?(Hash)
      end
      dates.compact!
      return "Open now" if dates.any? { |date| date <= today }

      future = dates.select { |date| date > today }.min
      if future
        return "Sign-up opens #{Date::ABBR_MONTHNAMES[future.month]} #{future.day}"
      end

      hint = past_signup_phrase(row, year - 1)
      hint ? "#{year} dates not posted yet (#{hint})" : "#{year} dates not posted yet"
    end

    def past_signup_phrase(row, fallback_year)
      hint = squash(row["hint"])
      return nil unless hint.match?(/regist/i)

      match = hint.match(/registered(?:\s+on)?\s+(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2})\b/i)
      return nil unless match

      day = match[2].to_i
      span = day <= 10 ? "early" : day <= 20 ? "mid-" : "late"
      gap = span.end_with?("-") ? "" : " "
      year = hint[/\b(20\d{2})\b/, 1] || fallback_year.to_s
      "#{span}#{gap}#{match[1]} #{year}"
    end

    def card_when(row, status, year)
      custom = squash(row["card_when"])
      return custom.gsub("{{status}}", status) unless custom.empty?
      return "Open now" if row["signup_open"] == true
      return status if camp_date(row["reg_on"])

      "#{year} dates not posted yet"
    end

    # Open now, then a future registration date, then not posted yet.
    def signup_bucket(row, today)
      if row["signup_open"] == true
        return { "id" => "open", "label" => "Open now", "order" => "0" }
      end

      dates = [camp_date(row["reg_on"])]
      Array(row["audiences"]).each do |line|
        dates << camp_date(line["reg_on"]) if line.is_a?(Hash)
      end
      dates.compact!
      return { "id" => "later", "label" => "Not posted yet", "order" => "2" } if dates.empty?
      return { "id" => "open", "label" => "Open now", "order" => "0" } if dates.any? { |date| date <= today }

      date = dates.min
      {
        "id" => "date-#{date.iso8601}",
        "label" => "#{Date::MONTHNAMES[date.month]} #{date.day}, #{date.year}",
        "order" => "1-#{date.iso8601}"
      }
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

    def sanitize_sponsors(site, names)
      raw = site.data["sponsors"]
      return unless raw.is_a?(Hash)

      seasons = raw["seasons"].is_a?(Hash) ? raw["seasons"] : {}
      seasons.each do |key, season|
        next unless season.is_a?(Hash)

        clean_sponsor_line(season, "season #{key}")
        season["cards"] = Array(season["cards"]).filter_map { |card| clean_sponsor_card(card, "season #{key}") }
      end
      raw["seasons"] = seasons

      cards = raw["cards"].is_a?(Hash) ? raw["cards"] : {}
      cards["weekend"] = Array(cards["weekend"]).filter_map { |card| clean_sponsor_card(card, "weekend card") }
      cities = cards["cities"].is_a?(Hash) ? cards["cities"] : {}
      cities.each do |city, list|
        cities[city] = Array(list).filter_map { |card| clean_sponsor_card(card, "#{city} card") }
      end
      cards["cities"] = cities
      raw["cards"] = cards

      raw["listings"] = Array(raw["listings"]).filter_map { |row| clean_listing(row, names, site) }

      email = raw["email"].is_a?(Hash) ? raw["email"] : {}
      clean_sponsor_line(email, "email")
      if email["line"].to_s.include?("\u2014")
        Jekyll.logger.error("Sponsors:", "em dash in the email line")
        email["line"] = ""
      else
        email["line"] = squash(email["line"])
      end
      raw["email"] = email
    end

    def clean_sponsor_line(row, label)
      name = squash(row["name"])
      url = row["url"].to_s.strip
      if name.include?("\u2014")
        Jekyll.logger.error("Sponsors:", "em dash in #{label}")
        row["name"] = ""
        return
      end
      if name.empty?
        row["name"] = ""
        return
      end
      unless url.match?(%r{\Ahttps://\S+\z})
        Jekyll.logger.error("Sponsors:", "no https url for #{label}")
        row["name"] = ""
        return
      end
      row["name"] = name
      row["url"] = url
    end

    def clean_sponsor_card(card, label)
      return nil unless card.is_a?(Hash)

      title = squash(card["title"])
      href = card["href"].to_s.strip
      text = [title, card["blurb"], card["when"], card["place"], card["town"], card["alt"], card["credit"]].join(" ")
      if title.empty? || text.include?("\u2014")
        Jekyll.logger.error("Sponsors:", "bad card for #{label}")
        return nil
      end
      unless href.match?(%r{\Ahttps://\S+\z})
        Jekyll.logger.error("Sponsors:", "no https link for #{label}")
        return nil
      end
      card["title"] = title
      card["href"] = href
      card["sponsored"] = true
      card["external"] = true
      card["town"] = "Sponsored" if squash(card["town"]).empty?
      card
    end

    def clean_listing(row, names, site)
      return nil unless row.is_a?(Hash)

      name = squash(row["name"])
      url = row["url"].to_s.strip
      town = squash(row["town"])
      text = [name, row["blurb"], row["meta"], row["alt"], row["credit"]].join(" ")
      if name.empty? || text.include?("\u2014")
        Jekyll.logger.error("Sponsors:", "bad camp listing #{name}")
        return nil
      end
      unless url.match?(%r{\Ahttps://\S+\z})
        Jekyll.logger.error("Sponsors:", "no https url for #{name}")
        return nil
      end
      town_name = names[town] || EXTRAS[town]
      if town_name.nil? || town_name.empty?
        Jekyll.logger.error("Sponsors:", "unknown town #{town} for #{name}")
        return nil
      end

      type = squash(row["type"])
      type_label = ""
      type_order = ""
      unless type.empty?
        found = TYPES.each_with_index.find { |pair, _index| pair[0] == type }
        if found.nil?
          Jekyll.logger.error("Sponsors:", "bad type #{type} on #{name}")
          return nil
        end
        type_label = found[0][1]
        type_order = found[1].to_s
      end

      ages = Array(row["ages"]).map { |value| value.to_s.strip }.reject(&:empty?)
      unknown = ages.reject { |key| AGES.any? { |pair| pair[0] == key } }
      unless unknown.empty?
        Jekyll.logger.error("Sponsors:", "bad ages on #{name}")
        return nil
      end

      photo = listing_photo(row, name, site)
      return nil if photo.nil?

      id = squash(row["id"])
      id = name.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "") if id.empty?
      order = (names.keys + EXTRAS.keys).index(town) || 0
      {
        "id" => id,
        "name" => name,
        "url" => url,
        "town" => town,
        "town_name" => town_name,
        "town_order" => order,
        "type" => type,
        "type_label" => type_label,
        "type_order" => type_order,
        "ages" => ages,
        "meta" => squash(row["meta"]),
        "blurb" => squash(row["blurb"])
      }.merge(photo)
    end

    # A missing image is fine. A broken image drops the whole listing.
    def listing_photo(row, name, site)
      image = squash(row["image"])
      return {} if image.empty?

      alt = squash(row["alt"])
      credit = squash(row["credit"])
      source = row["image_source"].to_s.strip
      path = File.join(site.source, image.sub(%r{\A/}, ""))
      if alt.empty? || credit.empty? || alt.include?("\u2014") || credit.include?("\u2014") ||
         !source.match?(%r{\Ahttps://\S+\z}) || !File.file?(path)
        Jekyll.logger.error("Sponsors:", "bad photo for #{name}")
        return nil
      end

      { "image" => image, "alt" => alt, "credit" => credit, "image_source" => source }
    end

    def city_names(cities)
      TextUtil.city_names(cities)
    end

    def join_bits(*parts)
      parts.map { |part| squash(part) }.reject(&:empty?).join(" · ")
    end

    def squash(value)
      TextUtil.squash(value)
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
      year = SummerCamps.season_year(EventCalendar.pacific_today(site.time))
      site.pages.each do |page|
        sample = page.data["sample_camp"]
        sample["signup"] = "#{year} dates not posted yet" if sample.is_a?(Hash)
      end
      places = page_data["camps"].select { |camp| camp["in_directory"] }.map do |camp|
        { "name" => camp["name"], "href" => camp["source"] }
      end
      site.pages.each do |page|
        next unless page.data["camps"]

        page.data["places"] = places
      end
    end
  end
end
