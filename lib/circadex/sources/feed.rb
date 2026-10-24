require "nokogiri"

module Circadex
  module Sources
    module Feed
      module_function

      def parse(body, source:)
        doc = Nokogiri::XML(body)
        doc.remove_namespaces!
        nodes = doc.xpath("//item")
        nodes = doc.xpath("//entry") if nodes.empty?
        nodes.filter_map { |node| item_from(node, source) }
      end

      def item_from(node, source)
        title = Text.squish(text(node, "title"))
        url = link(node)
        return if title.empty? || url.nil?

        Item.new(
          title: Text.html_to_text(title),
          url: url,
          source: source,
          author: first_text(node, "creator", "author/name", "author[not(*)]"),
          published: parse_time(first_text(node, "pubDate", "published", "updated")),
          summary: Text.html_to_text(first_text(node, "description", "summary")),
          content_html: [text(node, "encoded"), text(node, "content")].find { |c| !c.strip.empty? },
          image_url: image_url(node)
        )
      end

      IMAGE_EXTENSION = /\.(jpe?g|png|gif|webp)(\?|\z)/i

      # Looks for a picture the feed itself offers: media:content / media:thumbnail, an image
      # enclosure, or the first <img> inside the item's HTML.
      def image_url(node)
        node.xpath("./content[@url] | ./thumbnail[@url] | ./enclosure[@url]").each do |media|
          type = media["type"].to_s
          next unless media.name == "thumbnail" || media["medium"] == "image" || type.start_with?("image") || media["url"].match?(IMAGE_EXTENSION)

          return media["url"] if media["url"].start_with?("http")
        end

        %w[encoded content description].each do |name|
          src = Nokogiri::HTML.fragment(text(node, name)).at_css("img[src]")&.[]("src").to_s
          return src if src.start_with?("http")
        end
        nil
      end

      def link(node)
        atom = node.xpath("link[@href]").find { |l| l["rel"].nil? || l["rel"] == "alternate" }
        return atom["href"] if atom

        url = Text.squish(text(node, "link"))
        url.empty? ? nil : url
      end

      def text(node, path)
        node.at_xpath(path)&.text.to_s
      end

      def first_text(node, *paths)
        paths.map { |path| Text.squish(text(node, path)) }.find { |t| !t.empty? }.to_s
      end

      def parse_time(str)
        Time.parse(str) unless str.strip.empty?
      rescue ArgumentError
        nil
      end
    end
  end
end
