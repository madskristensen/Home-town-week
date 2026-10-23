#!/usr/bin/env ruby
# frozen_string_literal: true
# Merge one partner JSON record into _data/sponsors.yml for a given offering.
# Idempotent by name+offering (title/name match, case-insensitive).
#
#   ruby script/apply-sponsor.rb path/to/record.json
#   ruby script/apply-sponsor.rb path/to/record.json --offering featured-city
#
# The JSON is the suggest API partner record (or webhook payload). Fields used:
# name, link, blurb, place or offering, town, photo / image path optional.
# Does not download photos; set image on the card by hand or pass --image.

require "json"
require "yaml"
require "optparse"

ROOT = File.expand_path("..", __dir__)
SPONSORS = File.join(ROOT, "_data", "sponsors.yml")

OFFERING_NEEDS_TOWN = %w[featured-city camp-enhanced].freeze

def die(msg)
  warn msg
  exit 1
end

def squash(text)
  text.to_s.strip.gsub(/\s+/, " ")
end

options = { image: nil, offering: nil, dry: false }
OptionParser.new do |o|
  o.banner = "Usage: apply-sponsor.rb RECORD.json [options]"
  o.on("--offering SLUG", "Override place/offering from the JSON") { |v| options[:offering] = v }
  o.on("--image PATH", "Site-relative image path for the card") { |v| options[:image] = v }
  o.on("--dry-run", "Print the merge target and exit") { options[:dry] = true }
end.parse!
path = ARGV.shift or die("Pass a JSON file path")

record = JSON.parse(File.read(path))
offering = squash(options[:offering] || record["offering"] || record["place"])
die("Missing offering (place)") if offering.empty?
name = squash(record["name"] || record["title"])
die("Missing name") if name.empty?
href = squash(record["link"] || record["href"] || record["url"])
die("href must be https://...") unless href.match?(%r{\Ahttps://\S+\z}i)
blurb = squash(record["blurb"] || record["line"])
town = squash(record["town"]).downcase
die("#{offering} needs town (city id)") if OFFERING_NEEDS_TOWN.include?(offering) && town.empty?

data = YAML.load_file(SPONSORS) || {}
data["seasons"] ||= {}
data["cards"] ||= { "weekend" => [], "cities" => {} }
data["cards"]["weekend"] ||= []
data["cards"]["cities"] ||= {}
data["listings"] ||= []
data["email"] ||= { "name" => "", "url" => "", "line" => "" }

card = {
  "title" => name,
  "href" => href,
  "blurb" => blurb,
  "sponsored" => true
}
card["image"] = options[:image] if options[:image]
card["town"] = town.empty? ? "Sponsored" : town

def same_name?(a, b)
  squash(a).downcase == squash(b).downcase
end

target = nil
case offering
when "featured-weekend"
  list = data["cards"]["weekend"]
  list.reject! { |c| c.is_a?(Hash) && same_name?(c["title"], name) }
  list << card
  target = "cards.weekend"
when "featured-city"
  cities = data["cards"]["cities"]
  list = cities[town] ||= []
  list.reject! { |c| c.is_a?(Hash) && same_name?(c["title"], name) }
  list << card
  target = "cards.cities.#{town}"
when /^seasonal-(christmas|fall|spring-break|summer-camps)$/
  key = Regexp.last_match(1)
  season = data["seasons"][key] ||= { "name" => "", "url" => "", "cards" => [] }
  if key == "summer-camps" || blurb.empty?
    season["name"] = name
    season["url"] = href
    target = "seasons.#{key} (line)"
  else
    season["cards"] ||= []
    season["cards"].reject! { |c| c.is_a?(Hash) && same_name?(c["title"], name) }
    season["cards"] << card
    season["name"] = name if squash(season["name"]).empty?
    season["url"] = href if squash(season["url"]).empty?
    target = "seasons.#{key}.cards"
  end
when "email-one", "email-four"
  data["email"]["name"] = name
  data["email"]["url"] = href
  data["email"]["line"] = blurb.empty? ? name : blurb
  target = "email"
when "camp-enhanced"
  row = {
    "name" => name,
    "url" => href,
    "town" => town,
    "blurb" => blurb
  }
  row["image"] = options[:image] if options[:image]
  list = data["listings"]
  list.reject! { |r| r.is_a?(Hash) && same_name?(r["name"], name) }
  list << row
  target = "listings"
when "birthday-featured"
  die("birthday-featured updates _data/birthday_venues.yml by hand (sponsored: true); not sponsors.yml")
else
  die("Unknown offering: #{offering}")
end

if options[:dry]
  puts "Would merge #{name.inspect} into #{target}"
  exit 0
end

header = File.readlines(SPONSORS).take_while { |line| line.start_with?("#") || line.strip.empty? }.join
body = YAML.dump(data)
body = body.sub(/\A---\n/, "")
File.write(SPONSORS, header + body)
puts "Merged #{name.inspect} into #{target} (#{SPONSORS})"
puts "Review the YAML (Psych may reorder keys). Add image paths if needed."
