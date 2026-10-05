# frozen_string_literal: true

# Fingerprint stylesheets and event-share.js before Jekyll reads static
# files and data, so the head can link the hashed files and the service
# worker precaches those exact URLs.
Jekyll::Hooks.register :site, :after_init do |site|
  leaflet = File.join(site.source, "script/trim-leaflet-css.py")
  unless system("python3", leaflet, chdir: site.source)
    raise "Could not trim Leaflet CSS. Install rcssmin with: python3 -m pip install rcssmin"
  end
  script = File.join(site.source, "script/fingerprint-css.py")
  success = system("python3", script, chdir: site.source)
  unless success
    raise "Could not fingerprint CSS. Install rcssmin with: python3 -m pip install rcssmin"
  end
end
