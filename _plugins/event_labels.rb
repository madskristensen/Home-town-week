# frozen_string_literal: true

require "cgi"

module EastsideCalendar
  # Optional card labels. A field is shown only when it is one of the
  # known values. Seasonal tags stay in `tags` and are not labels.
  module EventLabels
    AGES = ["Toddlers", "Kids", "Teens", "All ages"].freeze
    SETTINGS = ["Indoor", "Outdoor"].freeze

    module_function

    def value(event, key)
      return nil if event.nil?

      if event.is_a?(Hash)
        return event[key.to_s] unless event[key.to_s].nil?
        return event[key.to_sym] unless event[key.to_sym].nil?
      end
      return nil unless event.respond_to?(:[])

      event[key.to_s]
    rescue StandardError
      nil
    end

    def text(event, key)
      raw = value(event, key)
      return "" if raw.nil? || raw == false

      raw.to_s.strip
    end

    def flag(event, key)
      raw = value(event, key)
      raw == true || raw.to_s.strip.casecmp("true").zero?
    end

    def cost_label(event)
      cost = text(event, "cost")
      return "" if cost.empty?
      return "Free" if cost.casecmp("free").zero?
      return cost if cost.match?(/\$\s?\d/)

      ""
    end

    def ages_label(event)
      ages = text(event, "ages")
      found = AGES.find { |item| item.casecmp(ages).zero? }
      found.to_s
    end

    def setting_label(event)
      setting = text(event, "setting")
      found = SETTINGS.find { |item| item.casecmp(setting).zero? }
      found.to_s
    end

    def labels(event)
      list = []
      cost = cost_label(event)
      list << cost unless cost.empty?
      ages = ages_label(event)
      list << ages unless ages.empty?
      setting = setting_label(event)
      list << setting unless setting.empty?
      list << "Drop-off" if flag(event, "drop_off")
      list << "Sign-up needed" if flag(event, "signup")
      list << "Sensory-friendly" if flag(event, "sensory")
      list
    end

    def free?(event)
      cost_label(event) == "Free"
    end

    def indoor?(event)
      setting_label(event) == "Indoor"
    end

    def html(event)
      list = labels(event)
      return "" if list.empty?

      items = list.map { |label| "<li>#{CGI.escapeHTML(label)}</li>" }
      %(<ul class="event-tags">#{items.join}</ul>)
    end

    def attrs(event)
      bits = []
      bits << 'data-free="1"' if free?(event)
      bits << 'data-indoor="1"' if indoor?(event)
      bits << 'data-dropoff="1"' if flag(event, "drop_off") && !camp?(event)
      bits.join(" ")
    end

    # How many cards on a page match each filter. A chip is shown only
    # when this is at least 3, so a filter never comes back empty.
    def filter_counts(events)
      free = indoor = drop = 0
      Array(events).each do |event|
        next unless event.is_a?(Hash)

        free += 1 if free?(event)
        indoor += 1 if indoor?(event)
        drop += 1 if flag(event, "drop_off") && !camp?(event)
      end
      { "free" => free, "indoor" => indoor, "dropoff" => drop }
    end

    # Day camps and overnight camps stay off the rainy-day and drop-off pages.
    def camp?(event)
      name = text(event, "name").downcase
      tags = Array(value(event, "tags")).map { |tag| tag.to_s.downcase }
      return true if tags.include?("camp") || tags.include?("camps")

      name.match?(/\bcamp?s?\b/)
    end
  end

  module EventLabelFilter
    def event_tag_html(event)
      EventLabels.html(event)
    end

    def event_tag_attrs(event)
      EventLabels.attrs(event)
    end
  end
end

Liquid::Template.register_filter(EastsideCalendar::EventLabelFilter)
