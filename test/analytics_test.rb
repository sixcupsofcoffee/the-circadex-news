require "test_helper"

class AnalyticsTest < Minitest::Test
  NOW = Time.new(2026, 10, 24, 6, 0, 0)
  SITES_URL = "https://api.cloudflare.com/client/v4/accounts/acct123/rum/site_info/list".freeze
  GRAPHQL_URL = "https://api.cloudflare.com/client/v4/graphql".freeze

  def sites_body(items = nil)
    items ||= [
      { "site_tag" => "tag-blog-0000000000", "ruleset" => { "zone_name" => "blog.example.test" } },
      { "site_tag" => "tag-shop-0000000000", "host" => "shop.example.test" },
      { "ruleset" => { "zone_name" => "no-tag.example.test" } }
    ]
    JSON.generate("success" => true, "result" => items, "result_info" => { "page" => 1, "per_page" => 50 })
  end

  # Returns canned rows depending on which fields the query asks for.
  def graphql_responder(overrides = {})
    lambda do |payload|
      query = payload[:query]
      account =
        if query.include?("d0:")
          (0..7).to_h { |i| ["d#{i}", [{ "count" => [1200, 1000, 900, 1100, 1000, 950, 1050, 1000][i], "sum" => { "visits" => 400 - i * 10 } }]] }
        elsif query.include?("requestPath")
          { "rows" => [{ "count" => 300, "dimensions" => { "requestPath" => "/" } }, { "count" => 120, "dimensions" => { "requestPath" => "/post" } }] }
        else
          { "rows" => [{ "count" => 90, "dimensions" => { "refererHost" => "" } }, { "count" => 80, "dimensions" => { "refererHost" => "news.ycombinator.com" } }] }
        end
      account = overrides.fetch(:account, account)
      JSON.generate(overrides[:body] || { "data" => { "viewer" => { "accounts" => [account] } }, "errors" => nil })
    end
  end

  def client(http)
    Circadex::Sources::CloudflareClient.new(account_id: "acct123", token: "tok", http: http)
  end

  def digest(config = {}, overrides = {})
    http = FakeHttp.new(SITES_URL => sites_body, GRAPHQL_URL => graphql_responder(overrides))
    [Circadex::Sources::Analytics.new(config, client: client(http), now: NOW).digest, http]
  end

  def test_discovers_sites_and_names_them
    d, = digest

    assert_equal ["blog.example.test", "shop.example.test"], d.sites.map(&:name)
    assert_equal Date.new(2026, 10, 23), d.date
  end

  def test_totals_comparisons_and_breakdowns
    site = digest.first.sites.first

    assert_equal 1200, site.views
    assert_equal 400, site.visits
    assert_equal 1000, site.prior_views
    assert_in_delta 1000.0, site.average_views, 0.1
    assert_equal 20, Circadex::Sources::Analytics.change(site.views, site.prior_views)
    assert_equal [["/", 300], ["/post", 120]], site.pages
    assert_equal [["news.ycombinator.com", 80]], site.referrers
    assert_nil site.notice
  end

  def test_configured_sites_skip_discovery
    d, http = digest("sites" => [{ "name" => "mine.test", "tag" => "abc" }])

    assert_equal ["mine.test"], d.sites.map(&:name)
    refute(http.requests.any? { |u| u.start_with?(SITES_URL) })
  end

  def test_queries_use_local_day_windows_and_variables
    seen = []
    http = FakeHttp.new(SITES_URL => sites_body, GRAPHQL_URL => ->(payload) { seen << payload; graphql_responder.call(payload) })
    Circadex::Sources::Analytics.new({}, client: client(http), now: NOW).digest

    totals = seen.find { |p| p[:query].include?("d0:") }
    assert_equal({ account: "acct123", tag: "tag-blog-0000000000" }, totals[:variables])
    assert_includes totals[:query], "datetime_geq: \"#{Time.new(2026, 10, 23).utc.iso8601}\""
    assert_includes totals[:query], "datetime_lt: \"#{Time.new(2026, 10, 24).utc.iso8601}\""
  end

  def test_graphql_error_becomes_site_notice_not_crash
    d, = digest({}, body: { "data" => nil, "errors" => [{ "message" => "not authorized" }] })

    assert_equal 2, d.sites.size
    assert_nil d.sites.first.views
    assert_equal "Analytics unavailable for this site.", d.sites.first.notice
  end

  def test_breakdown_failure_keeps_totals
    responder = lambda do |payload|
      raise Circadex::Http::Error, "boom" unless payload[:query].include?("d0:")

      graphql_responder.call(payload)
    end
    http = FakeHttp.new(SITES_URL => sites_body, GRAPHQL_URL => responder)
    site = Circadex::Sources::Analytics.new({}, client: client(http), now: NOW).digest.sites.first

    assert_equal 1200, site.views
    assert_empty site.pages
    assert_equal "Top pages and Referrers unavailable.", site.notice
  end

  def test_change_handles_zero_baseline
    assert_nil Circadex::Sources::Analytics.change(10, 0)
    assert_equal(-50, Circadex::Sources::Analytics.change(50, 100))
  end

  def test_api_failure_when_listing_sites_raises
    http = FakeHttp.new(SITES_URL => JSON.generate("success" => false, "errors" => [{ "message" => "Authentication error" }]))

    error = assert_raises(Circadex::Sources::Analytics::Error) { client(http).sites }
    assert_match(/Authentication error/, error.message)
  end

  def test_token_is_sent_only_as_header_never_in_url_or_errors
    http = FakeHttp.new(SITES_URL => "not json")

    error = assert_raises(Circadex::Sources::Analytics::Error) { client(http).sites }
    refute_includes error.message, "tok"
    refute(http.requests.any? { |u| u.include?("tok") })
  end
end
