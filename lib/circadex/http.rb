require "net/http"
require "uri"

module Circadex
  module Http
    class Error < StandardError; end

    USER_AGENT = "circadex-news/#{VERSION} (personal newspaper builder)".freeze

    module_function

    def get(url, headers: {}, redirects: 5, timeout: 20, binary: false)
      raise Error, "too many redirects for #{url}" if redirects.negative?

      uri = URI(url)
      response = perform(uri, Net::HTTP::Get.new(uri.request_uri, { "User-Agent" => USER_AGENT }.merge(headers)), timeout)
      case response
      when Net::HTTPSuccess
        binary ? response.body.to_s.b : decode(response)
      when Net::HTTPRedirection
        get(URI.join(url, response["location"]).to_s, headers: headers, redirects: redirects - 1, timeout: timeout, binary: binary)
      else
        raise Error, "GET #{url} returned #{response.code}"
      end
    end

    def post_json(url, payload, headers: {}, timeout: 20)
      uri = URI(url)
      request = Net::HTTP::Post.new(uri.request_uri, { "User-Agent" => USER_AGENT, "Content-Type" => "application/json" }.merge(headers))
      request.body = JSON.generate(payload)
      response = perform(uri, request, timeout)
      raise Error, "POST #{uri.host}#{uri.path} returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      decode(response)
    end

    def perform(uri, request, timeout)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = http.read_timeout = timeout
      http.request(request)
    rescue SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError => e
      raise Error, "request to #{uri.host} failed: #{e.message}"
    end

    def decode(response)
      response.body.to_s.dup.force_encoding(Encoding::UTF_8).scrub
    end
  end
end
