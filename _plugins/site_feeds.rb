# frozen_string_literal: true

require "cgi"
require "date"
require "fileutils"

module EastsideCalendar
  # Per-page Atom feeds for city, hub, and explore pages that list events.
  # Same shape as /feed.xml. Not added to the sitemap.
  module SiteFeeds
    module_function

    ATOM_TIME = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}\z/

    def prepare(site, page)
      return if page.data["atom_feed"]

      rows = rows_for(site, page)
      return if rows.nil?

      path = feed_path(page)
      page.data["atom_feed"] = path
      photos = photos_by_name(page.content)
      Array(page.data["visible_events"]).each do |row|
        next unless row.is_a?(Hash)

        image = row["image"].to_s
        name = row["name"].to_s
        photos[name] = image unless image.empty? || name.empty?
      end
      entries = rows.filter_map { |row| entry_for(row, photos) }
      entries = dedupe(entries)
      xml = document(site, page, path, entries)
      rel = path.sub(%r{\A/}, "")
      site.static_files << FeedFile.new(File.dirname(rel), File.basename(rel), xml)
    end

    def rows_for(site, page)
      if page.data["layout"].to_s == "city"
        Array(page.data["visible_events"])
      elsif page.data["layout"].to_s == "seasonal" && !page.data["hub_id"].to_s.empty?
        Array(page.data["visible_events"])
      elsif page.data["explore_id"].to_s == "book-ahead"
        Array(site.data["book_ahead_cards"])
      end
    end

    def feed_path(page)
      base = page.url.to_s.sub(%r{/\z}, "")
      "#{base}/feed.xml"
    end

    def photos_by_name(content)
      map = {}
      EventCalendar.markdown_headings(content).each do |heading|
        photo = SeasonalHubs.parse_photo_include(heading[:body])
        src = photo && photo["src"].to_s.strip
        next if src.to_s.empty?

        map[heading[:text].to_s] = src
      end
      map
    end

    def entry_for(event, photos)
      return nil unless event.is_a?(Hash)

      name = event["name"].to_s.strip
      return nil if name.empty?

      blurb = event["blurb"].to_s.strip
      blurb = event["description"].to_s.strip if blurb.empty?
      city = event["city"].to_s.strip
      city = event["locality"].to_s.strip if city.empty?
      source = first_http(event["sameAs"], event["same_as"], event["source"], event["url"])
      image = event["image"].to_s.strip
      image = photos[name].to_s if image.empty?
      when_at = event["startDate"].to_s.strip
      when_at = event["start"].to_s.strip if when_at.empty?
      when_at = event["date"].to_s.strip if when_at.empty?
      {
        "name" => name,
        "blurb" => blurb,
        "city" => city,
        "source" => source.to_s,
        "image" => image,
        "when_at" => when_at
      }
    end

    def first_http(*values)
      values.each do |value|
        text = value.to_s.strip
        return text if EventCalendar.http_url?(text)
      end
      ""
    end

    def dedupe(entries)
      seen = {}
      entries.each_with_object([]) do |entry, kept|
        key = [entry["name"], entry["city"], entry["when_at"], entry["source"]]
        next if seen[key]

        seen[key] = true
        kept << entry
      end
    end

    def document(site, page, path, entries)
      page_url = EventCalendar.absolute_url(site, page.url)
      self_url = EventCalendar.absolute_url(site, path)
      updated = site.time.xmlschema
      title = "#{site.config["title"]}: #{page.data["title"]}"
      subtitle = page.data["description"].to_s.strip
      subtitle = site.config["description"].to_s if subtitle.empty?
      author = site.config.dig("author", "name").to_s
      used = {}
      body = entries.map { |entry| entry_xml(site, page_url, entry, updated, used) }.join
      <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>#{esc(title)}</title>
          <subtitle>#{esc(subtitle)}</subtitle>
          <link href="#{esc(self_url)}" rel="self"/>
          <link href="#{esc(page_url)}"/>
          <id>#{esc(page_url)}</id>
          <updated>#{esc(updated)}</updated>
          <author>
            <name>#{esc(author)}</name>
          </author>
        #{body}</feed>
      XML
    end

    def entry_xml(site, page_url, entry, fallback, used)
      stamp = atom_time(entry["when_at"], fallback)
      slug = EventCalendar.kramdown_id(entry["name"], used)
      id = "#{page_url}##{slug}"
      link = entry["source"].empty? ? "#{page_url}##{slug}" : entry["source"]
      summary = entry["blurb"].empty? ? entry["name"] : entry["blurb"]
      image = image_xml(site, entry["image"])
      city = entry["city"].empty? ? "" : %(    <category term="#{esc(entry["city"])}"/>\n)
      <<~XML
          <entry>
            <title>#{esc(entry["name"])}</title>
            <link href="#{esc(link)}"/>
            <id>#{esc(id)}</id>
            <updated>#{esc(stamp)}</updated>
            <published>#{esc(stamp)}</published>
        #{city}    <summary>#{esc(summary)}</summary>
        #{image}  </entry>
      XML
    end

    def image_xml(site, path)
      src = StructuredData.avif_source(site, path.to_s.strip)
      return "" unless src.start_with?("/")

      href = EventCalendar.absolute_url(site, src)
      %(    <link href="#{esc(href)}" rel="enclosure" type="#{esc(image_type(src))}"/>\n)
    end

    def image_type(path)
      case File.extname(path).downcase
      when ".png" then "image/png"
      when ".jpg", ".jpeg" then "image/jpeg"
      when ".gif" then "image/gif"
      when ".webp" then "image/webp"
      when ".avif" then "image/avif"
      else "application/octet-stream"
      end
    end

    def atom_time(value, fallback)
      text = value.to_s.strip
      return fallback if text.empty?
      return text if text.match?(ATOM_TIME)

      parsed = EventCalendar.parse_when(text)
      formatted = EventCalendar.format_offset_time(parsed).to_s if parsed
      return formatted if formatted.to_s.match?(ATOM_TIME)

      if (day = text[/\A(\d{4}-\d{2}-\d{2})/, 1])
        formatted = EventCalendar.format_offset_time({ date: Date.iso8601(day), time: nil }).to_s
        return formatted if formatted.match?(ATOM_TIME)
      end

      fallback
    rescue Date::Error, ArgumentError
      fallback
    end

    def esc(text)
      CGI.escapeHTML(text.to_s)
    end
  end

  class FeedFile
    def initialize(dir, name, content)
      @dir = dir
      @name = name
      @content = content
    end

    def path
      nil
    end

    def url
      "/#{@dir}/#{@name}"
    end

    def relative_path
      "#{@dir}/#{@name}"
    end

    def extname
      File.extname(@name)
    end

    def write?
      true
    end

    def destination(dest)
      File.join(dest, @dir, @name)
    end

    def write(dest)
      dest_path = destination(dest)
      FileUtils.mkdir_p(File.dirname(dest_path))
      File.binwrite(dest_path, @content)
      true
    end

    def modified_time
      Time.now
    end

    def mtime
      Time.now
    end
  end
end

Jekyll::Hooks.register :pages, :pre_render do |page, payload|
  EastsideCalendar::SiteFeeds.prepare(page.site, page)
  feed = page.data["atom_feed"]
  page_data = payload["page"] if payload
  page_data["atom_feed"] = feed if feed && page_data.respond_to?(:[]=)
end
