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
      # - 4: + Tool list (names with first sentence)
      # - 5: + Tool definitions (complete schemas)
      # - 6: + Complete message history
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
          @console.puts("")
          @console.puts("\e[90m--- LLM Request ---\e[0m")

          output = build_output_hash(internal_request)
          display_yaml_content(output)
        end

        private

        # Builds the output hash based on verbosity level.
        #
        # @param internal_request [Hash] The internal request format
        # @return [Hash] The filtered output hash for display
        def build_output_hash(internal_request)
          output = {}

          # Verbosity level 1: Show only final user message
          add_final_message(output, internal_request)

          # Verbosity level 2: Add system_prompt
          output[:system_prompt] = internal_request[:system_prompt] if should_output?(2)

          # Verbosity level 3: Add rag_content from metadata
          add_rag_content(output, internal_request) if should_output?(3)

          # Verbosity level 4-5: Add tools (condensed or full)
          add_tools(output, internal_request)

          # Verbosity level 6: Add full message history
          add_full_messages(output, internal_request) if should_output?(6)

          output
        end

        # Adds the final message to the output hash.
        #
        # @param output [Hash] The output hash being built
        # @param internal_request [Hash] The internal request format
        # @return [void]
        def add_final_message(output, internal_request)
          final_message = internal_request[:messages]&.last
          output[:final_message] = final_message if final_message
        end

        # Adds RAG content to the output hash if present.
        #
        # @param output [Hash] The output hash being built
        # @param internal_request [Hash] The internal request format
        # @return [void]
        def add_rag_content(output, internal_request)
          rag_content = internal_request.dig(:metadata, :rag_content)
          output[:rag_content] = rag_content if rag_content
        end

        # Adds tools to the output hash (condensed at level 4, full at level 5).
        #
        # @param output [Hash] The output hash being built
        # @param internal_request [Hash] The internal request format
        # @return [void]
        def add_tools(output, internal_request)
          return unless internal_request[:tools]

          output[:tools] = condense_tools(internal_request[:tools]) if should_output?(4)
          output[:tools] = internal_request[:tools] if should_output?(5)
        end

        # Adds full message history to the output hash.
        #
        # @param output [Hash] The output hash being built
        # @param internal_request [Hash] The internal request format
        # @return [void]
        def add_full_messages(output, internal_request)
          output[:messages] = internal_request[:messages]
          output.delete(:final_message) # Remove final_message when showing all
        end

        # Checks if output should be displayed for the given verbosity level.
        #
        # @param level [Integer] The verbosity level to check (1-6)
        # @return [Boolean] true if the current verbosity level is >= the requested level
        def should_output?(level)
          return false unless @application

          SubsystemDebugger.should_output?(@application, "llm", level)
        end

        # Creates a condensed version of the tools array showing only names and first sentences.
        #
        # @param tools [Array<Hash>] The full tool definitions
        # @return [Hash] A hash mapping tool names to their first sentence descriptions
        def condense_tools(tools)
          tools.each_with_object({}) do |tool, condensed|
            name = tool[:name] || tool["name"]
            description = tool[:description] || tool["description"]
            first_sentence = extract_first_sentence(description)
            condensed[name] = first_sentence if name
          end
        end

        # Extracts the first sentence from a description string.
        #
        # @param description [String] The full description text
        # @return [String] The first sentence (ending with period, question mark, or exclamation point)
        def extract_first_sentence(description)
          return "" unless description

          # Match text up to and including the first sentence-ending punctuation
          match = description.match(/^.*?[.!?]/)
          match ? match[0] : description
        end

        # Displays the data as YAML with gray coloring.
        #
        # @param data [Hash] The data to format and display as YAML
        # @return [void]
        def display_yaml_content(data)
          require "yaml"
          yaml_output = YAML.dump(data)
          # Remove YAML document marker "---\n" from the start
          yaml_output = yaml_output.sub(/\A---\n/, "")
          # Output each line in gray
          yaml_output.each_line do |line|
            @console.puts("\e[90m#{line.chomp}\e[0m")
          end
        end
      end
    end
  end
end
