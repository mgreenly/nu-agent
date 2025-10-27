# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Nu
  module Agent
    module Tools
      class SearchInternet
        def name
          "search_internet"
        end

        def available?
          credentials = load_credentials
          credentials && credentials.length == 2
        end

        def description
          "PREFERRED tool for searching the internet using Google Custom Search API. " \
            "Returns web search results including titles, URLs, and snippets. " \
            "Useful for finding current information, researching topics, looking up documentation, " \
            "or gathering data from the web. " \
            "Results include the most relevant pages matching the search query."
        end

        def parameters
          {
            query: {
              type: "string",
              description: "The search query string",
              required: true
            },
            num_results: {
              type: "integer",
              description: "Number of results to return (1-10, default: 5)",
              required: false
            }
          }
        end

        def execute(arguments:, **)
          query = arguments[:query] || arguments["query"]
          num_results = (arguments[:num_results] || arguments["num_results"] || 5).to_i.clamp(1, 10)

          return error_response("query is required") if query.nil? || query.empty?

          begin
            credentials = load_credentials
            return error_response("Google Search API credentials not found at #{credentials_path}") unless credentials

            response = make_search_request(query, num_results, credentials)
            parse_search_response(response, query)
          rescue JSON::ParserError => e
            error_response("Failed to parse API response: #{e.message}")
          rescue StandardError => e
            error_response("Search failed: #{e.message}")
          end
        end

        private

        def error_response(message)
          { error: message, results: [] }
        end

        def make_search_request(query, num_results, credentials)
          api_key, cse_id = credentials
          uri = build_search_uri(query, num_results, api_key, cse_id)

          response = Net::HTTP.get_response(uri)
          return build_http_error(response) unless response.is_a?(Net::HTTPSuccess)

          response
        end

        def build_search_uri(query, num_results, api_key, cse_id)
          base_url = "https://www.googleapis.com/customsearch/v1"
          params = { key: api_key, cx: cse_id, q: query, num: num_results }

          uri = URI(base_url)
          uri.query = URI.encode_www_form(params)
          uri
        end

        def build_http_error(response)
          error_message = "HTTP #{response.code}: #{response.message}"

          begin
            error_body = JSON.parse(response.body)
            error_message += " - #{error_body['error']['message']}" if error_body.dig("error", "message")
          rescue JSON::ParserError
            # Ignore JSON parsing errors for error responses
          end

          error_response(error_message)
        end

        def parse_search_response(response, query)
          data = JSON.parse(response.body)

          results = (data["items"] || []).map do |item|
            { title: item["title"], url: item["link"], snippet: item["snippet"] }
          end

          {
            query: query,
            total_results: data.dig("searchInformation", "formattedTotalResults"),
            results: results,
            count: results.length
          }
        end

        def credentials_path
          File.join(Dir.home, ".secrets", "GOOGLE_SEARCH_API")
        end

        def load_credentials
          return nil unless File.exist?(credentials_path)
          return nil unless File.readable?(credentials_path)

          lines = File.readlines(credentials_path).map(&:strip).reject(&:empty?)

          return nil if lines.length < 2

          [lines[0], lines[1]] # [api_key, cse_id]
        end
      end
    end
  end
end
