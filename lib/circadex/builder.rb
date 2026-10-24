module Circadex
  # Gathers every source into an Edition. A failing source never stops the paper;
  # it is noted at the back instead.
  class Builder
    def initialize(config, http: Http)
      @config = config
      @http = http
    end

    def build(date)
      notices = []
      forecast = guard("Weather", notices) do
        Sources::Weather.new(@config["weather"], timezone: @config["timezone"], http: @http).fetch
      end
      sections = guard("News", notices) do
        Sources::News.new(@config["news"], http: @http).sections
      end || []

      Edition.new(date: date, forecast: forecast, sections: sections, notices: notices)
    end

    private

    def guard(name, notices)
      yield
    rescue StandardError => e
      Circadex.logger.error("#{name}: #{e.class}: #{e.message}")
      notices << "#{name} could not be loaded today (#{e.message})."
      nil
    end
  end
end
