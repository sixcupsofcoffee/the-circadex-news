require "nokogiri"

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

      def densest_container(doc)
        doc.css("main,section,div").max_by do |node|
          node.xpath("./p").sum { |p| p.text.length }
        end
      end
    end
  end
end
