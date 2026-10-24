module Circadex
  module Sources
    class News
      MIN_FEED_BODY = 600

      def initialize(config, http: Http, now: Time.now)
        @config = config
        @http = http
        @now = now
      end

      def sections
        @config["sections"].map { |section| build_section(section) }
      end

      def build_section(section)
        errors = []
        lists = section["feeds"].filter_map { |feed| load_feed(feed, errors) }
        items = interleave(lists).uniq { |i| i.title.downcase }.uniq(&:url)

        full = items.first(section["full_articles"].to_i)
        briefs = items.drop(full.size).first(section["brief_count"].to_i)
        briefs.each { |b| b.summary = Text.truncate(b.summary.to_s, 220) }

        Section.new(
          title: section["title"],
          stories: full.map { |item| story_for(item) },
          briefs: briefs,
          notice: notice_for(section, items, errors)
        )
      end

      private

      def load_feed(feed, errors)
        items = Feed.parse(@http.get(feed["url"]), source: feed["name"])
        items.select { |item| fresh?(item) }
      rescue Http::Error => e
        Circadex.logger.warn("feed #{feed['name']}: #{e.message}")
        errors << feed["name"]
        nil
      end

      def fresh?(item)
        return true unless item.published

        @now - item.published <= @config["max_age_hours"].to_i * 3600
      end

      def interleave(lists)
        sorted = lists.map { |l| l.sort_by { |i| -(i.published&.to_i || 0) } }
        longest = sorted.map(&:size).max.to_i
        (0...longest).flat_map { |i| sorted.filter_map { |l| l[i] } }
      end

      MAX_IMAGE_BYTES = 8_000_000
      MAX_PDF_IMAGE_BYTES = 1_500_000

      def story_for(item)
        page = Page.new(item, @http)
        paragraphs = body_for(item, page)
        Story.new(
          title: item.title,
          url: item.url,
          source: item.source,
          byline: item.author.to_s.empty? ? nil : item.author,
          published: item.published,
          summary: item.summary,
          paragraphs: paragraphs,
          image: images? ? image_for(item, page) : nil
        )
      end

      def body_for(item, page)
        paragraphs = Text.html_to_paragraphs(item.content_html) if item.content_html
        paragraphs = Extract.paragraphs(page.html.to_s) unless paragraphs && paragraphs.sum(&:length) >= MIN_FEED_BODY
        paragraphs = [item.summary] if paragraphs.empty? && !item.summary.to_s.empty?
        paragraphs.first(@config["max_paragraphs"].to_i)
      end

      # The feed's own picture if it has one, otherwise the article page's lead image.
      def image_for(item, page)
        url = item.image_url || Extract.image_url(page.html.to_s, item.url)
        return unless url

        bytes = @http.get(url, binary: true)
        return if bytes.bytesize > MAX_IMAGE_BYTES

        printable = ImageFile.printable(bytes)
        printable &&= ImageFile.shrink(printable)
        return if printable.nil? || printable.bytesize > MAX_PDF_IMAGE_BYTES

        printable
      rescue Http::Error => e
        Circadex.logger.warn("image for #{item.url}: #{e.message}")
        nil
      end

      def images?
        @config["images"] != false
      end

      # Fetches an article page at most once, however many times its text or image is needed.
      class Page
        def initialize(item, http)
          @item = item
          @http = http
          @loaded = false
        end

        def html
          return @html if @loaded

          @loaded = true
          @html = @http.get(@item.url)
        rescue Http::Error => e
          Circadex.logger.warn("article #{@item.url}: #{e.message}")
          @html = nil
        end
      end

      def notice_for(section, items, errors)
        return "No feeds could be reached for this section." if errors.size == section["feeds"].size
        return "Nothing new in the last #{@config['max_age_hours']} hours." if items.empty?

        "Unavailable today: #{errors.join(', ')}." unless errors.empty?
      end
    end
  end
end
