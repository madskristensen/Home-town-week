# frozen_string_literal: true

module EastsideCalendar
  # Shared string helpers. Map links, mail links, and the camp and
  # lights pages all use these instead of a private copy.
  module TextUtil
    module_function

    def squash(value)
      value.to_s.gsub(/\s+/, " ").strip
    end

    # Percent-encode every byte except RFC 3986 unreserved characters.
    def encode(text)
      text.to_s.encode("UTF-8").each_byte.map do |byte|
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

    # "10-5" and "10-05" become 1005. Anything else is nil.
    def month_day_number(value)
      match = value.to_s.strip.match(/\A(\d{1,2})-(\d{1,2})\z/)
      return nil unless match

      month = match[1].to_i
      day = match[2].to_i
      return nil unless (1..12).cover?(month) && (1..31).cover?(day)

      month * 100 + day
    end
  end
end
