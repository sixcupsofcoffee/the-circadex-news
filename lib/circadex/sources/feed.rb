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
          content_html: [text(node, "encoded"), text(node, "content")].find { |c| !c.strip.empty? }
        )
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
