# frozen_string_literal: true

require_relative "formatters/tool_call_formatter"
require_relative "formatters/tool_result_formatter"
require_relative "formatters/llm_request_formatter"

module Nu
  module Agent
    class Formatter
      attr_writer :orchestrator
      attr_accessor :exchange_start_time

      def debug=(value)
        @debug = value
        @llm_request_formatter.debug = value if @llm_request_formatter
      end

      def initialize(history:, console:, orchestrator:, **config)
        @history = history
        @console = console
        @orchestrator = orchestrator
        @session_start_time = config[:session_start_time]
        @conversation_id = config[:conversation_id]
        @debug = config.fetch(:debug, false)
        @application = config[:application]
        @last_message_id = 0
        @exchange_start_time = nil
        @tool_call_formatter = Formatters::ToolCallFormatter.new(console: console, application: @application)
        @tool_result_formatter = Formatters::ToolResultFormatter.new(console: console, application: @application)
        @llm_request_formatter = Formatters::LlmRequestFormatter.new(
          console: console,
          application: @application,
          debug: @debug
        )
      end

      def reset_session(conversation_id:)
        @conversation_id = conversation_id
        @session_start_time = Time.now
        @last_message_id = 0
      end

      def display_new_messages(conversation_id:)
        messages = @history.messages_since(
          conversation_id: conversation_id,
          message_id: @last_message_id
        )

        # Stop spinner before displaying any messages
        @console.hide_spinner if messages.any?

        messages.each do |msg|
          display_message(msg)
          @last_message_id = msg["id"]
        end

        # Restart spinner after displaying messages (if still waiting)
        @console.show_spinner("Thinking...") if messages.any? && !@history.workers_idle?
      end

      def wait_for_completion(conversation_id:, poll_interval: 0.1)
        # Start spinner if output_manager is available
        @console.show_spinner("Thinking...")

        loop do
          display_new_messages(conversation_id: conversation_id)

          break if @history.workers_idle?

          sleep poll_interval
        end

        # Display any final messages
        display_new_messages(conversation_id: conversation_id)

        # Stop spinner when done
        @console.hide_spinner
      end

      def display_message(message)
        # Only show spell_checker messages in debug mode
        return if message["actor"] == "spell_checker" && !@debug

        # Display spell_checker messages in gray (debug style)
        if message["actor"] == "spell_checker" && @debug
          display_spell_checker_message(message)
          return
        end

        # Error messages
        if message["error"]
          display_error(message)
        # Tool results have role 'user' but include tool_result
        elsif message["tool_result"]
          # Only display tool results in debug mode
          display_tool_result(message) if @debug
        else
          case message["role"]
          when "assistant"
            display_assistant_message(message)
          when "system"
            display_system_message(message)
          end
        end
      end

      def display_token_summary(conversation_id:)
        messages = @history.messages(conversation_id: conversation_id, include_in_context_only: false)

        total_input = messages.sum { |m| m["tokens_input"] || 0 }
        total_output = messages.sum { |m| m["tokens_output"] || 0 }
        total = total_input + total_output

        @console.puts("Tokens: #{total_input} in / #{total_output} out / #{total} total")
      end

      def display_thread_event(thread_name, status)
        # Only show in debug mode
        return unless @debug

        # Stop spinner to avoid output on same line
        @console.hide_spinner

        @console.puts("")
        @console.puts("\e[90m[Thread] #{thread_name} #{status}\e[0m")

        # Restart spinner with preserved start time
        @console.show_spinner("Thinking...") unless @history.workers_idle?
      end

      def display_message_created(actor:, role:, **details)
        return unless @debug

        verbosity = @application ? @application.verbosity : 0
        return if verbosity < 2

        @console.hide_spinner

        direction = case role
                    when "user", "tool", "system" then "Out"
                    when "assistant" then "In"
                    else ""
                    end
        msg_type = details.fetch(:redacted, false) ? "redacted message" : "message"

        display_basic_message_info(direction, msg_type, verbosity)
        return if verbosity == 2

        display_detailed_message_info(actor, role, details, verbosity) if verbosity >= 3

        @console.show_spinner("Thinking...") unless @history.workers_idle?
      end

      def display_basic_message_info(direction, msg_type, _verbosity)
        @console.puts("")
        @console.puts("\e[90m[Message #{direction}] Created #{msg_type}\e[0m")
      end

      def display_detailed_message_info(actor, role, details, verbosity)
        @console.puts("\e[90m  role: #{role}\e[0m")
        @console.puts("\e[90m  actor: #{actor}\e[0m")

        show_tool_calls_preview(details[:tool_calls], verbosity) if details[:tool_calls]&.length&.positive?
        show_tool_result_preview(details[:tool_result], verbosity) if details[:tool_result]
        show_content_preview(details[:content], verbosity) if details[:content] && !details[:content].empty?
      end

      def show_tool_calls_preview(tool_calls, verbosity)
        tool_names = tool_calls.map { |tc| tc["name"] }.join(", ")
        @console.puts("\e[90m  tool_calls: #{tool_names}\e[0m")

        tool_calls.each do |tc|
          next unless tc["arguments"] && !tc["arguments"].empty?

          args_str = tc["arguments"].to_json
          max_length = verbosity >= 6 ? 100 : 30
          preview = args_str[0...max_length]
          @console.puts("\e[90m    #{tc['name']}: #{preview}#{'...' if args_str.length > max_length}\e[0m")
        end
      end

      def show_tool_result_preview(tool_result, verbosity)
        @console.puts("\e[90m  tool_result: #{tool_result['name']}\e[0m")

        return unless tool_result["result"]

        res = tool_result["result"]
        result_str = res.is_a?(Hash) ? res.to_json : res.to_s
        max_length = verbosity >= 6 ? 100 : 30
        preview = result_str[0...max_length]
        @console.puts("\e[90m    result: #{preview}#{'...' if result_str.length > max_length}\e[0m")
      end

      def show_content_preview(content, verbosity)
        max_length = verbosity >= 6 ? 100 : 30
        preview = content[0...max_length]
        @console.puts("\e[90m  content: #{preview}#{'...' if content.length > max_length}\e[0m")
      end

      def display_llm_request(messages, tools = nil, markdown_document = nil)
        @llm_request_formatter.display(messages, tools, markdown_document)
      end

      private

      def display_assistant_message(message)
        display_content_or_warning(message)
        display_debug_tool_calls(message)
        display_session_statistics(message) if should_display_stats?(message)
      end

      def display_content_or_warning(message)
        if message["content"] && !message["content"].strip.empty?
          @console.puts("")
          @console.puts(message["content"])
        elsif !message["tool_calls"] && message["tokens_output"]&.positive?
          # LLM generated output but content is empty (unusual case - possibly API issue)
          @console.puts("\e[90m(LLM returned empty response - this may be an API/model issue)\e[0m") if @debug
        end
      end

      def display_debug_tool_calls(message)
        return unless @debug && message["tool_calls"]

        total_count = message["tool_calls"].length
        message["tool_calls"].each_with_index do |tc, index|
          display_tool_call(tc, index: index + 1, total: total_count)
        end
      end

      def should_display_stats?(message)
        message["tokens_input"] && message["tokens_output"] && !message["tool_calls"]
      end

      def display_session_statistics(_message)
        elapsed_time = @exchange_start_time ? Time.now - @exchange_start_time : nil

        tokens = @history.session_tokens(
          conversation_id: @conversation_id,
          since: @session_start_time
        )

        display_token_statistics(tokens) if @debug
        display_spend_statistics(tokens) if @debug
        display_elapsed_time(elapsed_time) if elapsed_time && @debug
      end

      def display_token_statistics(tokens)
        max_context = @orchestrator.max_context
        percentage = (tokens["total"].to_f / max_context * 100).round(1)

        @console.puts("")
        inp = tokens["input"]
        out = tokens["output"]
        total = tokens["total"]
        stat_msg = "Session tokens: #{inp} in / #{out} out / #{total} Total / (#{percentage}% of #{max_context})"
        @console.puts("\e[90m#{stat_msg}\e[0m")
      end

      def display_spend_statistics(tokens)
        @console.puts("\e[90mSession spend: $#{format('%.6f', tokens['spend'])}\e[0m")
      end

      def display_elapsed_time(elapsed_time)
        @console.puts("\e[90mElapsed time: #{format('%.2f', elapsed_time)}s\e[0m")
      end

      def display_system_message(message)
        content = message["content"].to_s
        return if content.strip.empty?

        # Split and normalize, then prefix first line with [System]
        lines = content.lines.map(&:chomp)
        lines = lines.drop_while(&:empty?).reverse.drop_while(&:empty?).reverse

        # Collapse consecutive blanks
        normalized = []
        prev_empty = false
        lines.each do |line|
          if line.empty?
            normalized << line unless prev_empty
            prev_empty = true
          else
            normalized << line
            prev_empty = false
          end
        end

        return unless normalized.any?

        @console.puts("\e[90m[System] #{normalized.first}\e[0m")
        normalized[1..].each { |line| @console.puts("\e[90m#{line}\e[0m") }
      end

      def display_spell_checker_message(message)
        role_label = message["role"] == "user" ? "Spell Check Request" : "Spell Check Result"
        @console.puts("")
        @console.puts("\e[90m[#{role_label}]\e[0m")
        return unless message["content"] && !message["content"].strip.empty?

        @console.puts("\e[90m#{message['content']}\e[0m")
      end

      def display_tool_call(tool_call, index: nil, total: nil)
        @tool_call_formatter.display(tool_call, index: index, total: total)
      end

      def display_tool_result(message)
        @tool_result_formatter.display(message)
      end

      def display_error(message)
        error = message["error"]

        @console.puts("\e[31m#{message['content']}\e[0m")
        @console.puts("\e[31mStatus: #{error['status']}\e[0m")

        @console.puts("\e[31mHeaders:\e[0m")
        error["headers"].each do |key, value|
          @console.puts("\e[31m  #{key}: #{value}\e[0m")
        end

        @console.puts("\e[31mBody:\e[0m")
        # Try to parse and pretty print JSON body
        begin
          if error["body"].is_a?(String) && !error["body"].empty?
            parsed = JSON.parse(error["body"])
            @console.puts("\e[31m#{JSON.pretty_generate(parsed)}\e[0m")
          elsif error["body"]
            @console.puts("\e[31m#{error['body']}\e[0m")
          else
            @console.puts("\e[31m(empty)\e[0m")
          end
        rescue JSON::ParserError
          @console.puts("\e[31m#{error['body']}\e[0m")
        end

        # Show raw error for debugging if body is empty
        return unless error["raw_error"] && (error["body"].nil? || error["body"].empty?)

        @console.puts("\e[31mRaw Error (for debugging):\e[0m")
        @console.puts("\e[31m#{error['raw_error']}\e[0m")
      end
    end
  end
end
