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
  end
end
