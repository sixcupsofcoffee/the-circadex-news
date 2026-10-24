module Circadex
  module Sources
    # Yesterday's traffic for each Cloudflare Web Analytics site, compared with the
    # day before and the previous seven days.
    class Analytics
      class Error < StandardError; end

      DATASET = "rumPageloadEventsAdaptiveGroups".freeze
      HISTORY_DAYS = 8

      def initialize(config, client:, now: Time.now)
        @config = config
        @client = client
        @today = now.to_date
      end

      def digest
        sites = Array(@config["sites"]).map { |s| { "tag" => s["tag"], "name" => s["name"] } }
        sites = @client.sites if sites.empty?
        AnalyticsDigest.new(date: @today - 1, sites: sites.map { |site| report(site) })
      end

      def self.change(current, base)
        return nil unless base.to_i.positive?

        ((current - base) * 100.0 / base).round
      end

      private

      def report(site)
        totals = daily_totals(site["tag"])
        yesterday = totals.first
        prior = totals.drop(1)
        pages, referrers, notice = breakdowns(site["tag"])

        AnalyticsSite.new(
          name: site["name"], views: yesterday[:views], visits: yesterday[:visits],
          prior_views: prior.first[:views], average_views: prior.sum { |d| d[:views] } / prior.size.to_f,
          pages: pages, referrers: referrers, notice: notice
        )
      rescue Error, Http::Error, KeyError => e
        Circadex.logger.warn("analytics #{site['name']}: #{e.message}")
        AnalyticsSite.new(name: site["name"], pages: [], referrers: [], notice: "Analytics unavailable for this site.")
      end

      def daily_totals(tag)
        fields = (0...HISTORY_DAYS).map do |i|
          "d#{i}: #{DATASET}(filter: {#{window(@today - 1 - i)}}, limit: 1) { count sum { visits } }"
        end
        account = query(fields.join("\n"), tag)
        (0...HISTORY_DAYS).map do |i|
          row = Array(account["d#{i}"]).first || {}
          { views: row["count"].to_i, visits: row.dig("sum", "visits").to_i }
        end
      end

      # Each breakdown is its own request, so one failing field never loses the totals.
      def breakdowns(tag)
        notes = []
        pages = breakdown(tag, "requestPath", 5, notes, "Top pages")
        referrers = breakdown(tag, "refererHost", 6, notes, "Referrers")
        [pages, referrers, notes.empty? ? nil : "#{notes.join(' and ')} unavailable."]
      end

      def breakdown(tag, dimension, limit, notes, label)
        field = "rows: #{DATASET}(filter: {#{window(@today - 1)}}, limit: #{limit}, orderBy: [count_DESC]) " \
                "{ count dimensions { #{dimension} } }"
        Array(query(field, tag)["rows"]).filter_map do |row|
          value = row.dig("dimensions", dimension).to_s
          [value, row["count"].to_i] unless value.empty?
        end.first(5)
      rescue Error, Http::Error, KeyError => e
        Circadex.logger.warn("analytics #{label.downcase}: #{e.message}")
        notes << label
        []
      end

      def query(fields, tag)
        gql = "query($account: String!, $tag: String!) { viewer { accounts(filter: {accountTag: $account}) { #{fields} } } }"
        data = @client.graphql(gql, { account: @client.account_id, tag: tag })
        data.fetch("viewer").fetch("accounts").first || raise(KeyError, "no account in response")
      end

      def window(date)
        start = Time.new(date.year, date.month, date.day)
        finish = Time.new((date + 1).year, (date + 1).month, (date + 1).day)
        "siteTag: $tag, datetime_geq: \"#{start.utc.iso8601}\", datetime_lt: \"#{finish.utc.iso8601}\""
      end
    end
  end
end
