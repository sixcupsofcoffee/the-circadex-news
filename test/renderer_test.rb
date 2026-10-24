require "test_helper"
require "pdf/reader"
require "tmpdir"

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

  def test_renders_without_forecast
    render(Circadex::Edition.new(date: Date.new(2026, 10, 24), forecast: nil, sections: [], notices: [])) do |reader, _|
      assert_equal 1, reader.page_count
    end
  end
end
