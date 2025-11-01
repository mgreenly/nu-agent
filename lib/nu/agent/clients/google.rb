# frozen_string_literal: true

module Nu
  module Agent
    module Clients
      class Google
        # Explicit imports for external dependencies
        Gemini = ::Gemini
        ApiKey = ::Nu::Agent::ApiKey
        Error = ::Nu::Agent::Error

        SYSTEM_PROMPT = <<~PROMPT
          Today is {{DATE}}.

          Format all responses in raw text, do not use markdown.

          If you can determine the answer to a question on your own, use your tools to find it instead of asking.

          Use execute_bash for shell commands and execute_python for Python scripts.

          These are your only tools to execute processes on the host.

          You can use your database tools to access memories from before the current conversation.

          You can use your tools to write scripts and you have access to the internet.

          # Pseudonyms
          - "project" can mean "the current directory"
        PROMPT

        # Default model (cheapest option)
        DEFAULT_MODEL = "gemini-2.5-flash-lite"

        # Model configurations (verified 2025-10-21)
        MODELS = {
          "gemini-2.5-flash-lite" => {
            display_name: "Gemini 2.5 Flash Lite",
            max_context: 1_048_576,
            pricing: { input: 0.10, output: 0.40 }
          },
          "gemini-2.5-flash" => {
            display_name: "Gemini 2.5 Flash",
            max_context: 1_048_576,
            pricing: { input: 0.30, output: 2.50 }
          },
          "gemini-2.5-pro" => {
            display_name: "Gemini 2.5 Pro",
            max_context: 1_048_576,
            pricing: { input: 1.25, output: 10.00 }
          }
        }.freeze

        def initialize(api_key: nil, model: nil)
          load_api_key(api_key)
          @model = model || "gemini-2.5-flash"
          @client = Gemini.new(
            credentials: {
              service: "generative-language-api",
              api_key: @api_key.value,
              version: "v1beta"
            },
            options: { model: @model, server_sent_events: false }
          )
        end

        def send_message(messages:, system_prompt: SYSTEM_PROMPT, tools: nil)
          processed_prompt = replace_date_placeholder(system_prompt)
          formatted_messages = format_messages(messages, system_prompt: processed_prompt)
          request = build_request(formatted_messages, tools)

          begin
            start_time = Time.now
            warn "[DEBUG] API Request starting at #{start_time.strftime('%H:%M:%S.%3N')} (#{name}/#{@model})"

            result = @client.generate_content(request)

            duration = Time.now - start_time
            warn "[DEBUG] API Response received after #{(duration * 1000).round}ms"
          rescue Faraday::Error => e
            duration = Time.now - start_time
            warn "[DEBUG] API Request failed after #{(duration * 1000).round}ms: #{e.message}"
            return format_error_response(e)
          end

          parse_api_response(result)
        end

        def name
          "Google"
        end

        attr_reader :model

        def max_context
          MODELS.dig(@model, :max_context) || MODELS.dig("gemini-2.5-flash", :max_context)
        end

        def format_tools(tool_registry)
          tool_registry.for_google
        end

        def list_models
          {
            provider: "Google",
            models: MODELS.map { |id, info| { id: id, display_name: info[:display_name] } }
          }
        end

        def calculate_cost(input_tokens:, output_tokens:)
          return 0.0 if input_tokens.nil? || output_tokens.nil?

          pricing = MODELS.dig(@model, :pricing) || MODELS.dig("gemini-2.5-flash", :pricing)
          input_cost = (input_tokens / 1_000_000.0) * pricing[:input]
          output_cost = (output_tokens / 1_000_000.0) * pricing[:output]
          input_cost + output_cost
        end

        private

        def build_request(formatted_messages, tools)
          request = { contents: formatted_messages }
          request[:tools] = [{ "functionDeclarations" => tools }] if tools && !tools.empty?
          request
        end

        def parse_api_response(result)
          parts = result.dig("candidates", 0, "content", "parts") || []
          text_content = parts.find { |p| p["text"] }&.dig("text")
          tool_calls = extract_tool_calls(parts)

          input_tokens = result.dig("usageMetadata", "promptTokenCount")
          output_tokens = result.dig("usageMetadata", "candidatesTokenCount")

          {
            "content" => text_content,
            "tool_calls" => tool_calls.empty? ? nil : tool_calls,
            "model" => model,
            "tokens" => {
              "input" => input_tokens,
              "output" => output_tokens
            },
            "spend" => calculate_cost(input_tokens: input_tokens, output_tokens: output_tokens),
            "finish_reason" => result.dig("candidates", 0, "finishReason")
          }
        end

        def extract_tool_calls(parts)
          parts.select { |p| p["functionCall"] }.map do |fc|
            {
              "id" => SecureRandom.uuid, # Gemini doesn't provide IDs, generate one
              "name" => fc["functionCall"]["name"],
              "arguments" => fc["functionCall"]["args"]
            }
          end
        end

        def format_error_response(error)
          status = error.response&.dig(:status) || "unknown"
          headers = error.response&.dig(:headers) || {}

          # Try multiple ways to get the body
          body = error.response&.dig(:body) ||
                 error.response_body ||
                 error.response&.[](:body) ||
                 error.message

          {
            "error" => {
              "status" => status,
              "headers" => headers.to_h,
              "body" => body,
              "raw_error" => error.inspect # Add for debugging
            },
            "content" => "API Error: #{status}",
            "model" => @model
          }
        end

        def load_api_key(provided_key)
          if provided_key
            @api_key = ApiKey.new(provided_key)
          else
            api_key_path = File.join(Dir.home, ".secrets", "GEMINI_API_KEY")

            raise Error, "API key not found at #{api_key_path}" unless File.exist?(api_key_path)

            key_content = File.read(api_key_path).strip
            @api_key = ApiKey.new(key_content)

          end
        rescue StandardError => e
          raise Error, "Error loading API key: #{e.message}"
        end

        def replace_date_placeholder(prompt)
          return prompt unless prompt

          current_date = Time.now.strftime("%Y-%m-%d")
          prompt.gsub("{{DATE}}", current_date)
        end

        def format_messages(messages, system_prompt:)
          # Convert from internal format to Gemini format
          # Gemini doesn't have a separate system parameter, so we prepend the system prompt
          # as the first user message
          formatted = []

          formatted << { role: "user", parts: [{ text: system_prompt }] } if system_prompt && !system_prompt.empty?

          messages.each do |msg|
            formatted << format_single_message(msg)
          end

          formatted
        end

        def format_single_message(msg)
          if msg["tool_result"]
            format_tool_result_message(msg)
          elsif msg["tool_calls"]
            format_tool_call_message(msg)
          else
            format_text_message(msg)
          end
        end

        def format_tool_result_message(msg)
          {
            role: "function",
            parts: [{
              functionResponse: {
                name: msg["tool_result"]["name"],
                response: msg["tool_result"]["result"]
              }
            }]
          }
        end

        def format_tool_call_message(msg)
          parts = []
          parts << { text: msg["content"] } if msg["content"] && !msg["content"].empty?

          msg["tool_calls"].each do |tc|
            parts << {
              functionCall: {
                name: tc["name"],
                args: tc["arguments"]
              }
            }
          end

          {
            role: "model",
            parts: parts
          }
        end

        def format_text_message(msg)
          # Translate our domain model to Gemini's format
          # Our 'assistant' becomes 'model', 'tool' becomes 'function'
          role = case msg["role"]
                 when "assistant" then "model"
                 when "tool" then "function"
                 else msg["role"]
                 end

          {
            role: role,
            parts: [{ text: msg["content"] }]
          }
        end
      end
    end
  end
end
