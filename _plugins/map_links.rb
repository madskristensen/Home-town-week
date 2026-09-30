# frozen_string_literal: true

require "cgi"

module EastsideCalendar
  # Google Maps search link. A deferred script swaps Apple and Android.
  module MapLinks
    module_function

    def href(place, city = nil, name = nil)
      "https://www.google.com/maps/search/?api=1&query=#{encode(query_text(place, city, name))}"
    end

    def pin
      return @pin if @pin

      path = File.expand_path("../_includes/addr-pin.html", __dir__)
      @pin = File.read(path).gsub(/\s+/, " ").strip.freeze
    end

    # Venue and street, then the town, then WA.
    # `name` is a venue that is not already written in the place line,
    # such as a park name next to a street. It is not an event title.
    # A town already at the end of the line is not repeated.
    def query_text(place, city = nil, name = nil)
      place = squash(place)
      city = squash(city)
      name = squash(name)
      bits = []
      bits << name unless name.empty? || contains_phrase?(place, name)
      bits << place unless place.empty?
      text = bits.join(", ")
      text = text.sub(/,?\s*\b(?:WA|Washington)\b(?:\s+\d{5}(?:-\d{4})?)?\s*\z/i, "")
      text = text.sub(/\s+\d{5}(?:-\d{4})?\s*\z/, "")
      text = text.strip.sub(/[,\s]+\z/, "")
      unless city.empty? || ends_with_phrase?(text, city) || ends_with_known_city?(text)
        text = text.empty? ? city : "#{text}, #{city}"
      end
      text = text.strip.sub(/[,\s]+\z/, "")
      text.empty? ? "WA" : "#{text}, WA"
    end

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

    def squash(value)
      value.to_s.gsub(/\s+/, " ").strip
    end

    def contains_phrase?(text, phrase)
      !phrase.empty? && text.downcase.include?(phrase.downcase)
    end

    def ends_with_phrase?(text, phrase)
      !phrase.empty? && text.match?(/#{Regexp.escape(phrase)}\s*\z/i)
    end

    # A place line that already ends in Issaquah should not also gain
    # the page's city, such as Redmond.
    def ends_with_known_city?(text)
      city_names.any? { |name| ends_with_phrase?(text, name) }
    end

    def city_names
      return @city_names if @city_names

      path = File.expand_path("../_data/cities.yml", __dir__)
      @city_names = File.readlines(path).filter_map { |line| line[/^  name: (.+)$/, 1]&.strip }.freeze
    end
  end

  module MapSearchFilter
    def map_search(place, city = nil, name = nil)
      CGI.escapeHTML(MapLinks.href(place, city, name))
    end
  end
end

Liquid::Template.register_filter(EastsideCalendar::MapSearchFilter)
