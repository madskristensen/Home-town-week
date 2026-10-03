# frozen_string_literal: true

require "date"

module EastsideCalendar
  # The home page featured line. Date windows live in
  # _data/featured_articles.yml. The daily rebuild picks again.
  module FeaturedArticle
    module_function

    def pick(site, today = nil)
      today ||= EventCalendar.pacific_today(site.time)
      data = site.data["featured_articles"]
      return nil unless data.is_a?(Hash)

      matches = Array(data["windows"]).select { |window| window.is_a?(Hash) && covers?(today, window) }
      window = matches.reverse.max_by { |item| month_day(item["start"]).to_i }
      chosen = rotate(lines_for(site, window), today)
      chosen ||= rotate(lines_for(site, { "items" => [data["fallback"]] }), today)
      if chosen
        Jekyll.logger.info "Featured article:", "#{chosen["text"]} (week #{today.cweek})"
      else
        Jekyll.logger.warn "Featured article:", "no article to show"
      end
      chosen
    end

    def covers?(date, window)
      start_md = month_day(window["start"])
      end_md = month_day(window["end"])
      return false unless start_md && end_md

      today = date.month * 100 + date.day
      if start_md <= end_md
        today >= start_md && today <= end_md
      else
        today >= start_md || today <= end_md
      end
    end

    def month_day(value)
      match = value.to_s.strip.match(/\A(\d{1,2})-(\d{1,2})\z/)
      return nil unless match

      month = match[1].to_i
      day = match[2].to_i
      return nil unless (1..12).cover?(month) && (1..31).cover?(day)

      month * 100 + day
    end

    def lines_for(site, window)
      return [] unless window.is_a?(Hash)

      Array(window["items"]).filter_map { |item| line_for(site, item) }
    end

    def line_for(site, item)
      return nil unless item.is_a?(Hash)

      slug = item["article"].to_s.strip
      text = item["text"].to_s.strip
      return nil if slug.empty? || text.empty? || text.include?("\u2014")
      return nil unless File.file?(File.join(site.source, "articles", "#{slug}.md"))

      { "text" => text, "url" => "/articles/#{slug}/" }
    end

    def rotate(lines, today)
      return nil if lines.empty?

      lines[today.cweek % lines.size]
    end
  end
end

Jekyll::Hooks.register :site, :post_read do |site|
  site.data["featured_article"] = EastsideCalendar::FeaturedArticle.pick(site)
end
