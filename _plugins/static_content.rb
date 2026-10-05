# frozen_string_literal: true

require "fileutils"

module EastsideCalendar
  # One writer for generated files that are not Jekyll pages:
  # city calendars, hub calendars, and Atom feeds.
  class StaticContent
    attr_reader :relative_path

    def initialize(dir, name, content)
      @dir = dir
      @name = name
      @content = content
      @relative_path = File.join(dir, name)
    end

    def path
      nil
    end

    def url
      "/#{@relative_path}"
    end

    def extname
      File.extname(@name)
    end

    def write?
      true
    end

    def destination(dest)
      File.join(dest, @relative_path)
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

  CalendarFile = StaticContent
  FeedFile = StaticContent
end
