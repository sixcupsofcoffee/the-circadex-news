require "test_helper"
require "base64"

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

  PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAABgAAAAICAIAAABsw6g0AAAAHklEQVR4nGM8YaPBQA3ARBVTqGkQ1QDj8A0jqhkEAA/mAmW2A+vsAAAAAElFTkSuQmCC")

  def image_feed(image_xml)
    %(<?xml version="1.0"?><rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/"><channel><item><title>Pic story</title><link>https://example.test/pic</link>
      <pubDate>Sat, 24 Oct 2026 09:30:00 -0400</pubDate><description>Short.</description>#{image_xml}</item></channel></rss>)
  end

  def story_with(responses, config_extra = {})
    feeds = [{ "name" => "Wire", "url" => "https://feeds.test/a" }]
    cfg = config([section_config(feeds, full: 1, briefs: 0)]).merge(config_extra)
    Circadex::Sources::News.new(cfg, http: FakeHttp.new(responses), now: NOW).sections.first.stories.first
  end

  def test_story_gets_the_feeds_picture
    story = story_with("https://feeds.test/a" => image_feed('<media:content url="https://img.test/p.png" medium="image"/>'), "https://img.test/p.png" => PNG)

    assert_equal PNG, story.image
  end

  def test_story_falls_back_to_the_article_pages_picture
    page = '<html><head><meta property="og:image" content="https://img.test/og.png"></head><body><article><p>' + ("Body text here. " * 12) + "</p></article></body></html>"
    http = FakeHttp.new("https://feeds.test/a" => image_feed(""), "https://example.test/pic" => page, "https://img.test/og.png" => PNG)
    story = Circadex::Sources::News.new(config([section_config([{ "name" => "Wire", "url" => "https://feeds.test/a" }], full: 1, briefs: 0)]), http: http, now: NOW).sections.first.stories.first

    assert_equal PNG, story.image
    assert_equal 1, http.requests.count("https://example.test/pic"), "the page should be fetched only once"
  end

  def test_missing_or_unsupported_picture_leaves_the_story_without_one
    assert_nil story_with("https://feeds.test/a" => image_feed('<media:content url="https://img.test/gone.png" medium="image"/>')).image
    assert_nil story_with("https://feeds.test/a" => image_feed('<media:content url="https://img.test/x.png" medium="image"/>'), "https://img.test/x.png" => "<html>not an image</html>").image
  end

  def test_images_can_be_turned_off
    feed = image_feed('<media:content url="https://img.test/p.png" medium="image"/>')
    story = story_with({ "https://feeds.test/a" => feed, "https://img.test/p.png" => PNG }, "images" => false)

    assert_nil story.image
  end
end
