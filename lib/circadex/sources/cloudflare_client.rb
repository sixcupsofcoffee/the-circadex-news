module Circadex
  module Sources
    # Thin Cloudflare API wrapper: lists Web Analytics sites and runs GraphQL queries.
    class CloudflareClient
      API = "https://api.cloudflare.com/client/v4".freeze
      PER_PAGE = 50

      def initialize(account_id:, token:, http: Http)
        @account_id = account_id
        @token = token
        @http = http
      end

      attr_reader :account_id

      def sites
        items = []
        (1..20).each do |page|
          body = parse(@http.get("#{API}/accounts/#{@account_id}/rum/site_info/list?per_page=#{PER_PAGE}&page=#{page}", headers: auth))
          batch = Array(body["result"])
          items.concat(batch)
          break if batch.size < PER_PAGE
        end
        items.filter_map { |item| site_from(item) }
      end

      def graphql(query, variables = {})
        body = parse(@http.post_json("#{API}/graphql", { query: query, variables: variables }, headers: auth))
        errors = Array(body["errors"])
        raise Analytics::Error, "Cloudflare GraphQL error: #{errors.first['message']}" unless errors.empty?

        body.fetch("data")
      end

      private

      def auth
        { "Authorization" => "Bearer #{@token}" }
      end

      def parse(raw)
        body = JSON.parse(raw)
        if body.key?("success") && body["success"] == false
          raise Analytics::Error, "Cloudflare API error: #{Array(body['errors']).first&.dig('message') || 'unknown'}"
        end

        body
      rescue JSON::ParserError
        raise Analytics::Error, "Cloudflare returned an unreadable response"
      end

      def site_from(item)
        tag = item["site_tag"]
        return unless tag

        name = item.dig("ruleset", "zone_name") || item["host"] || "site #{tag[0, 8]}"
        { "tag" => tag, "name" => name }
      end
    end
  end
end
