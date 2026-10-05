# frozen_string_literal: true

require "open3"
require "pathname"
require "time"

module EastsideCalendar
  # Sitemap lastmod is when the page changed. jekyll-sitemap prints
  # last_modified_at for pages only when it is set.
  class LastModified < Jekyll::Generator
    priority :low

    def generate(site)
      page_times = {}
      data_times = {}

      site.pages.each do |page|
        next if page.data["sitemap"] == false

        stamped = committed_at(site, page)
        page_times[page] = stamped if stamped
        next unless page.data["layout"] == "city"

        events = File.join(site.source, "_data", "#{page.data['city']}_events.yml")
        next unless File.file?(events)

        events_stamp = committed_at_path(site, events)
        data_times[page] = events_stamp if events_stamp
      end

      site.pages.each do |page|
        next if page.data["sitemap"] == false

        times = [page_times[page]]
        if page.data["layout"] == "city"
          times << data_times[page]
        elsif page.url == "/"
          times.concat(page_times.values)
          times.concat(data_times.values)
        elsif page.data["layout"] == "state"
          state = page.data["state"].to_s
          site.pages.each do |other|
            next unless other.data["layout"] == "city" && other.data["state"].to_s == state

            times << page_times[other]
            times << data_times[other]
          end
        end

        latest = times.compact.max
        page.data["last_modified_at"] = EventCalendar.pacific_time(latest) if latest
      end
    end

    def committed_at(site, item)
      full = source_file(site, item)
      return nil unless full

      committed_at_path(site, full)
    end

    def committed_at_path(site, full)
      root = File.expand_path(site.source)
      relative = Pathname.new(full).relative_path_from(Pathname.new(root)).to_s
      stdout, status = Open3.capture2(
        "git", "-C", root, "log", "-1", "--format=%cI", "--", relative
      )
      if status.success?
        stamp = stdout.to_s.strip
        return Time.parse(stamp) unless stamp.empty?
      end

      File.mtime(full)
    rescue StandardError
      File.mtime(full)
    end

    def source_file(site, item)
      raw = item.path.to_s
      return raw if raw.start_with?("/") && File.file?(raw)

      candidate = File.expand_path(raw, site.source)
      candidate if File.file?(candidate)
    end

    # Newest commit among the files that actually feed a generated hub.
    # Hub pages have no source file, so the page generator asks for this
    # instead of stamping the build clock.
    def self.hub_sources(site, hub_id)
      root = site.source
      id = hub_id.to_s
      paths = []
      events = Dir[File.join(root, "_data", "*_events.yml")]
      drive = File.join(root, "_data", "worth_the_drive_events.yml")
      case id
      when "worth-the-drive"
        paths << drive
        paths << File.join(root, "_data", "venue_images.yml")
      when "this-weekend"
        paths.concat(events.reject { |path| path == drive })
        paths.concat(city_indexes(site))
      else
        paths << File.join(root, "_data", "seasonal_hubs.yml")
        paths.concat(events)
        paths << File.join(root, "_data", "hub_pools.yml")
        paths << File.join(root, "_data", "venue_images.yml")
        paths << File.join(root, "_data", "theme_images.yml")
        paths.concat(city_indexes(site))
        paths << File.join(root, "_data", "no_school_days.yml") if id == "spring-break"
      end
      paths.uniq
    end

    def self.city_indexes(site)
      Array(site.data["cities"]).filter_map do |city|
        next unless city.is_a?(Hash)

        path = File.join(site.source, city["id"].to_s, "index.md")
        path if File.file?(path)
      end
    end

    def self.latest_commit(site, paths)
      @commit_times ||= {}
      times = paths.filter_map do |path|
        full = File.expand_path(path)
        next unless File.file?(full)
        next @commit_times[full] if @commit_times.key?(full)

        @commit_times[full] = new.committed_at_path(site, full)
      end
      times.compact.max
    end
  end
end
