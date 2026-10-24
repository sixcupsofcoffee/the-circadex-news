require "test_helper"

class FeedTest < Minitest::Test
  include Fixtures

  def test_parses_rss_items_and_skips_incomplete_ones
    items = Circadex::Sources::Feed.parse(fixture("rss.xml"), source: "Example Wire")

    assert_equal 2, items.size
    first = items.first
    assert_equal "City council & mayor reach budget deal", first.title
    assert_equal "https://example.test/budget", first.url
    assert_equal "Pat Reporter", first.author
    assert_equal "A deal was struck late Friday.", first.summary
    assert_equal Time.parse("2026-10-24 09:30:00 -0400"), first.published
    assert_includes first.content_html, "bridge inspections"
    assert_nil items.last.content_html
  end

  def test_parses_atom_entries
    item = Circadex::Sources::Feed.parse(fixture("atom.xml"), source: "Atom").first

    assert_equal "https://example.test/atom-1", item.url
    assert_equal "Sam Writer", item.author
    assert_equal Time.parse("2026-10-24T08:00:00-04:00"), item.published
    assert_equal "Short summary text.", item.summary
  end

  def feed_with(item_xml)
    %(<?xml version="1.0"?><rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/" xmlns:content="http://purl.org/rss/1.0/modules/content/"><channel>#{item_xml}</channel></rss>)
  end

  def test_finds_a_picture_from_media_content_thumbnail_or_enclosure
    media = feed_with('<item><title>A</title><link>https://x.test/a</link><media:content url="https://img.test/a.jpg" medium="image"/></item>')
    thumb = feed_with('<item><title>B</title><link>https://x.test/b</link><media:thumbnail url="https://img.test/b"/></item>')
    enclosure = feed_with('<item><title>C</title><link>https://x.test/c</link><enclosure url="https://img.test/c" type="image/png"/></item>')
    audio = feed_with('<item><title>D</title><link>https://x.test/d</link><enclosure url="https://audio.test/d.mp3" type="audio/mpeg"/></item>')

    assert_equal "https://img.test/a.jpg", Circadex::Sources::Feed.parse(media, source: "S").first.image_url
    assert_equal "https://img.test/b", Circadex::Sources::Feed.parse(thumb, source: "S").first.image_url
    assert_equal "https://img.test/c", Circadex::Sources::Feed.parse(enclosure, source: "S").first.image_url
    assert_nil Circadex::Sources::Feed.parse(audio, source: "S").first.image_url
  end

  def test_falls_back_to_the_first_image_in_the_item_html
    xml = feed_with('<item><title>E</title><link>https://x.test/e</link><content:encoded><![CDATA[<p>Hi</p><img src="https://img.test/e.jpg"><img src="https://img.test/other.jpg">]]></content:encoded></item>')

    assert_equal "https://img.test/e.jpg", Circadex::Sources::Feed.parse(xml, source: "S").first.image_url
  end
end
