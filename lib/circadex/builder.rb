module Circadex
  # Gathers every source into an Edition. A failing source never stops the paper;
  # it is noted at the back instead.
  class Builder
    def initialize(config, http: Http, mail_client: nil, now: Time.now)
      @config = config
      @http = http
      @mail_client = mail_client
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

      mail = guard("Mail", notices) { mail_digest } if mail_enabled?

      Edition.new(date: date, forecast: forecast, sections: sections, mail: mail, notices: notices)
    end

    private

    def mail_enabled?
      @config["mail"] && @config["mail"]["enabled"]
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
      yield
    rescue StandardError => e
      Circadex.logger.error("#{name}: #{e.class}: #{e.message}")
      notices << "#{name} could not be loaded today (#{e.message})."
      nil
    end
  end
end
