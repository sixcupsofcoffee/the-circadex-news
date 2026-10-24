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

  def test_mail_is_included_when_enabled
    client = Class.new { def fetch_since(_) = [] }.new
    cfg = Circadex::Config.new(config.to_h.merge("mail" => { "enabled" => true }))
    edition = Circadex::Builder.new(cfg, http: FakeHttp.new({}), mail_client: client).build(Date.new(2026, 10, 24))

    assert_equal 0, edition.mail.total
  end

  def test_mail_failure_is_a_notice_without_secrets
    cfg = Circadex::Config.new(config.to_h.merge("mail" => { "enabled" => true }))
    Circadex::Secrets.stub(:keychain, nil) do
      edition = Circadex::Builder.new(cfg, http: FakeHttp.new({})).build(Date.new(2026, 10, 24))

      assert_nil edition.mail
      assert(edition.notices.any? { |n| n.start_with?("Mail could not be loaded") })
    end
  end

  def test_mail_is_skipped_when_disabled
    edition = Circadex::Builder.new(config, http: FakeHttp.new({})).build(Date.new(2026, 10, 24))

    assert_nil edition.mail
  end

  def test_analytics_failure_is_a_notice
    cfg = Circadex::Config.new(config.to_h.merge("analytics" => { "enabled" => true }))
    Circadex::Secrets.stub(:keychain, nil) do
      edition = Circadex::Builder.new(cfg, http: FakeHttp.new({})).build(Date.new(2026, 10, 24))

      assert_nil edition.analytics
      assert(edition.notices.any? { |n| n.start_with?("Analytics could not be loaded") })
    end
  end

  def test_analytics_included_when_enabled
    client = Object.new
    def client.sites = []
    cfg = Circadex::Config.new(config.to_h.merge("analytics" => { "enabled" => true }))
    edition = Circadex::Builder.new(cfg, http: FakeHttp.new({}), analytics_client: client).build(Date.new(2026, 10, 24))

    assert_empty edition.analytics.sites
  end

  def test_comics_failure_does_not_stop_the_paper
    cfg = Circadex::Config.new(config.to_h.merge("comics" => { "enabled" => true, "strips" => [{ "name" => "Peanuts", "slug" => "peanuts" }] }))
    edition = Circadex::Builder.new(cfg, http: FakeHttp.new({})).build(Date.new(2026, 10, 24))

    assert_equal "Unavailable today.", edition.comics.strips.first.notice
  end

  def test_crossword_failure_becomes_a_notice
    cfg = Circadex::Config.new(config.to_h.merge("crossword" => { "enabled" => true }))
    edition = Circadex::Builder.new(cfg, http: FakeHttp.new({})).build(Date.new(2026, 10, 24))

    assert_nil edition.crossword
    assert(edition.notices.any? { |n| n.start_with?("Crossword could not be loaded") })
  end
end
