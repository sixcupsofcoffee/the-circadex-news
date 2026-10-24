require "test_helper"

class ExtractTest < Minitest::Test
  include Fixtures

  def test_keeps_article_paragraphs_only
    paragraphs = Circadex::Sources::Extract.paragraphs(fixture("article.html"))

    assert_equal 2, paragraphs.size
    assert_match(/landfall near the Rhode Island coast/, paragraphs.first)
  end

  def test_finds_densest_block_without_article_tag
    html = "<html><body><div><p>#{'a' * 50}</p></div><div><p>#{'b' * 60}</p><p>#{'c' * 60}</p></div></body></html>"

    assert_equal ["b" * 60, "c" * 60], Circadex::Sources::Extract.paragraphs(html)
  end

  def test_returns_empty_for_pages_without_text
    assert_empty Circadex::Sources::Extract.paragraphs("<html><body></body></html>")
  end
end
