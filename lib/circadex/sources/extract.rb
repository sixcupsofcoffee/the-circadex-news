require "nokogiri"
require "uri"

module Circadex
  module Sources
    # Pulls readable paragraphs out of an article page.
    module Extract
      NOISE = "script,style,nav,aside,footer,header,form,figure,noscript,iframe,button"
      MIN_PARAGRAPH = 40

      module_function

      def paragraphs(html)
        doc = Nokogiri::HTML(html)
        doc.css(NOISE).remove
        root = doc.at_css("article") || densest_container(doc) || doc.at_css("body")
        return [] unless root

        root.css("p").map { |p| Text.squish(p.text) }.select { |p| p.length >= MIN_PARAGRAPH }
      end

      # The article's lead picture: Open Graph / Twitter card image, else the first image in the article.
      def image_url(html, base_url)
        doc = Nokogiri::HTML(html)
        src = doc.at_css('meta[property="og:image"], meta[name="og:image"], meta[name="twitter:image"], meta[property="twitter:image"]')&.[]("content") ||
              doc.at_css("article img[src]")&.[]("src")
        return if src.to_s.strip.empty?

        url = URI.join(base_url, src.strip).to_s
        url.start_with?("http") ? url : nil
      rescue URI::Error
        nil
      end

      def densest_container(doc)
        doc.css("main,section,div").max_by do |node|
          node.xpath("./p").sum { |p| p.text.length }
        end
      end
    end
  end
end
