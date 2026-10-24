require "nokogiri"

module Circadex
  module Text
    TRANSLITERATE = {
      "‘" => "'", "’" => "'", "“" => '"', "”" => '"',
      " " => " ", "​" => "", " " => " ", " " => " "
    }.freeze

    module_function

    def squish(str)
      str.to_s.gsub(/[[:space:]]+/, " ").strip
    end

    # Prawn's built-in fonts only cover Windows-1252, so anything else is dropped.
    def clean(str)
      str = str.to_s.gsub(/[‘’“” ​  ]/, TRANSLITERATE)
      str.encode("Windows-1252", invalid: :replace, undef: :replace, replace: "").encode("UTF-8")
    end

    def html_to_text(html)
      fragment = Nokogiri::HTML.fragment(html.to_s)
      fragment.css("script,style").remove
      squish(fragment.text)
    end

    def html_to_paragraphs(html)
      fragment = Nokogiri::HTML.fragment(html.to_s)
      fragment.css("script,style,figure,figcaption,aside").remove
      paragraphs = fragment.css("p").map { |p| squish(p.text) }.reject(&:empty?)
      paragraphs = fragment.text.split(/\n{2,}/).map { |p| squish(p) }.reject(&:empty?) if paragraphs.empty?
      paragraphs
    end

    def truncate(str, limit)
      return str if str.length <= limit

      cut = str[0, limit].sub(/\s+\S*\z/, "")
      "#{cut}…"
    end
  end
end
