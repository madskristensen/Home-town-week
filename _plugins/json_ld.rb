# frozen_string_literal: true

# Structured data is rendered with the rest of the head. Move every
# JSON-LD block to just before </body> so the head stays small.
module EastsideCalendar
  module JsonLd
    SCRIPT = %r{<script\b[^>]*type=["']application/ld\+json["'][^>]*>.*?</script>}mi.freeze

    def self.move(item)
      html = item.output
      return unless html&.include?("application/ld+json")

      blocks = []
      html = html.gsub(SCRIPT) do |block|
        blocks << block
        ""
      end
      return if blocks.empty?
      raise "JSON-LD found but #{item.url} has no </body>" unless html.include?("</body>")

      item.output = html.sub("</body>", "#{blocks.join}\n</body>")
    end
  end
end

Jekyll::Hooks.register :pages, :post_render do |page|
  EastsideCalendar::JsonLd.move(page)
end

Jekyll::Hooks.register :documents, :post_render do |document|
  EastsideCalendar::JsonLd.move(document)
end
