# frozen_string_literal: true

module Nu
  module Agent
    class Application
      attr_reader :llm

      def initialize(llm: 'claude')
        @llm = create_llm(llm)
      end

      def run
        setup_signal_handlers
        print_welcome

        loop do
          print "\n> "
          input = gets

          # Handle Ctrl-D (EOF)
          break if input.nil?

          input = input.strip
          next if input.empty?

          # Handle commands
          if input.start_with?('/')
            break if Command.new(input, llm).execute == :exit
            next
          end

          response = llm.chat(prompt: input)
          puts "\n#{response}"
          puts "\nTokens: #{llm.input_tokens} in / #{llm.output_tokens} out / #{llm.total_tokens} total"
        end

        print_goodbye
      end

      private

      def setup_signal_handlers
        # Handle Ctrl-C gracefully
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
          ClaudeClient.new
        when 'gemini'
          GeminiClient.new
        else
          raise Error, "Unknown LLM: #{llm_name}. Use 'claude' or 'gemini'."
        end
      end
    end
  end
end
