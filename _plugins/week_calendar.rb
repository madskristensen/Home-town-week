# frozen_string_literal: true

require "date"

module HometownWeek
  # Monday–Sunday spans for issue grouping.
  #
  # The span comes from the date-span slug (sep-21-sep-27, sep-28-oct-4).
  # Front matter date / end_date is only a fallback when the slug does not parse.
  module Weeks
    MONTHS = {
      "jan" => 1, "feb" => 2, "mar" => 3, "apr" => 4,
      "may" => 5, "jun" => 6, "jul" => 7, "aug" => 8,
      "sep" => 9, "oct" => 10, "nov" => 11, "dec" => 12
    }.freeze

    module_function

    def calendar(zone_name, on_date = nil)
      today = on_date || today_in(zone_name)
      monday = today - ((today.wday + 6) % 7)
      {
        "today" => today.strftime("%Y-%m-%d"),
        "monday" => monday.strftime("%Y-%m-%d")
      }
    end

    def today_in(zone_name)
      name = zone_name.to_s.empty? ? "America/Los_Angeles" : zone_name.to_s
      previous = ENV["TZ"]
      ENV["TZ"] = name
      Time.now.to_date
    ensure
      if previous
        ENV["TZ"] = previous
      else
        ENV.delete("TZ")
      end
    end

    # Returns [start_date, end_date] or nil.
    def span_for(slug, year, date_value = nil, end_value = nil)
      parsed = span_from_slug(slug, year)
      return parsed if parsed

      start_date = coerce_date(date_value)
      end_date = coerce_date(end_value)
      return nil unless start_date && end_date

      [start_date, end_date]
    end

    def span_from_slug(slug, year)
      return nil if slug.to_s.empty? || year.to_s.empty?

      match = slug.to_s.downcase.match(/\A([a-z]{3})-(\d{1,2})-([a-z]{3})-(\d{1,2})\z/)
      return nil unless match

      start_month = MONTHS[match[1]]
      end_month = MONTHS[match[3]]
      return nil unless start_month && end_month

      year_i = year.to_i
      start_date = Date.new(year_i, start_month, match[2].to_i)
      end_year = end_month < start_month ? year_i + 1 : year_i
      end_date = Date.new(end_year, end_month, match[4].to_i)
      [start_date, end_date]
    rescue ArgumentError
      nil
    end

    def coerce_date(value)
      case value
      when Date
        value
      when Time, DateTime
        value.to_date
      when String
        return nil if value.strip.empty?

        Date.parse(value)
      end
    rescue ArgumentError
      nil
    end
  end

  class WeekCalendar < Jekyll::Generator
    priority :low

    def generate(site)
      zone = site.config["timezone"]
      site.data["calendar"] = Weeks.calendar(zone)

      issues = site.collections["issues"]
      return unless issues

      issues.docs.each do |doc|
        start_date, end_date = Weeks.span_for(
          doc.data["slug"],
          doc.data["year"],
          doc.data["date"] || doc.date,
          doc.data["end_date"]
        )
        unless start_date && end_date
          raise "Issue #{doc.relative_path} has no Monday–Sunday span"
        end

        doc.data["week_start"] = start_date.strftime("%Y-%m-%d")
        doc.data["week_end"] = end_date.strftime("%Y-%m-%d")
      end
    end
  end
end
