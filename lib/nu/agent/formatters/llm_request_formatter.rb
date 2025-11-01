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

          # Build the output hash based on verbosity level
          output = {}

          # Verbosity level 1: Show only final user message
          final_message = internal_request[:messages]&.last
          output[:final_message] = final_message if final_message

          # Verbosity level 2: Add system_prompt
          output[:system_prompt] = internal_request[:system_prompt] if should_output?(2)

          # Verbosity level 3: Add rag_content from metadata (only if not nil)
          if should_output?(3)
            rag_content = internal_request.dig(:metadata, :rag_content)
            output[:rag_content] = rag_content if rag_content
          end

          # Verbosity level 4: Add tools
          output[:tools] = internal_request[:tools] if should_output?(4)

          # Verbosity level 5: Add full message history
          if should_output?(5)
            output[:messages] = internal_request[:messages]
            # Remove final_message since we're showing all messages
            output.delete(:final_message)
          end

          display_yaml_content(output)
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
      end
    end
  end
end
