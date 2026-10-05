# frozen_string_literal: true

module EastsideCalendar
  # One generator, in this order. Filename order is not the order.
  # City calendars run first so a hub card can link to the .ics file.
  # Hubs run next and choose the photos. Structured data reads those photos.
  class SitePipeline < Jekyll::Generator
    priority :lowest

    def generate(site)
      EventCalendarGenerator.new.generate(site)
      SeasonalHubsGenerator.new.generate(site)
      StructuredDataGenerator.new.generate(site)
    end
  end
end
