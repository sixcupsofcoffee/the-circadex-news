module Circadex
  # Gathers every source into an Edition. A failing source never stops the paper;
  # it is noted at the back instead.
  class Builder
    def initialize(config, http: Http, mail_client: nil, analytics_client: nil, now: Time.now)
      @config = config
      @http = http
      @mail_client = mail_client
      @analytics_client = analytics_client
      @now = now
    end

    def build(date)
      notices = []
      forecast = guard("Weather", notices) do
        Sources::Weather.new(@config["weather"], timezone: @config["timezone"], http: @http).fetch
      end
      sections = guard("News", notices) do
        Sources::News.new(@config["news"], http: @http).sections
      end || []

      mail = guard("Mail", notices) { mail_digest } if enabled?("Mail", "mail")

      analytics = guard("Analytics", notices) { analytics_digest } if enabled?("Analytics", "analytics")

      comics = guard("Comics", notices) { Sources::Comics.new(@config["comics"], http: @http).digest(date) } if enabled?("Comics", "comics")

      crossword = guard("Crossword", notices) { Sources::GuardianCrossword.new(@config["crossword"], http: @http).fetch } if enabled?("Crossword", "crossword")

      Edition.new(date: date, forecast: forecast, sections: sections, mail: mail, analytics: analytics, comics: comics, crossword: crossword,
                  notices: notices)
    end

    private

    def enabled?(label, key)
      return true if @config[key] && @config[key]["enabled"]

      Circadex.logger.info("#{label}: skipped (not enabled in config)")
      false
    end

    def analytics_digest
      Sources::Analytics.new(@config["analytics"], client: @analytics_client || cloudflare_client, now: @now).digest
    end

    def cloudflare_client
      account_id = Secrets.fetch("CLOUDFLARE_ACCOUNT_ID")
      unless account_id.match?(/\A[0-9a-f]{32}\z/i)
        raise Config::Error,
              "CLOUDFLARE_ACCOUNT_ID should be the 32-character account ID from the Cloudflare dashboard " \
              "(it may hold an API token instead)"
      end

      Sources::CloudflareClient.new(account_id: account_id, token: Secrets.fetch("CLOUDFLARE_TOKEN"), http: @http)
    end

    def mail_digest
      Sources::Inbox.new(@config["mail"], client: @mail_client || imap_client, now: @now).digest
    end

    def imap_client
      mail = @config["mail"]
      Sources::ImapClient.new(
        host: mail["host"] || "imap.mail.me.com", port: mail["port"] || 993,
        username: Secrets.fetch("ICLOUD_USER"), password: Secrets.fetch("ICLOUD_PASSWORD"),
        mailbox: mail["mailbox"] || "INBOX"
      )
    end

    def guard(name, notices)
      result = yield
      Circadex.logger.info("#{name}: ok")
      result
    rescue StandardError => e
      Circadex.logger.error("#{name}: #{e.class}: #{e.message}")
      notices << "#{name} could not be loaded today (#{e.message})."
      nil
    end
  end
end
