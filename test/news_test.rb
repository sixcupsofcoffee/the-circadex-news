require "test_helper"

class NewsTest < Minitest::Test
  include Fixtures

  NOW = Time.parse("2026-10-24 12:00:00 -0400")

  def config(sections)
    { "max_age_hours" => 36, "max_paragraphs" => 14, "sections" => sections }
  end

  def section_config(feeds, full: 1, briefs: 5)
    { "title" => "Local", "full_articles" => full, "brief_count" => briefs, "feeds" => feeds }
  end

  def news(responses, sections)
    Circadex::Sources::News.new(config(sections), http: FakeHttp.new(responses), now: NOW)
  end

  def test_splits_items_into_stories_and_briefs
    feeds = [{ "name" => "Wire", "url" => "https://feeds.test/a" }]
    section = news({ "https://feeds.test/a" => fixture("rss.xml") }, [section_config(feeds)]).sections.first

    assert_equal ["City council & mayor reach budget deal"], section.stories.map(&:title)
    assert_equal ["Storm headed for the coast"], section.briefs.map(&:title)
    assert_equal 5, section.stories.first.paragraphs.size
    assert_nil section.notice
  end

  def test_fetches_article_page_when_feed_has_no_body
    feeds = [{ "name" => "Wire", "url" => "https://feeds.test/a" }]
    responses = { "https://feeds.test/a" => fixture("rss.xml"), "https://example.test/storm" => fixture("article.html") }
    section = news(responses, [section_config(feeds, full: 2, briefs: 0)]).sections.first

    storm = section.stories.last
    assert_equal 2, storm.paragraphs.size
    assert_match(/landfall/, storm.paragraphs.first)
  end

  def test_falls_back_to_summary_when_page_is_unreachable
    feeds = [{ "name" => "Wire", "url" => "https://feeds.test/a" }]
    responses = { "https://feeds.test/a" => fixture("rss.xml") }
    section = news(responses, [section_config(feeds, full: 2, briefs: 0)]).sections.first

    assert_equal ["Heavy rain is expected Sunday."], section.stories.last.paragraphs
  end

  def test_one_dead_feed_does_not_sink_the_section
    feeds = [{ "name" => "Wire", "url" => "https://feeds.test/a" }, { "name" => "Down", "url" => "https://feeds.test/b" }]
    section = news({ "https://feeds.test/a" => fixture("rss.xml") }, [section_config(feeds)]).sections.first

    assert_equal 1, section.stories.size
    assert_equal "Unavailable today: Down.", section.notice
  end

  def test_all_feeds_dead_gives_notice_not_error
    feeds = [{ "name" => "Down", "url" => "https://feeds.test/b" }]
    section = news({}, [section_config(feeds)]).sections.first

    assert_empty section.stories
    assert_match(/No feeds could be reached/, section.notice)
  end

  def test_stale_items_are_dropped
    feeds = [{ "name" => "Wire", "url" => "https://feeds.test/a" }]
    late = Circadex::Sources::News.new(config([section_config(feeds)]), http: FakeHttp.new("https://feeds.test/a" => fixture("rss.xml")), now: NOW + 7 * 86_400)
    section = late.sections.first

    assert_empty section.stories
    assert_match(/Nothing new/, section.notice)
  end

  def test_interleaves_feeds_and_dedupes_by_title
    a = fixture("rss.xml")
    b = fixture("rss.xml").gsub("https://example.test/", "https://other.test/")
    feeds = [{ "name" => "A", "url" => "https://feeds.test/a" }, { "name" => "B", "url" => "https://feeds.test/b" }]
    section = news({ "https://feeds.test/a" => a, "https://feeds.test/b" => b }, [section_config(feeds, full: 0, briefs: 10)]).sections.first

    assert_equal 2, section.briefs.size
  end
end
