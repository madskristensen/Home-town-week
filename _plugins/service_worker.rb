# frozen_string_literal: true

module EastsideCalendar
  # Paths the service worker precaches. Built from real static files so a
  # new stylesheet, script, or icon is picked up without editing sw.js.
  # Generated calendar files are not Jekyll::StaticFile and are skipped.
  class ServiceWorkerShell < Jekyll::Generator
    priority :low

    def generate(site)
      pages = ["/"]
      images = []
      site.static_files.each do |file|
        next unless file.is_a?(Jekyll::StaticFile)

        path = file.relative_path.to_s
        path = "/#{path.sub(%r{\A/}, '')}"
        ext = File.extname(path).downcase
        name = File.basename(path).downcase
        if [".css", ".js", ".webmanifest"].include?(ext)
          pages << path unless path == "/sw.js"
        elsif name == "favicon.ico" || (path.start_with?("/assets/images/") && shell_icon?(name))
          images << path
        end
      end
      site.data["shell"] = {
        "pages" => pages.uniq,
        "images" => images.uniq.sort
      }
    end

    def shell_icon?(name)
      name.include?("favicon") || name.include?("apple-touch") || name.include?("icon-")
    end
  end
end
