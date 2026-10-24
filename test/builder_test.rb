require "test_helper"

class BuilderTest < Minitest::Test
  include Fixtures

  def config
    Circadex::Config.new(
      "timezone" => "America/New_York",
      "weather" => { "latitude" => 41.8, "longitude" => -71.4, "location_name" => "Providence, RI" },
      "news" => { "max_age_hours" => 36, "max_paragraphs" => 14, "sections" => [
        { "title" => "Local", "full_articles" => 1, "brief_count" => 1,
          "feeds" => [{ "name" => "Wire", "url" => "https://feeds.test/a" }] }
      ] }
    )
  end

  def test_failed_weather_becomes_a_notice
    http = FakeHttp.new("https://feeds.test/a" => fixture("rss.xml"))
    edition = Circadex::Builder.new(config, http: http).build(Date.new(2026, 10, 24))

    assert_nil edition.forecast
    assert_equal 1, edition.sections.size
    assert_match(/Weather could not be loaded/, edition.notices.first)
  end

  def test_everything_down_still_returns_an_edition
    edition = Circadex::Builder.new(config, http: FakeHttp.new({})).build(Date.new(2026, 10, 24))

    assert_nil edition.forecast
    assert_equal 1, edition.sections.size
    assert_match(/No feeds could be reached/, edition.sections.first.notice)
  end
end
