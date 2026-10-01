# frozen_string_literal: true

require "cgi"
require "yaml"

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
      return found if found

      infer_setting(event)
    end

    # Theaters, libraries, and other buildings are Indoor. Parks, farms,
    # trails, beaches, and streets are Outdoor. The longest phrase wins.
    # A numbered street address does not count. A hike or parade in the
    # name, or a parade tag, stays Outdoor.
    def infer_setting(event)
      rules = venue_setting_rules
      return "" if rules.empty?

      name = text(event, "name").downcase
      blurb = text(event, "blurb").downcase
      hay = "#{name} #{text(event, "place")}".downcase
      tags = Array(value(event, "tags")).map { |tag| tag.to_s.downcase }
      return "Outdoor" if (tags & %w[parade pumpkin-patch corn-maze]).any?

      Array(rules["outdoor_activity"]).each do |phrase|
        token = phrase.to_s.downcase.strip
        next if token.empty?
        next unless phrase_in?(name, token) || blurb.match?(/\b(?:a|an)\s+(?:[\w-]+\s+){0,3}#{Regexp.escape(token)}\b/)

        return "Outdoor"
      end

      best_len = 0
      best = ""
      { "indoor" => "Indoor", "outdoor" => "Outdoor" }.each do |key, label|
        Array(rules[key]).each do |phrase|
          text = phrase.to_s.downcase.strip
          next unless phrase_in?(hay, text)
          next if text.length <= best_len

          best_len = text.length
          best = label
        end
      end
      return best unless best.empty?
      return "Indoor" if text(event, "same_as").downcase.include?("kcls.bibliocommons")

      ""
    end

    def phrase_in?(hay, phrase)
      text = phrase.to_s.downcase.strip
      return false if text.empty? || hay.to_s.empty?
      return false if text == "street" && hay.match?(/\d(?:st|nd|rd|th)?\s+(?:\w+\s+){0,3}street\b/)

      hay.match?(/(?<![a-z0-9])#{Regexp.escape(text)}(?![a-z0-9])/)
    end

    def venue_setting_rules
      return @venue_setting_rules if defined?(@venue_setting_rules) && @venue_setting_rules

      path = File.expand_path("../_data/venue_settings.yml", __dir__)
      @venue_setting_rules = if File.file?(path)
                               YAML.safe_load(File.read(path)) || {}
                             else
                               {}
                             end
    end

    def labels(event)
      list = []
      cost = cost_label(event)
      list << cost unless cost.empty?
      ages = ages_label(event)
      list << ages unless ages.empty?
      setting = setting_label(event)
      list << setting unless setting.empty?
      list << "Drop-off" if flag(event, "drop_off") && !camp?(event)
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
      cost = cost_label(event)
      bits << %(data-cost="#{CGI.escapeHTML(cost)}") unless cost.empty?
      ages = ages_label(event)
      bits << %(data-ages="#{CGI.escapeHTML(ages)}") unless ages.empty?
      setting = setting_label(event)
      bits << %(data-setting="#{CGI.escapeHTML(setting)}") unless setting.empty?
      bits << 'data-dropoff="1"' if flag(event, "drop_off") && !camp?(event)
      bits << 'data-signup="1"' if flag(event, "signup")
      bits << 'data-sensory="1"' if flag(event, "sensory")
      bits.join(" ")
    end

    # One chip per label that appears on the page, in the same words as
    # the card. A price and All ages stay on the card and are not chips.
    # Kids and Teens get a chip only at the old threshold of 3, so a thin
    # age group stays text the way All ages does. Toddlers stays a chip
    # whenever a card has it. Free is the paid-versus-free chip. The page
    # ORs chips inside a group and ANDs the groups.
    CHIP_MIN = 3

    def filter_counts(events)
      counts = Hash.new(0)
      seen = []
      Array(events).each do |event|
        next unless event.is_a?(Hash)

        labels(event).each do |label|
          counts[label] += 1
          seen << label unless seen.include?(label)
        end
      end
      seen.filter_map do |label|
        next unless chip?(label, counts[label])

        {
          "label" => label,
          "group" => chip_group(label),
          "value" => chip_value(label),
          "count" => counts[label]
        }
      end.sort_by { |chip| [chip_rank(chip["label"]), seen.index(chip["label"])] }
    end

    def chip?(label, count)
      return false if price_label?(label)
      return false if label.to_s.casecmp("All ages").zero?
      return count >= CHIP_MIN if label.to_s.casecmp("Kids").zero? || label.to_s.casecmp("Teens").zero?

      count >= 1
    end

    def price_label?(label)
      label.to_s.match?(/\$\s?\d/)
    end

    def chip_group(label)
      return "ages" if AGES.any? { |item| item.casecmp(label).zero? }
      return "setting" if SETTINGS.any? { |item| item.casecmp(label).zero? }
      return "dropoff" if label == "Drop-off"
      return "signup" if label == "Sign-up needed"
      return "sensory" if label == "Sensory-friendly"

      "cost"
    end

    def chip_value(label)
      %w[dropoff signup sensory].include?(chip_group(label)) ? "1" : label
    end

    def chip_rank(label)
      case chip_group(label)
      when "cost" then label == "Free" ? [0, 0] : [0, 1]
      when "ages" then [1, AGES.index { |item| item.casecmp(label).zero? } || 0]
      when "setting" then [2, SETTINGS.index { |item| item.casecmp(label).zero? } || 0]
      when "dropoff" then [3, 0]
      when "signup" then [4, 0]
      when "sensory" then [5, 0]
      else [9, 0]
      end
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
