# frozen_string_literal: true

module HometownWeek
  # Read a same-origin stylesheet so it can be inlined in <head>.
  # A tag (not a {{ }} filter) writes the file straight into the output.
  # Liquid filters are easy to HTML-escape later, and escaped quotes or
  # child combinators would silently drop rules inside <style>.
  module InlineCss
    module_function

    def read(context, relative_path)
      site = context.registers[:site]
      relative = relative_path.to_s.strip.gsub(/\A["']|["']\z/, "").sub(%r{\A/}, "")
      root = File.expand_path(site.source)
      full = File.expand_path(relative, root)
      prefix = root + File::SEPARATOR
      unless full.start_with?(prefix) && File.file?(full)
        raise ArgumentError, "inline_css: missing stylesheet #{relative_path}"
      end

      File.read(full).gsub("</style", "<\\/style")
    end
  end

  class InlineCssTag < Liquid::Tag
    def initialize(tag_name, markup, tokens)
      super
      @path = markup
    end

    def render(context)
      InlineCss.read(context, @path)
    end
  end
end

Liquid::Template.register_tag("inline_css", HometownWeek::InlineCssTag)
