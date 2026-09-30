# frozen_string_literal: true

# Stars come from the playground entries in _data/guides.yml.
# At most four per city, in the order written there. Matching parks
# sort to the front of that city's list. The flag is added in memory
# so the map JSON and the HTML list stay in step.
Jekyll::Hooks.register :site, :post_read do |site|
  EastsideCalendar::PlaygroundStandouts.apply(site)
end

module EastsideCalendar
  module PlaygroundStandouts
    MAX_PER_CITY = 4

    module_function

    def apply(site)
      map = site.data["playground_map"]
      groups = site.data.dig("guides", "playgrounds", "groups")
      return unless map.is_a?(Hash) && map["cities"] && groups

      by_city = {}
      groups.each do |group|
        by_city[group["id"]] = group["entries"] || []
      end

      map["cities"].each do |city|
        parks = city["parks"] || []
        parks.each { |park| park.delete("standout") }
        starred = []
        (by_city[city["id"]] || []).each do |entry|
          break if starred.size >= MAX_PER_CITY

          park = match(parks, entry)
          if park.nil?
            Jekyll.logger.warn("Playground standout not in the map: #{city["name"]} / #{entry["name"]}")
            next
          end
          next if starred.include?(park)

          park["standout"] = true
          starred << park
        end
        city["parks"] = starred + parks.reject { |park| starred.include?(park) }
      end
    end

    def match(parks, entry)
      page = entry["page"].to_s
      unless page.empty?
        hits = parks.select { |park| park["page"].to_s == page }
        return hits.first if hits.size == 1
      end

      wanted = norm(entry["name"])
      return nil if wanted.empty?

      hits = parks.select { |park| norm(park["name"]) == wanted }
      return hits.first if hits.size == 1

      hits = parks.select do |park|
        name = norm(park["name"])
        name.start_with?("#{wanted} ") || wanted.start_with?("#{name} ")
      end
      hits.size == 1 ? hits.first : nil
    end

    def norm(name)
      name.to_s.downcase.tr("’'", "").gsub(/[^a-z0-9]+/, " ").strip.sub(/\s+park\z/, "").strip
    end
  end
end
