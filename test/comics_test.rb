require "test_helper"
require "base64"

class ComicsTest < Minitest::Test
  PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAABgAAAAICAIAAABsw6g0AAAAHklEQVR4nGM8YaPBQA3ARBVTqGkQ1QDj8A0jqhkEAA/mAmW2A+vsAAAAAElFTkSuQmCC")
  GIF = Base64.decode64("R0lGODdhGAAIAIAAAAAAAAAAACwAAAAAGAAIAAAIIAABCBxIsKDBgwgTKlxoMIDDhxAjSnzIsKLFixgzJgwIADs=")
  PAGE_URL = "https://www.arcamax.com/thefunnies/peanuts/".freeze
  IMAGE_URL = "https://www.arcamax.com/newspics/12/1234/123456.gif".freeze

  def page(image_url = IMAGE_URL)
    %(<html><head><meta property="og:image" content="#{image_url}"></head><body></body></html>)
  end

  def config(*slugs, source: nil)
    { "strips" => slugs.map { |s| { "name" => s.capitalize, "slug" => s }.merge(source ? { "source" => source } : {}) } }
  end

  def digest(responses, strips = ["peanuts"], converter: ->(_) { nil })
    Circadex::Sources::Comics.new(config(*strips), http: FakeHttp.new(responses), converter: converter).digest(Date.new(2026, 10, 24))
  end

  def test_fetches_strip_image
    strip = digest({ PAGE_URL => page, IMAGE_URL => PNG }).strips.first

    assert_equal "Peanuts", strip.name
    assert_equal PNG, strip.image
    assert_nil strip.notice
  end

  def test_converts_gif_with_the_converter
    seen = nil
    converter = ->(bytes) { seen = bytes; PNG }
    strip = digest({ PAGE_URL => page, IMAGE_URL => GIF }, converter: converter).strips.first

    assert_equal GIF, seen
    assert_equal PNG, strip.image
  end

  def test_missing_image_tag_gives_notice
    strip = digest({ PAGE_URL => "<html><body>nothing</body></html>" }).strips.first

    assert_nil strip.image
    assert_equal "Unavailable today.", strip.notice
  end

  def test_image_from_unexpected_host_is_rejected
    strip = digest({ PAGE_URL => page("https://evil.example.test/x.png"), "https://evil.example.test/" => PNG }).strips.first

    assert_nil strip.image
  end

  def test_finds_image_by_alt_text_and_resolves_relative_urls
    html = '<html><body><img src="/logo.png" alt="logo"><img src="/newspics/1/2/3.gif" alt="Peanuts for today"></body></html>'
    strip = digest({ PAGE_URL => html, "https://www.arcamax.com/newspics/1/2/3.gif" => PNG }).strips.first

    assert_equal PNG, strip.image
  end

  def test_finds_image_by_strip_like_path_when_alt_is_missing
    html = '<html><body><img src="//www.arcamax.com/newspics/9/9/9.png"></body></html>'
    strip = digest({ PAGE_URL => html, "https://www.arcamax.com/newspics/9/9/9.png" => PNG }).strips.first

    assert_equal PNG, strip.image
  end

  def test_prefers_the_strip_over_the_icon_even_when_the_icon_matches_first
    icon = "https://www.arcamax.com/images/garfield-icon.gif"
    strip = "https://resources.arcamax.com/newspics/397/39798/3979805.gif"
    html = %(<html><head><meta property="og:image" content="#{icon}"></head><body>
             <img src="#{icon}" alt="Garfield"><img src="#{strip}" alt="Garfield"></body></html>)
    http = FakeHttp.new("https://www.arcamax.com/thefunnies/garfield/" => html, strip => PNG, icon => "icon bytes")
    result = Circadex::Sources::Comics.new(config("garfield"), http: http, converter: ->(_) { nil }).digest(Date.new(2026, 10, 24)).strips.first

    assert_equal PNG, result.image
    refute_includes http.requests, icon
  end

  def test_strip_pattern_wins_even_without_alt_text
    html = '<html><body><img src="/logo.png"><img src="https://resources.arcamax.com/newspics/1/22/333.gif"></body></html>'
    http = FakeHttp.new(PAGE_URL => html, "https://resources.arcamax.com/newspics/1/22/333.gif" => PNG)

    assert_equal PNG, Circadex::Sources::Comics.new(config("peanuts"), http: http).digest(Date.new(2026, 10, 24)).strips.first.image
  end

  def test_gocomics_source_uses_its_own_page_address
    gc_page = "https://www.gocomics.com/peanuts"
    gc_image = "https://featureassets.gocomics.com/assets/abc123.png"
    http = FakeHttp.new(gc_page => page(gc_image), gc_image => PNG)
    strip = Circadex::Sources::Comics.new(config("peanuts", source: "gocomics"), http: http).digest(Date.new(2026, 10, 24)).strips.first

    assert_equal PNG, strip.image
    assert_equal [gc_page, gc_image], http.requests
  end

  def test_unknown_source_gives_notice
    strip = Circadex::Sources::Comics.new(config("peanuts", source: "nope"), http: FakeHttp.new({})).digest(Date.new(2026, 10, 24)).strips.first

    assert_equal "Unavailable today.", strip.notice
  end

  def test_missing_image_logs_what_the_page_contained
    io = StringIO.new
    original = Circadex.instance_variable_get(:@logger)
    Circadex.instance_variable_set(:@logger, Logger.new(io, level: Logger::WARN))
    digest({ PAGE_URL => '<html><head><title>A Page</title></head><body><img src="/x/banner.jpg"></body></html>' })

    assert_match(/1 images/, io.string)
    assert_match(%r{/x/banner\.jpg}, io.string)
    assert_match(/og:image absent/, io.string)
  ensure
    Circadex.instance_variable_set(:@logger, original)
  end

  def test_one_failing_strip_does_not_stop_the_others
    d = digest({ PAGE_URL => page, IMAGE_URL => PNG }, %w[peanuts garfield])

    assert_equal [true, false], d.strips.map { |s| !s.image.nil? }
    assert_equal "Unavailable today.", d.strips.last.notice
  end

  def test_unsupported_image_and_bad_slug
    assert_nil digest({ PAGE_URL => page, IMAGE_URL => "<html>not an image</html>" }).strips.first.image
    assert_equal "Unavailable today.", digest({}, ["../etc"]).strips.first.notice
  end
end

class ImageFileTest < Minitest::Test
  PNG = ComicsTest::PNG
  GIF = ComicsTest::GIF

  def test_sniffs_formats
    assert_equal :png, Circadex::ImageFile.kind(PNG)
    assert_equal :gif, Circadex::ImageFile.kind(GIF)
    assert_equal :jpeg, Circadex::ImageFile.kind("\xFF\xD8\xFF\xE0rest".b)
    assert_equal :webp, Circadex::ImageFile.kind("RIFF\x00\x00\x00\x00WEBPVP8 ".b)
    assert_nil Circadex::ImageFile.kind("<html>")
  end

  def test_png_and_jpeg_pass_through_untouched
    assert_same PNG, Circadex::ImageFile.printable(PNG, converter: ->(_) { flunk "should not convert" })
  end

  def test_real_conversion_when_a_tool_is_installed
    skip "no image converter installed" unless %w[sips magick convert].any? { |t| system("which #{t} > /dev/null 2>&1") }

    converted = Circadex::ImageFile.printable(GIF)

    assert_equal :png, Circadex::ImageFile.kind(converted)
  end
end
