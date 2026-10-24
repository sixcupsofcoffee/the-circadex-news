require "nokogiri"

module Circadex
  module Sources
    # Fetches today's strip from GoComics: the strip page names its image in og:image.
    class Comics
      class Error < StandardError; end

      PAGE = "https://www.gocomics.com/%s".freeze
      SLUG = /\A[a-z0-9-]+\z/
      IMAGE_HOST = %r{\Ahttps://[a-z0-9.-]*gocomics\.com/}

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
        slug = strip["slug"].to_s
        raise Error, "invalid slug #{slug.inspect}" unless slug.match?(SLUG)

        url = format(PAGE, slug)
        image = image_for(url)
        ComicStrip.new(name: strip["name"], image: image, url: url)
      rescue Http::Error, Error => e
        hint = e.message.include?("returned 403") ? " (the site is refusing automated requests)" : ""
        Circadex.logger.warn("comic #{strip['name']}: #{e.message}#{hint}")
        ComicStrip.new(name: strip["name"], notice: "Unavailable today.")
      end

      def image_for(page_url)
        image_url = Nokogiri::HTML(@http.get(page_url)).at_css('meta[property="og:image"]')&.[]("content").to_s
        raise Error, "no strip image found on #{page_url}" unless image_url.match?(IMAGE_HOST)

        bytes = @http.get(image_url, binary: true)
        ImageFile.printable(bytes, converter: @converter) || raise(Error, "unsupported image format")
      end
    end
  end
end
