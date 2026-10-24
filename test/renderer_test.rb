require "test_helper"
require "pdf/reader"
require "tmpdir"
require "base64"

class RendererTest < Minitest::Test
  PAGE = { "width_in" => 7.07, "height_in" => 9.43, "margin_pt" => 30, "body_pt" => 10 }.freeze
  PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAABgAAAAICAIAAABsw6g0AAAAHklEQVR4nGM8YaPBQA3ARBVTqGkQ1QDj8A0jqhkEAA/mAmW2A+vsAAAAAElFTkSuQmCC")
  TIME = Time.parse("2026-10-24 03:00:00 -0400")

  def forecast
    codes = [2, 63, 85, 3, 0, 95]
    days = codes.each_with_index.map do |code, i|
      Circadex::Day.new(date: Date.new(2026, 10, 24) + i, high: 60 + i, low: 45 + i, summary: "Showers", precip: 40, code: code)
    end
    Circadex::Forecast.new(location: "Providence, RI", today: days.first, upcoming: days.drop(1))
  end

  def story(title, paragraphs)
    Circadex::Story.new(title: title, url: "https://example.test/x", source: "Wire", byline: "Pat Reporter",
                        published: TIME, summary: "A summary.", paragraphs: paragraphs)
  end

  def mail_message(subject, category, from: "Ann")
    Circadex::MailMessage.new(from: from, address: "a@x.test", subject: subject, received: TIME, snippet: "Body text.", category: category)
  end

  def site(name = "blog.example.test", views: 12_345)
    history = (0..13).map { |i| [Date.new(2026, 10, 10) + i, 800 + i * 40] }
    Circadex::AnalyticsSite.new(name: name, views: views, visits: 4_000, prior_views: 10_000, average_views: 10_000.0, history: history,
                                pages: [["/", 300], ["/post", 120]], referrers: [["news.ycombinator.com", 80]])
  end

  def edition(**parts)
    Circadex::Edition.new({ date: Date.new(2026, 10, 24), forecast: nil, sections: [], notices: [] }.merge(parts))
  end

  def render(edition, config = {})
    Dir.mktmpdir do |dir|
      path = File.join(dir, "out.pdf")
      Circadex::Renderer.new({ "page" => PAGE, "paper" => { "name" => "The Circadex Chronicle" } }.merge(config)).render_file(edition, path)
      reader = PDF::Reader.new(path)
      yield reader, File.binread(path), reader.pages.map { |p| p.text.gsub(/\s+/, " ") }
    end
  end

  def test_front_page_has_masthead_and_a_single_weather_strip
    render(edition(forecast: forecast)) do |_, bytes, pages|
      assert bytes.start_with?("%PDF")
      assert_includes pages[0], "The Circadex Chronicle"
      assert_match(/DAILY EDITION/, pages[0])
      assert_includes pages[0], "TODAY"
      assert_includes pages[0], "60° / 45°"
      assert_match(/SUN 25/, pages[0])
      assert_match(/THU 29/, pages[0])
      assert_includes pages[0], "40%", "precipitation shows in the strip"
    end
  end

  def test_sunday_edition_label
    render(edition(date: Date.new(2026, 10, 25))) { |_, _, pages| assert_match(/SUNDAY EDITION/, pages[0]) }
  end

  def test_renders_without_any_optional_sections
    render(edition) { |reader, _, _| assert_equal 1, reader.page_count }
  end

  def mail_digest(attention: 1, personal: 1, newsletters: 1, skipped: 3)
    Circadex::MailDigest.new(
      attention: Array.new(attention) { |i| mail_message("Bill due Friday #{i}", :alert) },
      messages: Array.new(personal) { |i| mail_message("Dinner? #{i}", :personal) },
      newsletters: Array.new(newsletters) { |i| mail_message("Issue #{i}", :newsletter, from: "Weekly") },
      skipped: skipped, total: attention + personal + newsletters + skipped, truncated: false
    )
  end

  def test_mail_sits_beside_the_lead_story_and_its_count_is_in_the_contents
    section = Circadex::Section.new(title: "World", stories: [story("Lead headline", ["Word " * 60])], briefs: [])
    render(edition(forecast: forecast, sections: [section], mail: mail_digest)) do |reader, _, pages|
      assert_includes pages[0], "Lead headline"
      assert_includes pages[0], "MAIL SINCE MIDNIGHT · 3"
      assert_includes pages[0], "NEEDS ATTENTION"
      assert_includes pages[0], "Bill due Friday 0"
      assert_includes pages[0], "3 new messages"
      assert_includes pages[0], "1 need attention"
      assert_includes pages[0], "3 promotional skipped"
    end
  end

  def test_traffic_is_not_on_the_front_page_but_has_its_own_page
    traffic = Circadex::AnalyticsDigest.new(date: Date.new(2026, 10, 23), sites: [site])
    render(edition(forecast: forecast, analytics: traffic)) do |reader, _, pages|
      refute_includes pages[0], "blog.example.test"
      refute_includes pages[0], "12,345"
      assert_match(/Site Traffic\s*2/, pages[0])
      assert_equal 2, reader.page_count
      assert_includes pages[1], "SITE TRAFFIC"
      assert_includes pages[1], "blog.example.test"
      assert_includes pages[1], "12,345"
      assert_includes pages[1], "+23% vs 7-day avg"
      assert_includes pages[1], "TOP PAGES"
      assert_includes pages[1], "REFERRERS"
    end
  end

  def test_several_sites_share_the_traffic_page
    traffic = Circadex::AnalyticsDigest.new(date: Date.new(2026, 10, 23), sites: (1..3).map { |i| site("site-#{i}.example.test") })
    render(edition(analytics: traffic)) do |_, _, pages|
      (1..3).each { |i| assert_includes pages.join(" "), "site-#{i}.example.test" }
    end
  end

  def test_overflow_mail_continues_on_a_mail_page_and_is_linked
    many = Circadex::MailDigest.new(attention: [], messages: (1..40).map { |i| mail_message("Personal subject number #{i}", :personal) }, newsletters: [], skipped: 0, total: 40, truncated: false)
    render(edition(mail: many)) do |reader, bytes, pages|
      assert_operator reader.page_count, :>=, 2
      assert_match(/\+ \d+ more on page 2/, pages[0])
      assert_match(/Mail\s*2/, pages[0])
      assert_includes bytes, "sec-inbox"
      assert_includes pages[1], "MAIL"
      assert_includes pages.join(" "), "Personal subject number 40"
    end
  end

  def test_contents_lists_sections_with_resolved_page_numbers_and_links
    sections = [Circadex::Section.new(title: "World", stories: [story("Budget deal", ["Word " * 80])], briefs: []),
                Circadex::Section.new(title: "Technology", stories: [story("New chip", ["Word " * 80])], briefs: [])]
    puzzle = Circadex::Crossword.new(title: "Quick", setter: nil, date: nil, cols: 2, rows: 2, cells: { [0, 0] => 1, [1, 0] => nil, [0, 1] => nil }, across: [["1", "Clue (2)"]], down: [["1", "Clue (2)"]])
    render(edition(sections: sections, crossword: puzzle, notices: ["Something failed."])) do |_, bytes, pages|
      assert_match(/IN THIS EDITION/, pages[0])
      assert_match(/Technology\s*\d/, pages[0])
      assert_match(/Crossword\s*\d/, pages[0])
      assert_match(/Notes\s*\d/, pages[0])
      %w[sec-technology sec-crossword sec-notes].each { |dest| assert_includes bytes, dest }
      assert_includes pages.join(" "), "TECHNOLOGY"
    end
  end

  def test_lead_story_is_on_the_front_page_and_continues_in_its_section_without_losing_text
    paragraphs = Array.new(40) { |i| "Paragraph #{i} " + ("lorem ipsum dolor " * 20) }
    sections = [Circadex::Section.new(title: "World", stories: [story("Lead headline", paragraphs), story("Second story", ["Other text. " * 20])], briefs: [])]
    render(edition(forecast: forecast, sections: sections)) do |_, _, pages|
      assert_includes pages[0], "Lead headline"
      assert_match(/Continued on page 2/, pages[0])
      assert_includes pages[1], "Continued from page 1: Lead headline"
      assert_includes pages[1], "WORLD"
      all = pages.join(" ")
      assert_includes all, "Paragraph 39"
      assert_equal 1, all.scan("Second story").size
    end
  end

  def test_a_short_lead_story_fits_on_the_front_page_and_is_not_repeated
    sections = [Circadex::Section.new(title: "World", stories: [story("Short lead", ["Just a little text. " * 8])], briefs: [])]
    render(edition(sections: sections)) do |reader, _, pages|
      assert_equal 1, reader.page_count
      assert_includes pages[0], "Short lead"
      refute_match(/Continued/, pages[0])
      refute_includes pages[0], "WORLD", "an emptied section should not leave a band behind"
    end
  end

  def test_the_lead_is_the_first_story_with_a_picture
    plain = story("Plain story", ["Text. " * 30])
    pictured = story("Pictured story", ["Text. " * 30])
    pictured.image = PNG
    sections = [Circadex::Section.new(title: "World", stories: [plain, pictured], briefs: [])]
    render(edition(sections: sections)) do |_, bytes, pages|
      assert_includes pages[0], "Pictured story"
      assert_includes bytes, "/Subtype /Image"
      assert_includes pages.join(" "), "Plain story"
    end
  end

  def test_story_pictures_appear_in_sections
    pictured = story("Second", ["Text. " * 30])
    pictured.image = PNG
    sections = [Circadex::Section.new(title: "World", stories: [story("Lead", ["Text. " * 30]), pictured], briefs: [])]
    render(edition(sections: sections)) { |_, bytes, _| assert_includes bytes, "/Subtype /Image" }
  end

  def test_stories_share_pages_and_long_story_flows_without_losing_text
    paragraphs = Array.new(60) { |i| "Paragraph #{i} " + ("lorem ipsum dolor " * 25) }
    sections = [Circadex::Section.new(title: "World", stories: [story("Short one", ["Brief text. " * 10]), story("Long read", paragraphs)], briefs: [])]
    render(edition(sections: sections)) do |reader, _, pages|
      all = pages.join(" ")

      assert_operator reader.page_count, :>=, 2
      assert_includes all, "Paragraph 59"
      assert_includes all, "Short one"
      assert_includes all, "Long read"
    end
  end

  def test_briefs_are_listed_in_two_columns
    briefs = (1..6).map { |i| Circadex::Item.new(title: "Brief number #{i}", url: "https://x.test/#{i}", source: "NPR", summary: "Short summary #{i}.") }
    render(edition(sections: [Circadex::Section.new(title: "World", stories: [], briefs: briefs)])) do |_, _, pages|
      assert_includes pages[1], "Also in World"
      (1..6).each { |i| assert_includes pages[1], "Brief number #{i}" }
    end
  end

  def test_unsupported_characters_do_not_crash_and_accents_are_kept
    sections = [Circadex::Section.new(title: "World", stories: [story("Emoji \u{1F600} and 中文", ["Café — naïve “quoted” \u{1F600} text."])], briefs: [])]
    render(edition(sections: sections)) do |_, _, pages|
      assert_includes pages.join, "Café"
      assert_includes pages.join, "naïve"
      refute_includes pages.join, "\u{1F600}"
    end
  end

  def test_crossword_grid_and_clues_on_one_page
    cells = {}
    13.times { |r| 13.times { |c| cells[[c, r]] = nil if r.even? || c.even? } }
    cells[[0, 0]] = 1
    across = (1..14).map { |n| [n.to_s, "Across clue number #{n} with a fairly long description & more <b> (#{n + 3})"] }
    down = (1..14).map { |n| [n.to_s, "Down clue number #{n} with a fairly long description (#{n + 2})"] }
    puzzle = Circadex::Crossword.new(title: "Quick crossword No 17,101", setter: "Pan", date: Time.now, cols: 13, rows: 13, cells: cells, across: across, down: down)
    render(edition(crossword: puzzle)) do |reader, _, pages|
      assert_equal 2, reader.page_count
      text = pages.last

      %w[CROSSWORD Across Down].each { |t| assert_includes text, t }
      assert_includes text, "set by Pan"
      assert_includes text, "Across clue number 14"
      assert_includes text, "Down clue number 14"
      assert_includes text, "& more"
    end
  end

  def test_comics_with_image_notice_and_bad_image
    strips = [Circadex::ComicStrip.new(name: "Peanuts", image: PNG), Circadex::ComicStrip.new(name: "Garfield", notice: "Unavailable today."),
              Circadex::ComicStrip.new(name: "Broken", image: "not an image")]
    render(edition(comics: Circadex::ComicsDigest.new(date: Date.new(2026, 10, 24), strips: strips))) do |_, bytes, pages|
      assert_includes pages.last, "COMICS"
      assert_includes pages.last, "Peanuts"
      assert_includes pages.last, "Unavailable today."
      assert_includes pages.last, "Broken could not be displayed today."
      assert_includes bytes, "/Subtype /Image"
    end
  end

  def test_notes_page_lists_notices
    render(edition(notices: ["News could not be loaded today (boom)."])) do |_, _, pages|
      assert_includes pages.last, "NOTES"
      assert_includes pages.last, "News could not be loaded today"
    end
  end

  def test_analytics_respects_the_show_setting
    traffic = Circadex::AnalyticsDigest.new(date: Date.new(2026, 10, 23), sites: [site])
    render(edition(analytics: traffic), "analytics" => { "show" => ["trend"] }) do |_, _, pages|
      assert_includes pages[1], "12,345"
      refute_includes pages[1], "TOP PAGES"
    end
  end

  def test_a_failed_site_shows_its_notice
    down = Circadex::AnalyticsSite.new(name: "down.example.test", history: [], pages: [], referrers: [], notice: "Analytics unavailable for this site.")
    render(edition(analytics: Circadex::AnalyticsDigest.new(date: Date.new(2026, 10, 23), sites: [down]))) do |_, _, pages|
      assert_includes pages[1], "down.example.test"
      assert_includes pages[1], "Analytics unavailable for this site."
    end
  end
end
