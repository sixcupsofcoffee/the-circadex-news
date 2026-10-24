require "nokogiri"

module Circadex
  module Text
    module_function

    def squish(str)
      str.to_s.gsub(/[[:space:]]+/, " ").strip
    end

    # Removes characters that only get in the way of layout; the renderer drops any
    # remaining characters its fonts cannot draw.
    def normalize(str)
      str.to_s.gsub(/[\u200B-\u200D\uFEFF]/, "").tr("\u00A0\u2009\u202F", "   ")
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
