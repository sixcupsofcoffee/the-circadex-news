require "test_helper"
require "pdf/reader"
require "tmpdir"
require "base64"

class RendererTest < Minitest::Test
  PAGE = { "width_in" => 7.07, "height_in" => 9.43, "margin_pt" => 30, "body_pt" => 10 }.freeze

  def forecast
    days = (0..5).map do |i|
      Circadex::Day.new(date: Date.new(2026, 10, 24) + i, high: 60 + i, low: 45 + i, summary: "Showers", precip: 40)
    end
    Circadex::Forecast.new(location: "Providence, RI", today: days.first, upcoming: days.drop(1))
  end

  def story(title, paragraphs)
    Circadex::Story.new(title: title, url: "https://example.test/x", source: "Wire", byline: "Pat Reporter",
                        published: Time.parse("2026-10-24 09:30:00 -0400"), summary: "A summary.", paragraphs: paragraphs)
  end

  def render(edition)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "out.pdf")
      Circadex::Renderer.new({ "page" => PAGE }).render_file(edition, path)
      PDF::Reader.new(path).then { |reader| yield reader, File.binread(path) }
    end
  end

  def edition(sections: [], notices: [], date: Date.new(2026, 10, 24))
    Circadex::Edition.new(date: date, forecast: forecast, sections: sections, notices: notices)
  end

  def test_renders_masthead_weather_and_story
    section = Circadex::Section.new(title: "World", stories: [story("Budget deal “reached”", ["Word " * 80])], briefs: [])
    render(edition(sections: [section])) do |reader, bytes|
      text = reader.pages.map(&:text).join("\n")

      assert bytes.start_with?("%PDF")
      assert_includes text, "THE CIRCADEX"
      assert_includes text, "Saturday, October 24, 2026"
      assert_match(/High 60/, text)
      assert_includes text, "Budget deal"
      assert_equal 2, reader.page_count
    end
  end

  def test_long_story_flows_onto_extra_pages
    paragraphs = Array.new(60) { |i| "Paragraph #{i} " + ("lorem ipsum dolor " * 25) }
    section = Circadex::Section.new(title: "World", stories: [story("Long read", paragraphs)], briefs: [])
    render(edition(sections: [section])) do |reader, _|
      assert_operator reader.page_count, :>=, 3
      assert_includes reader.pages.last.text, "Paragraph"
      all_text = reader.pages.map(&:text).join(" ").gsub(/\s+/, " ")
      assert_includes all_text, "Paragraph 59"
    end
  end

  def test_unsupported_characters_do_not_crash
    section = Circadex::Section.new(title: "World", stories: [story("Emoji \u{1F600} and 中文", ["Café — naïve \u{1F600} text."])], briefs: [])
    render(edition(sections: [section])) do |reader, _|
      assert_includes reader.pages.map(&:text).join, "Caf"
    end
  end

  def test_notes_page_lists_notices_and_sunday_label
    render(edition(notices: ["News could not be loaded today (boom)."], date: Date.new(2026, 10, 25))) do |reader, _|
      text = reader.pages.map(&:text).join("\n")

      assert_includes text, "Sunday Edition"
      assert_includes text, "News could not be loaded today"
    end
  end

  def test_renders_mail_section
    msg = ->(subject, category) { Circadex::MailMessage.new(from: "Ann", address: "a@x.test", subject: subject, received: Time.parse("2026-10-24 03:00:00"), snippet: "Body text.", category: category) }
    digest = Circadex::MailDigest.new(attention: [msg.("Bill due Friday", :alert)], messages: [msg.("Dinner?", :personal)],
                                      newsletters: [msg.("Issue 42", :newsletter)], skipped: 3, total: 6, truncated: false)
    render(Circadex::Edition.new(date: Date.new(2026, 10, 24), forecast: forecast, sections: [], mail: digest, notices: [])) do |reader, _|
      text = reader.pages.map(&:text).join("\n")

      assert_includes text, "MAIL SINCE MIDNIGHT"
      assert_includes text, "6 messages"
      assert_includes text, "3 promotional skipped"
      %w[Needs\ attention Messages Newsletters Bill\ due\ Friday Dinner? Issue\ 42].each { |t| assert_includes text, t }
    end
  end

  def test_renders_analytics_section
    site = Circadex::AnalyticsSite.new(name: "blog.example.test", views: 12_345, visits: 4_000, prior_views: 10_000, average_views: 12_500.0,
                                       pages: [["/", 300]], referrers: [["news.ycombinator.com", 80]], notice: nil)
    down = Circadex::AnalyticsSite.new(name: "shop.example.test", pages: [], referrers: [], notice: "Analytics unavailable for this site.")
    digest = Circadex::AnalyticsDigest.new(date: Date.new(2026, 10, 23), sites: [site, down])
    render(Circadex::Edition.new(date: Date.new(2026, 10, 24), forecast: nil, sections: [], analytics: digest, notices: [])) do |reader, _|
      text = reader.pages.map(&:text).join("\n")

      assert_includes text, "SITE TRAFFIC"
      assert_includes text, "12,345 page views"
      assert_includes text, "+23% vs the day before"
      assert_includes text, "-1% vs the 7-day average"
      assert_includes text, "news.ycombinator.com"
      assert_includes text, "Analytics unavailable for this site."
    end
  end

  def test_renders_comics_with_image_and_notice
    png = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAABgAAAAICAIAAABsw6g0AAAAHklEQVR4nGM8YaPBQA3ARBVTqGkQ1QDj8A0jqhkEAA/mAmW2A+vsAAAAAElFTkSuQmCC")
    strips = [Circadex::ComicStrip.new(name: "Peanuts", image: png), Circadex::ComicStrip.new(name: "Garfield", notice: "Unavailable today."),
              Circadex::ComicStrip.new(name: "Broken", image: "not an image")]
    render(Circadex::Edition.new(date: Date.new(2026, 10, 24), forecast: nil, sections: [], comics: Circadex::ComicsDigest.new(date: Date.new(2026, 10, 24), strips: strips), notices: [])) do |reader, bytes|
      text = reader.pages.map(&:text).join("\n")

      assert_includes text, "COMICS"
      assert_includes text, "Peanuts"
      assert_includes text, "Unavailable today."
      assert_includes text, "Broken could not be displayed today."
      assert_includes bytes, "/Subtype /Image"
    end
  end

  def crossword(cols: 13, rows: 13)
    cells = {}
    rows.times { |r| cols.times { |c| cells[[c, r]] = nil if r.even? || c.even? } }
    cells[[0, 0]] = 1
    across = (1..14).map { |n| [n.to_s, "Across clue number #{n} with a fairly long description & more <b> (#{n + 3})"] }
    down = (1..14).map { |n| [n.to_s, "Down clue number #{n} with a fairly long description (#{n + 2})"] }
    Circadex::Crossword.new(title: "Quick crossword No 17,101", setter: "Pan", date: Time.now, cols: cols, rows: rows, cells: cells, across: across, down: down)
  end

  def test_renders_crossword_grid_and_clues_on_one_page
    render(Circadex::Edition.new(date: Date.new(2026, 10, 24), forecast: nil, sections: [], crossword: crossword, notices: [])) do |reader, _|
      assert_equal 2, reader.page_count
      text = reader.pages.last.text

      assert_includes text, "CROSSWORD"
      assert_includes text, "Quick crossword No 17,101"
      assert_includes text, "set by Pan"
      assert_includes text, "Across"
      assert_includes text, "Down"
      assert_includes text, "Across clue number 14"
      assert_includes text, "Down clue number 14"
      assert_includes text, "& more"
      assert_includes text, "<b> (4)"
    end
  end

  def test_renders_without_forecast
    render(Circadex::Edition.new(date: Date.new(2026, 10, 24), forecast: nil, sections: [], notices: [])) do |reader, _|
      assert_equal 1, reader.page_count
    end
  end
end
