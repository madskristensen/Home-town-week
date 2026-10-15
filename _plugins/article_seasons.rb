# frozen_string_literal: true

require "date"

module EastsideCalendar
  # Seasonal order for the /articles/ card grid. Each row in
  # _data/articles.yml may carry a season: start and end (month-day,
  # may wrap the year end) and an optional lead (month-day the guide
  # starts rising before the season opens). Sorted at build time with
  # today in America/Los_Angeles; the daily rebuild re-sorts.
  #
  # 1. Rising: inside lead..end. Soonest season end first, because a
  #    window about to close is the most time-sensitive (the same rule
  #    as the home banner). Rows inside start..end get when "In season".
  # 2. Evergreen: no season. File order.
  # 3. Out of season: soonest return (lead, else start) first.
  # Ties keep file order. The result is site.data["articles_seasonal"];
  # site.data["articles"] keeps file order for search and the nav.
  module ArticleSeasons
    module_function

    IN_SEASON = "In season"

    def sort(rows, today)
      items = Array(rows).select { |row| row.is_a?(Hash) }.each_with_index.map do |row, index|
        tier, key, core = place(row["season"], today)
        copy = row.dup
        copy["when"] = IN_SEASON if core
        [tier, key, index, copy]
      end
      items.sort_by { |tier, key, index, _| [tier, key, index] }.map(&:last)
    end

    # Returns [tier, sort key, in core season].
    def place(season, today)
      return [1, 0, false] unless season.is_a?(Hash)

      start_md = season["start"].to_s
      end_md = season["end"].to_s
      return [1, 0, false] unless TextUtil.month_day_number(start_md) && TextUtil.month_day_number(end_md)

      lead_md = season["lead"].to_s
      lead_md = start_md unless TextUtil.month_day_number(lead_md)
      core = FeaturedArticle.covers?(today, { "start" => start_md, "end" => end_md })
      rising = core || FeaturedArticle.covers?(today, { "start" => lead_md, "end" => end_md })
      if rising
        [0, days_until(today, end_md), core]
      else
        [2, days_until(today, lead_md), false]
      end
    end

    # Days from today to the next date (today included) with that month-day.
    def days_until(today, month_day)
      month, day = month_day.split("-").map(&:to_i)
      [today.year, today.year + 1].each do |year|
        date = safe_date(year, month, day)
        return (date - today).to_i if date >= today
      end
      366
    end

    def safe_date(year, month, day)
      Date.new(year, month, day)
    rescue ArgumentError
      Date.new(year, month, -1)
    end
  end
end

Jekyll::Hooks.register :site, :post_read do |site|
  today = EastsideCalendar::EventCalendar.pacific_today(site.time)
  sorted = EastsideCalendar::ArticleSeasons.sort(site.data["articles"], today)
  site.data["articles_seasonal"] = sorted
  Jekyll.logger.info "Articles order:", sorted.map { |row| row["href"].to_s.sub(%r{\A/articles/}, "").delete_suffix("/") }.join(", ")
end
