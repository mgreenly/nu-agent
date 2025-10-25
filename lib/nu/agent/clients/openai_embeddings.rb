# frozen_string_literal: true

module Nu
  module Agent
    module Clients
      class OpenAIEmbeddings
        # Explicit imports for external dependencies
        OpenAIGem = ::OpenAI
        ApiKey = ::Nu::Agent::ApiKey
        Error = ::Nu::Agent::Error

        # Only support text-embedding-3-small
        MODEL = 'text-embedding-3-small'
        PRICING_PER_MILLION_TOKENS = 0.020

        def initialize(api_key: nil)
          load_api_key(api_key)
          @client = OpenAIGem::Client.new(access_token: @api_key.value)
        end

        def name
          "OpenAI Embeddings (text-embedding-3-small)"
        end

        # Generate embeddings for text input
        # @param text [String, Array<String>] Single text or array of texts to embed
        # @return [Hash] Response with embeddings, tokens, and cost
        def generate_embedding(text)
          input = text.is_a?(Array) ? text : [text]

          begin
            response = @client.embeddings(
              parameters: {
                model: MODEL,
                input: input
              }
            )
          rescue Faraday::Error => e
            return format_error_response(e)
          end

          # Extract embeddings
          embeddings = response['data'].map { |d| d['embedding'] }

          # Get usage information
          total_tokens = response.dig('usage', 'total_tokens') || 0

          # Calculate cost
          cost = (total_tokens / 1_000_000.0) * PRICING_PER_MILLION_TOKENS

          {
            'embeddings' => text.is_a?(Array) ? embeddings : embeddings.first,
            'model' => MODEL,
            'tokens' => total_tokens,
            'spend' => cost
          }
        end

        private

        def format_error_response(error)
          status = error.response&.dig(:status) || 'unknown'
          headers = error.response&.dig(:headers) || {}

          # Try multiple ways to get the body
          body = error.response&.dig(:body) ||
                 error.response_body ||
                 error.response&.[](:body) ||
                 error.message

          {
            'error' => {
              'status' => status,
              'headers' => headers.to_h,
              'body' => body,
              'raw_error' => error.inspect
            },
            'embeddings' => nil,
            'model' => MODEL
          }
        end

        def load_api_key(provided_key)
          if provided_key
            @api_key = ApiKey.new(provided_key)
          else
            # Use the same API key as the regular OpenAI client
            api_key_path = File.join(Dir.home, '.secrets', 'OPENAI_API_KEY')

            if File.exist?(api_key_path)
              key_content = File.read(api_key_path).strip
              @api_key = ApiKey.new(key_content)
            else
              raise Error, "API key not found at #{api_key_path}"
            end
          end
        rescue => e
          raise Error, "Error loading API key: #{e.message}"
        end
      end
    end
  end
end
