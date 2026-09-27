# frozen_string_literal: true

require "open3"
require "pathname"
require "time"

module HometownWeek
  # Sitemap lastmod has to be when the page changed, not the Monday the
  # digest covers. jekyll-sitemap prints last_modified_at for pages only
  # when it is set, and otherwise falls back to an issue's date.
  class LastModified < Jekyll::Generator
    priority :low

    def generate(site)
      issues = site.collections["issues"]
      return unless issues

      issue_times = {}
      issues.docs.each do |doc|
        next if doc.data["sitemap"] == false

        stamped = committed_at(site, doc)
        next unless stamped

        doc.data["last_modified_at"] = stamped
        issue_times[doc] = stamped
      end

      site.pages.each do |page|
        next if page.data["sitemap"] == false

        times = []
        own = committed_at(site, page)
        times << own if own

        related = related_issues(site, page, issues.docs)
        times.concat(related.filter_map { |doc| issue_times[doc] })

        latest = times.compact.max
        page.data["last_modified_at"] = latest if latest
      end
    end

    def related_issues(_site, page, docs)
      url = page.url.to_s
      if url == "/" || page.data["layout"] == "state"
        return docs
      end

      city = page.data["city"]
      state = page.data["state"]
      return [] unless city && state

      matched = docs.select do |doc|
        doc.data["city"].to_s == city.to_s && doc.data["state"].to_s == state.to_s
      end
      year = page.data["year"]
      return matched unless year

      matched.select { |doc| doc.data["year"].to_i == year.to_i }
    end

    def committed_at(site, item)
      full = source_file(site, item)
      return nil unless full

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
