require "test_helper"

class WeatherTest < Minitest::Test
  include Fixtures

  def weather(http = FakeHttp.new("https://api.open-meteo.com/" => fixture("forecast.json")))
    Circadex::Sources::Weather.new(
      { "latitude" => 41.824, "longitude" => -71.413, "location_name" => "Providence, RI" },
      timezone: "America/New_York", http: http
    )
  end

  def test_parses_today_and_five_days
    forecast = weather.fetch

    assert_equal "Providence, RI", forecast.location
    assert_equal [61, 47, "Partly cloudy", 10, 2], forecast.today.to_a.drop(1)
    assert_equal 5, forecast.upcoming.size
    assert_equal Date.new(2026, 10, 25), forecast.upcoming.first.date
    assert_equal "Thunderstorms", forecast.upcoming.last.summary
    assert_nil forecast.upcoming[3].precip
  end

  def test_requests_fahrenheit_for_the_configured_location
    http = FakeHttp.new("https://api.open-meteo.com/" => fixture("forecast.json"))
    weather(http).fetch

    url = http.requests.first
    assert_includes url, "temperature_unit=fahrenheit"
    assert_includes url, "latitude=41.824"
    assert_includes url, "timezone=America%2FNew_York"
  end

  def test_rejects_unreadable_response
    assert_raises(Circadex::Http::Error) { weather.parse("<html>nope</html>") }
    assert_raises(Circadex::Http::Error) { weather.parse('{"daily":{"time":[]}}') }
  end
end
