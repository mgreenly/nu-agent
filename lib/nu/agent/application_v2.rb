# frozen_string_literal: true

module Nu
  module Agent
    class ApplicationV2
      attr_reader :client, :history, :formatter, :conversation_id

      def initialize(options:)
        $stdout.sync = true
        @options = options
        @client = create_client(options.llm)
        @history = History.new
        @formatter = Formatter.new(history: @history)
        @conversation_id = @history.create_conversation
        @active_threads = []
      end

      def run
        setup_signal_handlers
        print_welcome
        repl
        print_goodbye
      ensure
        # Wait for any active threads to complete
        @active_threads.each(&:join)
        @history.close if @history
      end

      def process_input(input)
        # Handle commands
        if input.start_with?('/')
          return handle_command(input)
        end

        # Add user message to history
        @history.add_message(
          conversation_id: @conversation_id,
          actor: 'user',
          role: 'user',
          content: input
        )

        # Increment workers BEFORE spawning thread
        @history.increment_workers

        # Process in a thread
        thread = Thread.new do
          begin
            chat_loop
          ensure
            @history.decrement_workers
          end
        end

        @active_threads << thread

        # Wait for completion and display
        @formatter.wait_for_completion(conversation_id: @conversation_id)

        # Remove completed thread
        @active_threads.delete(thread)

        :continue
      end

      private

      def chat_loop
        # Get messages from history
        messages = @history.messages(conversation_id: @conversation_id)

        # Call LLM
        response = @client.send_message(messages: messages)

        # Save assistant response
        @history.add_message(
          conversation_id: @conversation_id,
          actor: 'orchestrator',
          role: 'assistant',
          content: response[:content],
          model: response[:model],
          tokens_input: response[:tokens][:input],
          tokens_output: response[:tokens][:output]
        )
      end

      def repl
        loop do
          print "\n\n> "
          input = gets

          break if input.nil?

          input = input.strip
          next if input.empty?

          result = process_input(input)
          break if result == :exit
        end
      end

      def handle_command(input)
        case input.downcase
        when '/exit'
          :exit
        when '/reset'
          @conversation_id = @history.create_conversation
          puts "Conversation reset"
          :continue
        when '/help'
          print_help
          :continue
        else
          puts "Unknown command: #{input}"
          :continue
        end
      end

      def print_help
        puts "\nAvailable commands:"
        puts "  /exit   - Exit the REPL"
        puts "  /help   - Show this help message"
        puts "  /reset  - Start a new conversation"
      end

      def setup_signal_handlers
        Signal.trap("INT") do
          print_goodbye
          @active_threads.each(&:join) if @active_threads
          @history.close if @history
          exit(0)
        end
      end

      def print_welcome
        puts "Nu Agent v2 REPL"
        puts "Using: #{@client.name} (#{@client.model})"
        puts "Type your prompts below. Press Ctrl-C, Ctrl-D, or /exit to quit."
        puts "Type /help for available commands"
        puts "=" * 60
      end

      def print_goodbye
        puts "\n\nGoodbye!"
      end

      def create_client(client_name)
        case client_name.downcase
        when 'claude', 'anthropic'
          AnthropicClient.new
        when 'gemini', 'google'
          GoogleClient.new
        else
          raise Error, "Unknown client: #{client_name}. Use 'claude', 'anthropic', 'gemini', or 'google'."
        end
      end
    end
  end
end
