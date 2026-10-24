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

      def story_for(item)
        Story.new(
          title: item.title,
          url: item.url,
          source: item.source,
          byline: item.author.to_s.empty? ? nil : item.author,
          published: item.published,
          summary: item.summary,
          paragraphs: body_for(item)
        )
      end

      def body_for(item)
        paragraphs = Text.html_to_paragraphs(item.content_html) if item.content_html
        paragraphs = fetch_body(item) unless paragraphs && paragraphs.sum(&:length) >= MIN_FEED_BODY
        paragraphs = [item.summary] if paragraphs.empty? && !item.summary.to_s.empty?
        paragraphs.first(@config["max_paragraphs"].to_i)
      end

      def fetch_body(item)
        Extract.paragraphs(@http.get(item.url))
      rescue Http::Error => e
        Circadex.logger.warn("article #{item.url}: #{e.message}")
        []
      end

      def notice_for(section, items, errors)
        return "No feeds could be reached for this section." if errors.size == section["feeds"].size
        return "Nothing new in the last #{@config['max_age_hours']} hours." if items.empty?

        "Unavailable today: #{errors.join(', ')}." unless errors.empty?
      end
    end
  end
end
