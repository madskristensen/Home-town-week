# frozen_string_literal: true

module HometownWeek
  # Read a same-origin stylesheet so it can be inlined in <head>.
  # WebKit may paint one frame before an external sheet applies.
  module InlineCss
    def inline_css(relative_path)
      site = @context.registers[:site]
      relative = relative_path.to_s.sub(%r{\A/}, "")
      root = File.expand_path(site.source)
      full = File.expand_path(relative, root)
      prefix = root + File::SEPARATOR
      unless full.start_with?(prefix) && File.file?(full)
        raise ArgumentError, "inline_css: missing stylesheet #{relative_path}"
      end

      File.read(full).gsub("</style", "<\\/style")
    end
  end
end

Liquid::Template.register_filter(HometownWeek::InlineCss)
