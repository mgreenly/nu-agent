# frozen_string_literal: true

require_relative "../subsystem_debugger"

module Nu
  module Agent
    module Formatters
      # Formats and displays LLM requests in YAML format with verbosity-based filtering.
      #
      # This formatter takes an internal LLM request format and displays it to the
      # console in YAML format. The amount of information displayed is controlled by
      # the verbosity level configured in the application's debug settings.
      #
      # Verbosity levels:
      # - 0: Nothing displayed (silent mode)
      # - 1: Final user message only
      # - 2: + System prompt
      # - 3: + RAG content (if present)
      # - 4: + Tool definitions
      # - 5: + Complete message history
      #
      # The internal request sent to the LLM is always complete regardless of
      # verbosity level - verbosity only controls what is displayed for debugging.
      #
      # @example Using the formatter
      #   formatter = LlmRequestFormatter.new(console: $stdout, application: app)
      #   formatter.display_yaml(internal_request)
      #
      # @see Nu::Agent::SubsystemDebugger
      # @see Nu::Agent::LlmRequestBuilder
      class LlmRequestFormatter
        # Initializes a new LlmRequestFormatter.
        #
        # @param console [IO] The output stream for displaying formatted requests (e.g., $stdout)
        # @param application [Nu::Agent::Application] The application object for accessing debug settings
        def initialize(console:, application:)
          @console = console
          @application = application
        end

        # Displays the internal request in YAML format based on verbosity level.
        #
        # The method checks the configured verbosity level and displays the
        # appropriate fields from the internal request. All output is colored
        # in gray (ANSI code \e[90m) for visual distinction.
        #
        # @param internal_request [Hash] The internal request format from LlmRequestBuilder
        # @option internal_request [String] :system_prompt System instructions
        # @option internal_request [Array<Hash>] :messages Message history
        # @option internal_request [Array<Hash>] :tools Tool definitions
        # @option internal_request [Hash] :metadata Additional metadata including RAG content
        # @return [void]
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

        # Checks if output should be displayed for the given verbosity level.
        #
        # @param level [Integer] The verbosity level to check (1-5)
        # @return [Boolean] true if the current verbosity level is >= the requested level
        def should_output?(level)
          return false unless @application

          SubsystemDebugger.should_output?(@application, "llm", level)
        end

        # Displays the data as YAML with gray coloring.
        #
        # @param data [Hash] The data to format and display as YAML
        # @return [void]
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
