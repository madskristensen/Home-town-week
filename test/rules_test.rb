# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "date"
require "jekyll"
require_relative "../_plugins/eastside_text"
require_relative "../_plugins/event_calendar"
require_relative "../_plugins/event_labels"
require_relative "../_plugins/map_links"

class RulesTest < Minitest::Test
  FIXTURE = File.expand_path("fixtures/rules.json", __dir__)
  RULES = JSON.parse(File.read(FIXTURE))

  def test_match_score
    RULES["match_score"].each do |row|
      score = EastsideCalendar::EventCalendar.match_score(row["left"], row["right"])
      assert_equal row["score"], score, "#{row["left"]} / #{row["right"]}"
    end
  end

  def test_year_inference
    RULES["year"].each do |row|
      today = Date.iso8601(row["today"])
      parsed = EastsideCalendar::EventCalendar.parse_when_text(row["text"], today)
      assert parsed, row["text"]
      assert_equal row["iso"], parsed.iso8601, row["text"]
    end
  end

  def test_buckets
    RULES["buckets"].each do |row|
      key = EastsideCalendar::EventCalendar.bucket_key(Date.iso8601(row["date"]), Date.iso8601(row["today"]))
      assert_equal row["key"], key.to_s, row["date"]
    end
  end

  def test_dst_offsets
    RULES["dst"].each do |row|
      year, month, day, hour, min, sec = row["utc"].split(/[-T:]/).map(&:to_i)
      utc = DateTime.new(year, month, day, hour, min, sec, 0)
      offset = EastsideCalendar::EventCalendar.pacific_offset_hours(utc)
      assert_equal row["offset"], offset, row["utc"]
    end
  end

  def test_parse_when
    RULES["parse_when"].each do |row|
      parsed = EastsideCalendar::EventCalendar.parse_when(row["value"])
      assert parsed, row["value"]
      assert_equal row["date"], parsed[:date].iso8601
      if row["time"].nil?
        assert_nil parsed[:time]
      else
        assert_equal row["time"], parsed[:time]
      end
    end
  end

  def test_shorten_blurb
    RULES["blurbs"].each do |row|
      out = EastsideCalendar::EventCalendar.shorten_blurb(row["text"], row["max"])
      assert_equal row["out"], out
    end
  end

  def test_map_query_and_encode
    RULES["maps"].each do |row|
      query = EastsideCalendar::MapLinks.query_text(row["place"], row["city"], row["name"])
      assert_equal row["query"], query, row["place"]
    end
    RULES["map_links"].each do |row|
      href = EastsideCalendar::MapLinks.href(row["place"], row["city"], row["name"])
      assert_equal row["href"], href, row["place"]
    end
    RULES["encode"].each do |row|
      assert_equal row["encoded"], EastsideCalendar::MapLinks.encode(row["text"])
      assert_equal row["encoded"], EastsideCalendar::TextUtil.encode(row["text"])
    end
  end

  def test_setting_inference
    RULES["settings"].each do |row|
      label = EastsideCalendar::EventLabels.infer_setting(
        "name" => row["name"],
        "place" => row["place"],
        "blurb" => row["blurb"],
        "tags" => row["tags"],
        "same_as" => row["same_as"]
      )
      assert_equal row["label"], label, row["name"]
    end
  end

  def test_shared_helpers
    assert_equal({ "bellevue" => "Bellevue" }, EastsideCalendar::TextUtil.city_names([{ "id" => "bellevue", "name" => "Bellevue" }, { "id" => "", "name" => "Nope" }]))
    assert_equal 1005, EastsideCalendar::TextUtil.month_day_number("10-5")
    assert_nil EastsideCalendar::TextUtil.month_day_number("13-40")
    assert_equal "a b", EastsideCalendar::TextUtil.squash("  a   b ")
  end
end
