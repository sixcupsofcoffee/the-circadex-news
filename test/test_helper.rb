$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "circadex"

Circadex.logger.level = Logger::FATAL

module Fixtures
  def fixture(name)
    File.read(File.expand_path("fixtures/#{name}", __dir__))
  end
end

# Stands in for Circadex::Http: maps URLs to bodies, raises for anything else.
class FakeHttp
  attr_reader :requests

  def initialize(responses)
    @responses = responses
    @requests = []
  end

  def get(url, **)
    @requests << url
    lookup(url)
  end

  def post_json(url, payload, **)
    @requests << url
    lookup(url, payload)
  end

  private

  def lookup(url, payload = nil)
    body = @responses.find { |pattern, _| url.start_with?(pattern) }&.last
    raise Circadex::Http::Error, "#{url} returned 404" if body.nil?

    body.respond_to?(:call) ? body.call(payload) : body
  end
end
