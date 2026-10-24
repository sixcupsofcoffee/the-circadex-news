require "nokogiri"
require "uri"

module Circadex
  module Sources
    # Fetches today's strip image from a comics site. Each strip names a source
    # (default: arcamax) and a slug, the last part of the strip's page address.
    class Comics
      class Error < StandardError; end

      SOURCES = {
        "arcamax" => { page: "https://www.arcamax.com/thefunnies/%s/", host: /(\A|\.)arcamax\.com\z/ },
        "gocomics" => { page: "https://www.gocomics.com/%s", host: /(\A|\.)gocomics\.com\z/ }
      }.freeze
      DEFAULT_SOURCE = "arcamax".freeze
      SLUG = /\A[a-z0-9-]+\z/
      IMAGE_PATH = /\.(gif|jpe?g|png|webp)(\?|\z)/i

      def initialize(config, http: Http, converter: ImageFile.method(:convert))
        @config = config
        @http = http
        @converter = converter
      end

      def digest(date)
        strips = Array(@config["strips"]).map { |strip| fetch(strip) }
        Circadex.logger.info("Comics: #{strips.count(&:image)} of #{strips.size} strips loaded")
        ComicsDigest.new(date: date, strips: strips)
      end

      private

      def fetch(strip)
        source = SOURCES.fetch(strip["source"] || DEFAULT_SOURCE) { raise Error, "unknown comics source #{strip['source'].inspect}" }
        slug = strip["slug"].to_s
        raise Error, "invalid slug #{slug.inspect}" unless slug.match?(SLUG)

        url = format(source[:page], slug)
        ComicStrip.new(name: strip["name"], image: image_for(url, source, strip["name"]), url: url)
      rescue Http::Error, Error => e
        hint = e.message.include?("returned 403") ? " (the site is refusing automated requests)" : ""
        Circadex.logger.warn("comic #{strip['name']}: #{e.message}#{hint}")
        ComicStrip.new(name: strip["name"], notice: "Unavailable today.")
      end

      def image_for(page_url, source, name)
        doc = Nokogiri::HTML(@http.get(page_url))
        image_url = find_image(doc, page_url, source, name)
        unless image_url
          log_page_summary(doc, page_url)
          raise Error, "no strip image found on #{page_url}"
        end

        bytes = @http.get(image_url, binary: true)
        ImageFile.printable(bytes, converter: @converter) || raise(Error, "unsupported image format")
      end

      # Prefers the page's og:image, then an <img> whose alt text names the strip,
      # then any other image on the site's own host that looks like a strip.
      def find_image(doc, page_url, source, name)
        candidates = []
        candidates << doc.at_css('meta[property="og:image"]')&.[]("content")
        images = doc.css("img[src]")
        candidates += images.select { |img| img["alt"].to_s.downcase.include?(name.to_s.downcase) }.map { |img| img["src"] }
        candidates += images.select { |img| img["src"].to_s.match?(%r{/(newspics|comics|strips)/}i) }.map { |img| img["src"] }

        candidates.compact.filter_map { |src| absolute(page_url, src) }
                  .find { |url| URI(url).host.to_s.match?(source[:host]) && URI(url).path.match?(IMAGE_PATH) }
      end

      def absolute(base, src)
        URI.join(base, src.strip).to_s
      rescue URI::Error
        nil
      end

      # When the page has no image we can recognise, say what is there so the selector can be fixed.
      def log_page_summary(doc, page_url)
        sources = doc.css("img[src]").first(6).map { |img| img["src"].to_s[0, 90] }
        Circadex.logger.warn("comics page #{page_url}: title #{doc.at_css('title')&.text.to_s.strip[0, 60].inspect}, " \
                             "#{doc.css('img').size} images, og:image #{doc.at_css('meta[property="og:image"]') ? 'present' : 'absent'}, " \
                             "first images: #{sources.inspect}")
      end
    end
  end
end
