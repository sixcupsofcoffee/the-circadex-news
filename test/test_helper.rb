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
    body = @responses.find { |pattern, _| url.start_with?(pattern) }&.last
    raise Circadex::Http::Error, "GET #{url} returned 404" if body.nil?

    body
  end
end
