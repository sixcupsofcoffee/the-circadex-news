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
end
