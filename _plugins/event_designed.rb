# frozen_string_literal: true

require "date"

module EastsideCalendar
  # The city card HTML the layout prints under the intro.
  module EventCalendar
    
    module_function


        def render_grouped_cards(page, cards, today)
          return "" if cards.empty?

          unless today
            assigns = { "events" => cards, "show_city" => false, "eager" => 0, "microdata" => "1" }
            assigns["defer"] = "1" if page.data["layout"].to_s == "city"
            return render_card_grid(page, assigns)
          end

          buckets = Hash.new { |hash, key| hash[key] = [] }
          cards.each do |assigns|
            iso = assigns["date"].to_s
            date = iso.empty? ? nil : Date.iso8601(iso)
            buckets[bucket_key(date, today)] << assigns
          rescue Date::Error, ArgumentError
            buckets[:later] << assigns
          end
          grouped = +""
          site = page.site
          BUCKETS.each do |key, label|
            list = buckets[key]
            next if list.nil? || list.empty?

            assigns = {
              "events" => list,
              "heading" => label,
              "show_city" => false,
              "eager" => 0,
              "microdata" => "1"
            }
            assigns["defer"] = "1" if page.data["layout"].to_s == "city"
            if key == :weekend
              assigns["share"] = "weekend"
              assigns["share_url"] = absolute_url(site, page.url)
              assigns["share_title"] = "This weekend in #{city_name_for(site, page)}"
            end
            grouped << render_card_grid(page, assigns)
          end
          grouped
        end

        def render_card_grid(page, assigns)
          site = page.site
          path = File.join(site.source, "_includes", "card-grid.html")
          template = site.liquid_renderer.file(path).parse(File.read(path))
          context = Liquid::Context.new(
            [site.site_payload],
            {},
            { site: site, page: { "path" => page.path.to_s } },
            true
          )
          context["include"] = assigns
          site.regenerator.add_dependency(site.in_source_dir(page.path), path)
          rendered = template.render!(context).to_s
          events = assigns["events"]
          if events.respond_to?(:any?) && events.any?
            raise "card-grid include did not render" unless rendered.include?('class="card-grid"')
            raise "card-grid include did not render an event card" unless rendered.include?('<article class="event-card"')
          end

          rendered
        end

        # Venue and pool photos are chosen after the hub index exists.
        # The card HTML is what the city layout prints under the intro.
        def finish_city_cards!(page)
          assigns = page.data["city_card_assigns"]
          return unless assigns.is_a?(Array)

          site = page.site
          city_id = page.data["city"].to_s
          venues = site.data.dig("venue_images", "venues")
          options = site.data.dig("card_photo_options", city_id)
          fallback = site.data["card_photo_fallback"]
          assigns.each do |card|
            next unless card.is_a?(Hash)
            next unless card["image"].to_s.empty?

            photo = venue_card_photo(card, venues) || fallback_card_photo(card, options, fallback)
            next unless photo

            card["image"] = photo["src"].to_s
            card["alt"] = photo["alt"].to_s
            card["credit"] = photo["credit"].to_s
            card["image_source"] = photo["source"].to_s
            card["schema_image"] = photo["src"].to_s
          end
          today = pacific_today(site.time)
          page.data["city_cards_html"] = render_grouped_cards(page, assigns, today)
          images = {}
          assigns.each do |card|
            src = card["image"].to_s
            anchor = card["heading_id"].to_s
            images[anchor] = src unless anchor.empty? || src.empty?
          end
          Array(page.data["visible_events"]).each do |event|
            next unless event.is_a?(Hash)

            anchor = event["url"].to_s.split("#", 2).last.to_s
            event["image"] = images[anchor] if images[anchor]
          end
        end

        def venue_card_photo(card, venues)
          place = card["place"].to_s
          place = card["schema_place"].to_s if place.empty?
          return nil if card["title"].to_s.empty? && place.empty?

          venue = SeasonalHubs.matching_venues({ "name" => card["title"].to_s, "place" => place }, venues).first
          photo = SeasonalHubs.listed_photo(venue, "venue") if venue
          return nil unless photo

          photo
        end

        def fallback_card_photo(card, options, fallback)
          photo = SeasonalHubs.fallback_choice(options, card["title"].to_s)
          photo ||= SeasonalHubs.fallback_choice(options, card["name"].to_s)
          if photo.nil? && fallback.is_a?(Hash) && !fallback["src"].to_s.empty?
            photo = fallback
          end
          return nil if photo.nil? || photo["src"].to_s.empty?

          photo
        end
  end
end
