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

    def guides(site, today = nil)
      today ||= EventCalendar.pacific_today(site.time)
      data = site.data["featured_articles"]
      config = data.is_a?(Hash) ? data["guides"] : nil
      empty = { "articles" => [], "evergreen" => [], "buckets" => [] }
      return empty unless config.is_a?(Hash)

      names = article_names(site)
      cap = config["cap"].to_i
      cap = 5 if cap <= 0
      articles = []
      Array(config["articles"]).each do |item|
        break if articles.size >= cap

        guide = guide_article(site, names, item, today)
        articles << guide if guide
      end
      evergreen = Array(config["evergreen"]).filter_map { |item| plain_link(item) }
      buckets = Array(config["buckets"]).filter_map { |item| guide_bucket(site, item, today) }
      Jekyll.logger.info "Nav guides:", "#{articles.size} articles, #{buckets.size} bucket lists"
      { "articles" => articles, "evergreen" => evergreen, "buckets" => buckets }
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
      TextUtil.month_day_number(value)
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

    def article_names(site)
      names = {}
      Array(site.data["articles"]).each do |article|
        next unless article.is_a?(Hash)

        href = article["href"].to_s
        slug = href.sub(%r{\A/articles/}, "").delete_suffix("/")
        name = article["name"].to_s.strip
        names[slug] = name unless slug.empty? || name.empty?
      end
      names
    end

    def guide_article(site, names, item, today)
      return nil unless item.is_a?(Hash)

      slug = item["article"].to_s.strip
      return nil if slug.empty?
      return nil unless in_season?(item, today)
      return nil unless File.file?(File.join(site.source, "articles", "#{slug}.md"))

      name = names[slug]
      return nil if name.to_s.empty?

      { "name" => name, "href" => "/articles/#{slug}/" }
    end

    def guide_bucket(site, item, today)
      return nil unless item.is_a?(Hash)
      return nil unless in_season?(item, today)

      href = item["href"].to_s.strip
      return nil if href.empty?

      title = bucket_title(site, href)
      return nil if title.to_s.empty?

      { "name" => title, "href" => href }
    end

    def in_season?(item, today)
      return true if item["evergreen"] == true

      ranges = Array(item["ranges"])
      ranges = [item] if ranges.empty? && item["start"] && item["end"]
      ranges.any? { |range| range.is_a?(Hash) && covers?(today, range) }
    end

    def plain_link(item)
      return nil unless item.is_a?(Hash)

      name = item["name"].to_s.strip
      href = item["href"].to_s.strip
      return nil if name.empty? || href.empty?

      { "name" => name, "href" => href }
    end

    def bucket_title(site, href)
      wanted = href.end_with?("/") ? href : "#{href}/"
      page = site.pages.find do |item|
        permalink = item.data["permalink"].to_s.strip
        next false if permalink.empty?

        permalink = "#{permalink}/" unless permalink.end_with?("/")
        permalink == wanted
      end
      return nil unless page

      page.data["title"].to_s.strip
    end
  end
end

Jekyll::Hooks.register :site, :post_read do |site|
  site.data["featured_article"] = EastsideCalendar::FeaturedArticle.pick(site)
  site.data["nav_guides"] = EastsideCalendar::FeaturedArticle.guides(site)
end
