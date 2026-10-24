require "net/http"
require "uri"

module Circadex
  module Http
    class Error < StandardError; end

    USER_AGENT = "circadex-news/#{VERSION} (personal newspaper builder)".freeze

    module_function

    def get(url, headers: {}, redirects: 5, timeout: 20)
      raise Error, "too many redirects for #{url}" if redirects.negative?

      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = http.read_timeout = timeout

      response = http.request(Net::HTTP::Get.new(uri.request_uri, { "User-Agent" => USER_AGENT }.merge(headers)))
      case response
      when Net::HTTPSuccess
        response.body.to_s.dup.force_encoding(Encoding::UTF_8).scrub
      when Net::HTTPRedirection
        get(URI.join(url, response["location"]).to_s, headers: headers, redirects: redirects - 1, timeout: timeout)
      else
        raise Error, "GET #{url} returned #{response.code}"
      end
    rescue SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError => e
      raise Error, "GET #{url} failed: #{e.message}"
    end
  end
end
