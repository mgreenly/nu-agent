# frozen_string_literal: true

require_relative "../subsystem_debugger"

module Nu
  module Agent
    module Formatters
      class LlmRequestFormatter
        def initialize(console:, application:)
          @console = console
          @application = application
        end

        def display_yaml(internal_request)
          # Verbosity level 0 displays nothing (early return)
          return unless should_output?(1)

          # Display YAML formatted request based on verbosity level
          @console.puts("\e[90m--- LLM Request ---\e[0m")

          # Verbosity level 1: Show only final user message
          final_message = internal_request[:messages]&.last
          display_yaml_content({ final_message: final_message }) if final_message

          # TODO: Implement verbosity levels 2-5 in Task 3.3
        end

        def display(messages, tools = nil, markdown_document = nil)
          # Only show LLM request at verbosity level 3+
          return unless should_output?(3)

          display_tools(tools) if should_output?(4) && tools && !tools.empty?
          display_history(messages, markdown_document)
          display_markdown_document(markdown_document) if markdown_document
        end

        private

        def should_output?(level)
          return false unless @application

          SubsystemDebugger.should_output?(@application, "llm", level)
        end

        def display_yaml_content(data)
          require "yaml"
          yaml_output = YAML.dump(data)
          # Output each line in gray
          yaml_output.each_line do |line|
            @console.puts("\e[90m#{line.chomp}\e[0m")
          end
        end

        def display_tools(tools)
          @console.puts("")
          @console.puts("\e[90m--- #{tools.length} Tools Offered ---\e[0m")
          tools.each do |tool|
            name = extract_tool_name(tool)
            @console.puts("\e[90m  - #{name}\e[0m")
          end
        end

        def extract_tool_name(tool)
          # Handle different tool formats (Anthropic, Google, OpenAI)
          tool[:name] || tool["name"] || # Anthropic/Google format
            tool.dig(:function, :name) || tool.dig("function", "name") # OpenAI format
        end

        def display_history(messages, markdown_document)
          # Separate history from markdown document
          # The markdown document is always the last message (if present)
          history_messages = markdown_document ? messages[0...-1] : messages

          # Show conversation history (unredacted messages)
          return if history_messages.empty?

          @console.puts("\e[90m--- Conversation History (#{history_messages.length} unredacted message(s)) ---\e[0m")
          history_messages.each_with_index do |msg, i|
            display_message_info(msg, i)
          end
        end

        def display_message_info(msg, index)
          @console.puts("\e[90m  Message #{index + 1} (role: #{msg['role']})\e[0m")

          display_message_content(msg["content"]) if msg["content"]
          display_tool_calls_info(msg["tool_calls"]) if msg["tool_calls"]
          display_tool_result_info(msg["tool_result"]) if msg["tool_result"]
        end

        def display_message_content(content)
          content_preview = content.to_s[0...200]
          @console.puts("\e[90m  #{content_preview}\e[0m")
          return unless content.to_s.length > 200

          @console.puts("\e[90m  ... (#{content.to_s.length} chars total)\e[0m")
        end

        def display_tool_calls_info(tool_calls)
          @console.puts("\e[90m  [Contains #{tool_calls.length} tool call(s)]\e[0m")
        end

        def display_tool_result_info(tool_result)
          @console.puts("\e[90m  [Tool result for: #{tool_result['name']}]\e[0m")
        end

        def display_markdown_document(markdown_document)
          @console.puts("")
          @console.puts("\e[90m--- Exchange Content ---\e[0m")

          # Show first 500 chars of markdown document
          preview = markdown_document[0...500]
          @console.puts("\e[90m#{preview}\e[0m")

          @console.puts("\e[90m... (#{markdown_document.length} chars total)\e[0m") if markdown_document.length > 500
          @console.puts("\e[90m--- Exchange Content ---\e[0m")
        end
      end
    end
  end
end
