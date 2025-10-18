# frozen_string_literal: true

module Nu
  module Agent
    class Application
      attr_reader :llm

      def initialize(options:)
        @options = options
        @llm = create_llm(options.llm)
      end

      def run
        setup_signal_handlers
        print_welcome
        repl
        print_goodbye
      end

      private

      def repl
        loop do
          print "\n> "
          input = gets

          break if input.nil?

          input = input.strip
          next if input.empty?

          result = Command.new(input, llm).execute
          break if result == :exit
          next if result == :continue

          puts llm.response(input)
        end
      end

      def setup_signal_handlers
        Signal.trap("INT") do
          print_goodbye
          exit(0)
        end
      end

      def print_welcome
        puts "Nu Agent REPL"
        puts "Using: #{llm.name} (#{llm.model})"
        puts "Type your prompts below. Press Ctrl-C, Ctrl-D, or /exit to quit."
        puts "Type /help for available commands"
        puts "=" * 60
      end

      def print_goodbye
        puts "\n\nGoodbye!"
      end

      def create_llm(llm_name)
        case llm_name.downcase
        when 'claude'
          ClaudeClient.new(options: @options)
        when 'gemini'
          GeminiClient.new(options: @options)
        else
          raise Error, "Unknown LLM: #{llm_name}. Use 'claude' or 'gemini'."
        end
      end
    end
  end
end
