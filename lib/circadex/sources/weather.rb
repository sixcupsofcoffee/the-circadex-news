module Circadex
  module Sources
    class Weather
      ENDPOINT = "https://api.open-meteo.com/v1/forecast".freeze

      # WMO weather interpretation codes, as used by Open-Meteo.
      CODES = {
        0 => "Clear", 1 => "Mostly clear", 2 => "Partly cloudy", 3 => "Overcast",
        45 => "Fog", 48 => "Freezing fog",
        51 => "Light drizzle", 53 => "Drizzle", 55 => "Heavy drizzle",
        56 => "Freezing drizzle", 57 => "Freezing drizzle",
        61 => "Light rain", 63 => "Rain", 65 => "Heavy rain",
        66 => "Freezing rain", 67 => "Freezing rain",
        71 => "Light snow", 73 => "Snow", 75 => "Heavy snow", 77 => "Snow grains",
        80 => "Light showers", 81 => "Showers", 82 => "Heavy showers",
        85 => "Snow showers", 86 => "Heavy snow showers",
        95 => "Thunderstorms", 96 => "Thunderstorms with hail", 99 => "Thunderstorms with hail"
      }.freeze

      def initialize(config, timezone:, http: Http)
        @config = config
        @timezone = timezone
        @http = http
      end

      def fetch
        query = URI.encode_www_form(
          latitude: @config["latitude"],
          longitude: @config["longitude"],
          daily: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max",
          temperature_unit: "fahrenheit",
          timezone: @timezone,
          forecast_days: 6
        )
        parse(@http.get("#{ENDPOINT}?#{query}"))
      end

      def parse(body)
        daily = JSON.parse(body).fetch("daily")
        days = daily["time"].each_index.map do |i|
          Day.new(
            date: Date.parse(daily["time"][i]),
            high: daily["temperature_2m_max"][i]&.round,
            low: daily["temperature_2m_min"][i]&.round,
            summary: CODES.fetch(daily["weather_code"][i], "Unsettled"),
            code: daily["weather_code"][i],
            precip: daily["precipitation_probability_max"][i]
          )
        end
        raise Http::Error, "forecast response had no days" if days.empty?

        Forecast.new(location: @config["location_name"], today: days.first, upcoming: days.drop(1).first(5))
      rescue JSON::ParserError, KeyError => e
        raise Http::Error, "unreadable forecast response: #{e.message}"
      end
    end
  end
end
