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

        def execute(arguments:, history:, context:)
          query = arguments[:query] || arguments["query"]
          num_results = arguments[:num_results] || arguments["num_results"] || 5

          # Validate required parameters
          if query.nil? || query.empty?
            return {
              error: "query is required",
              results: []
            }
          end

          # Validate num_results range
          num_results = [[num_results.to_i, 1].max, 10].min

          begin
            # Read credentials from file
            credentials = load_credentials
            unless credentials
              return {
                error: "Google Search API credentials not found at #{credentials_path}",
                results: []
              }
            end

            api_key, cse_id = credentials

            # Build API request URL
            base_url = "https://www.googleapis.com/customsearch/v1"
            params = {
              key: api_key,
              cx: cse_id,
              q: query,
              num: num_results
            }

            uri = URI(base_url)
            uri.query = URI.encode_www_form(params)

            # Make HTTP request
            response = Net::HTTP.get_response(uri)

            unless response.is_a?(Net::HTTPSuccess)
              error_message = "HTTP #{response.code}: #{response.message}"

              # Try to parse error details from response body
              begin
                error_body = JSON.parse(response.body)
                if error_body["error"] && error_body["error"]["message"]
                  error_message += " - #{error_body['error']['message']}"
                end
              rescue JSON::ParserError
                # Ignore JSON parsing errors for error responses
              end

              return {
                error: error_message,
                results: []
              }
            end

            # Parse JSON response
            data = JSON.parse(response.body)

            # Extract search results
            items = data["items"] || []
            results = items.map do |item|
              {
                title: item["title"],
                url: item["link"],
                snippet: item["snippet"]
              }
            end

            # Extract total results estimate
            total_results = data.dig("searchInformation", "formattedTotalResults")

            {
              query: query,
              total_results: total_results,
              results: results,
              count: results.length
            }
          rescue JSON::ParserError => e
            {
              error: "Failed to parse API response: #{e.message}",
              results: []
            }
          rescue StandardError => e
            {
              error: "Search failed: #{e.message}",
              results: []
            }
          end
        end

        private

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
