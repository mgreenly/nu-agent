# frozen_string_literal: true

module Nu
  module Agent
    class Command
      def initialize(input, app)
        @input = input
        @app = app
        @llm = app.llm
        @pipeline = app.pipeline
      end

      def execute
        return :process unless @input.start_with?('/')

        command = @input.downcase

        case command
        when '/exit'
          :exit
        when '/reset'
          @llm.reset
          puts "Conversation and token count reset"
          :continue
        when '/pipeline'
          toggle_pipeline
          :continue
        when '/help'
          print_help
          :continue
        else
          puts "Unknown command: #{@input}"
          :continue
        end
      end

      private

      def toggle_pipeline
        @pipeline.toggle_enabled
        if @pipeline.enabled
          puts "🟢 Pipeline enabled - prompts will be processed for ambiguities"
        else
          puts "🔴 Pipeline disabled - prompts will be sent directly to LLM"
        end
      end

      def print_help
        puts "\nAvailable commands:"
        puts "  /exit     - Exit the REPL"
        puts "  /help     - Show this help message"
        puts "  /pipeline - Toggle prompt processing pipeline on/off"
        puts "  /reset    - Reset conversation and token count"
        puts "\nPipeline status: #{@pipeline.enabled ? '🟢 Enabled' : '🔴 Disabled'}"
      end
    end
  end
end
