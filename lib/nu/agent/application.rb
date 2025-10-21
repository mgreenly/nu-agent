# frozen_string_literal: true

module Nu
  module Agent
    class Application
      attr_reader :client, :history, :formatter, :conversation_id, :session_start_time
      attr_accessor :active_threads

      def initialize(options:)
        $stdout.sync = true
        @session_start_time = Time.now
        @options = options
        @user_actor = ENV['USER'] || 'user'
        @client = ModelFactory.create(options.model)
        @history = History.new
        @conversation_id = @history.create_conversation
        @formatter = Formatter.new(
          history: @history,
          session_start_time: @session_start_time,
          conversation_id: @conversation_id,
          client: @client
        )
        @active_threads = []
      end

      def run
        setup_signal_handlers
        print_welcome
        repl
        print_goodbye
      ensure
        # Wait for any active threads to complete
        active_threads.each(&:join)
        history.close if history
      end

      def process_input(input)
        # Handle commands
        if input.start_with?('/')
          return handle_command(input)
        end

        # Add user message to history
        history.add_message(
          conversation_id: conversation_id,
          actor: @user_actor,
          role: 'user',
          content: input
        )

        # Increment workers BEFORE spawning thread
        history.increment_workers

        # Capture values to pass into thread
        conv_id = conversation_id
        hist = history
        cli = client
        session_start = session_start_time

        # Process in a thread
        thread = Thread.new(conv_id, hist, cli, session_start) do |conversation_id, history, client, session_start_time|
          begin
            chat_loop(
              conversation_id: conversation_id,
              history: history,
              client: client,
              session_start_time: session_start_time
            )
          ensure
            history.decrement_workers
          end
        end

        active_threads << thread

        # Wait for completion and display
        formatter.wait_for_completion(conversation_id: conversation_id)

        # Remove completed thread
        active_threads.delete(thread)

        :continue
      end

      private

      def chat_loop(conversation_id:, history:, client:, session_start_time:)
        tool_registry = ToolRegistry.new

        loop do
          # Get messages from history (only from current session)
          messages = history.messages(conversation_id: conversation_id, since: session_start_time)

          # Get tools formatted for this client
          tools = client.format_tools(tool_registry)

          # Call LLM with tools
          response = client.send_message(messages: messages, tools: tools)

          # If we got tool calls, execute them
          if response['tool_calls']
            # Save assistant message with tool calls
            history.add_message(
              conversation_id: conversation_id,
              actor: 'orchestrator',
              role: 'assistant',
              content: response['content'],
              model: response['model'],
              tokens_input: response['tokens']['input'],
              tokens_output: response['tokens']['output'],
              spend: response['spend'],
              tool_calls: response['tool_calls']
            )

            # Execute each tool and save results
            response['tool_calls'].each do |tool_call|
              result = tool_registry.execute(
                name: tool_call['name'],
                arguments: tool_call['arguments'],
                history: history,
                context: { 'conversation_id' => conversation_id }
              )

              # Save tool result
              # Store both name and result for client formatting
              history.add_message(
                conversation_id: conversation_id,
                actor: tool_call['name'],
                role: 'tool',
                content: nil,
                tool_call_id: tool_call['id'],
                tool_result: {
                  'name' => tool_call['name'],
                  'result' => result
                }
              )
            end

            # Loop back to send results to LLM
            next
          else
            # No tool calls, save final response and exit
            history.add_message(
              conversation_id: conversation_id,
              actor: 'orchestrator',
              role: 'assistant',
              content: response['content'],
              model: response['model'],
              tokens_input: response['tokens']['input'],
              tokens_output: response['tokens']['output'],
              spend: response['spend']
            )

            break
          end
        end
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
          @conversation_id = history.create_conversation
          @session_start_time = Time.now
          formatter.reset_session(conversation_id: @conversation_id)
          puts "Conversation reset"
          :continue
        when '/models'
          print_models
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
        puts "  /models - List available models for current provider"
        puts "  /reset  - Start a new conversation"
      end

      def print_models
        result = client.list_models

        puts "\n#{result[:provider]} Models"
        puts "=" * 60

        if result[:note]
          puts "Note: #{result[:note]}"
        end

        if result[:error]
          puts "Error: #{result[:error]}"
        end

        puts "\nAvailable models:"
        result[:models].each do |model|
          if model[:id]
            puts "  • #{model[:id]}"
            puts "    Aliases: #{model[:aliases].join(', ')}" if model[:aliases]
          elsif model[:name]
            puts "  • #{model[:name]}"
            puts "    Display: #{model[:display_name]}" if model[:display_name]
          end
        end
        puts ""
      end

      def setup_signal_handlers
        Signal.trap("INT") do
          print_goodbye
          active_threads.each(&:join) if active_threads
          history.close if history
          exit(0)
        end
      end

      def print_welcome
        puts "Nu Agent REPL"
        puts "Using: #{client.name} (#{client.model})"
        puts "Type your prompts below. Press Ctrl-C, Ctrl-D, or /exit to quit."
        puts "Type /help for available commands"
        puts "=" * 60
      end

      def print_goodbye
        puts "\n\nGoodbye!"
      end

    end
  end
end
