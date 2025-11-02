# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::Formatter do
  let(:history) { instance_double(Nu::Agent::History, get_int: 0) }
  let(:orchestrator) { instance_double("Orchestrator", max_context: 200_000) }
  let(:mock_console) do
    instance_double(
      Nu::Agent::ConsoleIO,
      puts: nil,
      show_spinner: nil,
      hide_spinner: nil
    )
  end
  let(:application) { instance_double(Nu::Agent::Application, debug: false, history: history) }
  let(:session_start_time) { Time.now - 60 }
  let(:conversation_id) { 1 }
  let(:formatter) do
    described_class.new(
      history: history,
      session_start_time: session_start_time,
      conversation_id: conversation_id,
      orchestrator: orchestrator,
      debug: false,
      console: mock_console,
      application: application
    )
  end

  describe "#display_new_messages" do
    context "when there are new messages" do
      let(:messages) do
        [
          {
            "id" => 1,
            "actor" => "user",
            "role" => "user",
            "content" => "Hello",
            "tokens_input" => nil,
            "tokens_output" => nil
          },
          {
            "id" => 2,
            "actor" => "orchestrator",
            "role" => "assistant",
            "content" => "Hi there!",
            "tokens_input" => 10,
            "tokens_output" => 5
          }
        ]
      end

      before do
        allow(history).to receive_messages(messages_since: messages, workers_idle?: true, session_tokens: {
                                             "input" => 10,
                                             "output" => 5,
                                             "total" => 15,
                                             "spend" => 0.000150
                                           })
      end

      it "displays assistant messages" do
        expect(mock_console).to receive(:puts).with("Hi there!")

        formatter.display_new_messages(conversation_id: conversation_id)
      end

      it "displays token counts for assistant messages in debug mode" do
        allow(history).to receive(:session_tokens).and_return({
                                                                "input" => 10,
                                                                "output" => 5,
                                                                "total" => 15,
                                                                "spend" => 0.000150
                                                              })

        # Enable debug mode and stats verbosity to show token stats
        formatter.debug = true
        allow(application).to receive(:debug).and_return(true)
        allow(history).to receive(:get_int).with("stats_verbosity", default: 0).and_return(1)

        expect(mock_console).to receive(:puts).with("Hi there!")
        token_str = "\e[90mSession tokens: 10 in / 5 out / 15 Total / (0.0% of 200000)\e[0m"
        expect(mock_console).to receive(:puts).with(token_str)
        expect(mock_console).to receive(:puts).with("\e[90mSession spend: $0.000150\e[0m")

        formatter.display_new_messages(conversation_id: conversation_id)
      end

      it "updates last_message_id" do
        formatter.display_new_messages(conversation_id: conversation_id)

        # Call again - should use updated last_message_id
        expect(history).to receive(:messages_since).with(
          conversation_id: conversation_id,
          message_id: 2
        ).and_return([])

        formatter.display_new_messages(conversation_id: conversation_id)
      end
    end

    context "when there are no new messages" do
      before do
        allow(history).to receive(:messages_since).and_return([])
      end

      it "does not output anything" do
        expect(mock_console).not_to receive(:puts)

        formatter.display_new_messages(conversation_id: conversation_id)
      end
    end
  end

  describe "#wait_for_completion" do
    it "polls until workers are idle" do
      call_count = 0
      allow(history).to receive(:messages_since).and_return([])
      allow(history).to receive(:workers_idle?) do
        call_count += 1
        call_count >= 3 # Become idle after 3 calls
      end

      formatter.wait_for_completion(conversation_id: conversation_id, poll_interval: 0.01)

      expect(call_count).to eq(3)
    end

    it "displays messages during polling" do
      messages = [
        {
          "id" => 1,
          "actor" => "orchestrator",
          "role" => "assistant",
          "content" => "Processing...",
          "tokens_input" => 5,
          "tokens_output" => 3
        }
      ]

      call_count = 0
      allow(history).to receive(:messages_since) do
        call_count += 1
        call_count == 1 ? messages : []
      end

      allow(history).to receive(:session_tokens).and_return({
                                                              "input" => 5,
                                                              "output" => 3,
                                                              "total" => 8,
                                                              "spend" => 0.000080
                                                            })

      allow(history).to receive(:workers_idle?).and_return(false, true)

      expect(mock_console).to receive(:puts).with("Processing...")

      formatter.wait_for_completion(conversation_id: conversation_id, poll_interval: 0.01)
    end

    it "uses event-driven approach when event_bus is available" do
      event_bus = instance_double("EventBus")
      allow(event_bus).to receive(:subscribe) # Accept any subscribe call

      formatter_with_event_bus = described_class.new(
        history: history,
        session_start_time: session_start_time,
        conversation_id: conversation_id,
        orchestrator: orchestrator,
        debug: false,
        console: mock_console,
        application: nil,
        event_bus: event_bus
      )

      allow(history).to receive(:messages_since).and_return([])

      # Simulate exchange completion after a short delay
      Thread.new do
        sleep 0.1
        formatter_with_event_bus.instance_variable_get(:@exchange_mutex).synchronize do
          formatter_with_event_bus.instance_variable_set(:@exchange_completed, true)
        end
      end

      expect(mock_console).to receive(:show_spinner).with("Thinking...")
      expect(mock_console).to receive(:hide_spinner)

      formatter_with_event_bus.wait_for_completion(conversation_id: conversation_id)
    end
  end

  describe "#display_message" do
    it "displays user messages (as no-op)" do
      message = { "id" => 1, "actor" => "user", "role" => "user", "content" => "Hello" }

      expect(mock_console).not_to receive(:puts)

      formatter.display_message(message)
    end

    it "displays assistant messages with content and tokens" do
      allow(history).to receive(:session_tokens).and_return({
                                                              "input" => 8,
                                                              "output" => 4,
                                                              "total" => 12,
                                                              "spend" => 0.000120
                                                            })

      message = {
        "id" => 2,
        "actor" => "orchestrator",
        "role" => "assistant",
        "content" => "Hello back!",
        "tokens_input" => 8,
        "tokens_output" => 4
      }

      expect(mock_console).to receive(:puts).with("Hello back!")

      formatter.display_message(message)
    end

    it "displays system messages with prefix" do
      message = { "id" => 3, "actor" => "system", "role" => "system", "content" => "Starting up" }

      expect(mock_console).to receive(:puts).with("\e[90m[System] Starting up\e[0m")

      formatter.display_message(message)
    end

    it "queries session tokens from database for cumulative totals" do
      # Enable debug mode and stats verbosity to trigger token statistics display
      formatter.debug = true
      allow(application).to receive(:debug).and_return(true)
      allow(history).to receive(:get_int).with("stats_verbosity", default: 0).and_return(1)

      message1 = {
        "id" => 1,
        "actor" => "orchestrator",
        "role" => "assistant",
        "content" => "First message",
        "tokens_input" => 10,
        "tokens_output" => 5
      }

      message2 = {
        "id" => 2,
        "actor" => "orchestrator",
        "role" => "assistant",
        "content" => "Second message",
        "tokens_input" => 20,
        "tokens_output" => 8
      }

      # First call returns just first message tokens
      # Second call returns cumulative total
      allow(history).to receive(:session_tokens).and_return(
        { "input" => 10, "output" => 5, "total" => 15, "spend" => 0.000150 },
        { "input" => 30, "output" => 13, "total" => 43, "spend" => 0.000430 }
      )

      expect(mock_console).to receive(:puts).with("First message")
      expect(mock_console).to receive(:puts).with("Second message")

      formatter.display_message(message1)
      formatter.display_message(message2)

      # Verify session_tokens was called with correct parameters
      expect(history).to have_received(:session_tokens).with(
        conversation_id: conversation_id,
        since: session_start_time
      ).twice
    end
  end

  describe "#display_token_summary" do
    let(:messages) do
      [
        { "id" => 1, "role" => "user", "content" => "Hi", "tokens_input" => nil, "tokens_output" => nil },
        { "id" => 2, "role" => "assistant", "content" => "Hello", "tokens_input" => 10, "tokens_output" => 5 },
        { "id" => 3, "role" => "user", "content" => "How are you?", "tokens_input" => nil, "tokens_output" => nil },
        { "id" => 4, "role" => "assistant", "content" => "Good!", "tokens_input" => 15, "tokens_output" => 3 }
      ]
    end

    before do
      allow(history).to receive(:messages).and_return(messages)
    end

    it "displays total token counts via console.puts" do
      expect(mock_console).to receive(:puts).with("Tokens: 25 in / 8 out / 33 total")

      formatter.display_token_summary(conversation_id: conversation_id)
    end

    it "handles messages with nil token counts" do
      expect { formatter.display_token_summary(conversation_id: conversation_id) }.not_to raise_error
    end
  end

  describe "verbosity levels" do
    let(:application) { instance_double("Application", debug: true, history: history) }
    let(:formatter_with_app) do
      described_class.new(
        history: history,
        session_start_time: session_start_time,
        conversation_id: conversation_id,
        orchestrator: orchestrator,
        debug: true,
        console: mock_console,
        application: application
      )
    end

    let(:tool_call_message) do
      {
        "id" => 5,
        "actor" => "orchestrator",
        "role" => "assistant",
        "content" => nil,
        "tokens_input" => 20,
        "tokens_output" => 10,
        "tool_calls" => [
          {
            "name" => "file_read",
            "arguments" => {
              "path" => "/very/long/path/to/some/file/that/is/longer/than/thirty/characters.txt",
              "encoding" => "utf-8"
            }
          }
        ]
      }
    end

    let(:tool_result_message) do
      {
        "id" => 6,
        "actor" => "orchestrator",
        "role" => "user",
        "tool_result" => {
          "name" => "file_read",
          "result" => {
            "content" => "This is a very long file content that should be truncated when verbosity is 1 " \
                         "and shown in full when verbosity is 2 or higher",
            "size" => 1024
          }
        }
      }
    end

    before do
      allow(history).to receive_messages(session_tokens: {
                                           "input" => 20,
                                           "output" => 10,
                                           "total" => 30,
                                           "spend" => 0.000300
                                         }, workers_idle?: true)
    end

    describe "level 1: tool name only" do
      before do
        allow(history).to receive(:get_int).with("tools_verbosity", default: 0).and_return(1)
      end

      it "displays tool call name without arguments" do
        expect(mock_console).to receive(:puts).with("").ordered
        expect(mock_console).to receive(:puts).with("\e[90m[Tool Call Request] file_read\e[0m")

        formatter_with_app.display_message(tool_call_message)
      end

      it "displays tool result name without result details" do
        expect(mock_console).to receive(:puts).with("\e[90m[Tool Use Response] file_read\e[0m")

        formatter_with_app.display_message(tool_result_message)
      end
    end

    describe "level 2: tool name + first 30 chars of params + thread notifications" do
      before do
        allow(history).to receive(:get_int).with("tools_verbosity", default: 0).and_return(2)
      end

      it "displays tool call arguments truncated to 30 characters" do
        expect(mock_console).to receive(:puts).with("").ordered
        expect(mock_console).to receive(:puts).with("\e[90m[Tool Call Request] file_read\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  path: /very/long/path/to/some/file/t...\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  encoding: utf-8\e[0m")

        formatter_with_app.display_message(tool_call_message)
      end

      it "displays tool result fields truncated to 30 characters" do
        expect(mock_console).to receive(:puts).with("\e[90m[Tool Use Response] file_read\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  content: This is a very long file conte...\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  size: 1024\e[0m")

        formatter_with_app.display_message(tool_result_message)
      end

      it "does not truncate short values" do
        short_message = {
          "id" => 7,
          "actor" => "orchestrator",
          "role" => "user",
          "tool_result" => {
            "name" => "test_tool",
            "result" => {
              "status" => "ok",
              "value" => "short"
            }
          }
        }

        expect(mock_console).to receive(:puts).with("\e[90m[Tool Use Response] test_tool\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  status: ok\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  value: short\e[0m")

        formatter_with_app.display_message(short_message)
      end
    end

    describe "level 2: truncated params (same as level 2)" do
      before do
        allow(history).to receive(:get_int).with("tools_verbosity", default: 0).and_return(2)
      end

      it "displays tool call arguments truncated to 30 chars" do
        expect(mock_console).to receive(:puts).with("").ordered
        expect(mock_console).to receive(:puts).with("\e[90m[Tool Call Request] file_read\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  path: /very/long/path/to/some/file/t...\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  encoding: utf-8\e[0m")

        formatter_with_app.display_message(tool_call_message)
      end

      it "displays tool result fields truncated to 30 chars" do
        expect(mock_console).to receive(:puts).with("\e[90m[Tool Use Response] file_read\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  content: This is a very long file conte...\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  size: 1024\e[0m")

        formatter_with_app.display_message(tool_result_message)
      end
    end

    describe "level 4 and 5: documented in application specs" do
      # Levels 3 and 4 involve showing the request/context sent to the LLM
      # These are tested in application_spec.rb since they require chat_loop context
      it "is a placeholder for application-level tests" do
        # Level 3: Show messages sent to LLM
        # Level 4: Show messages + conversation history
        # See application_spec.rb for these tests
      end
    end
  end

  describe "blank line spacing for readability" do
    let(:blank_line_app) { instance_double("Application", debug: true, history: history) }
    let(:formatter_debug) do
      described_class.new(
        history: history,
        session_start_time: session_start_time,
        conversation_id: conversation_id,
        orchestrator: orchestrator,
        debug: true,
        console: mock_console,
        application: blank_line_app
      )
    end

    before do
      allow(history).to receive(:get_int).with("tools_verbosity", default: 0).and_return(1)
      allow(history).to receive(:get_int).with("stats_verbosity", default: 0).and_return(1)
    end

    context "thread events" do
      before do
        allow(history).to receive(:workers_idle?).and_return(true)
      end

      it "adds blank line before thread event output" do
        allow(history).to receive(:get_int).with("thread_verbosity", default: 0).and_return(1)

        expect(mock_console).to receive(:puts).with("").ordered
        expect(mock_console).to receive(:puts).with("\e[90m[Thread] Orchestrator Starting\e[0m").ordered

        formatter_debug.display_thread_event("Orchestrator", "Starting")
      end
    end

    context "tool calls" do
      it "adds blank line before tool call output" do
        message = {
          "id" => 3,
          "actor" => "orchestrator",
          "role" => "assistant",
          "content" => nil,
          "tool_calls" => [
            {
              "name" => "file_read",
              "arguments" => { "path" => "/tmp/test.txt" }
            }
          ]
        }

        allow(history).to receive(:session_tokens).and_return({
                                                                "input" => 10,
                                                                "output" => 5,
                                                                "total" => 15,
                                                                "spend" => 0.000150
                                                              })

        expect(mock_console).to receive(:puts).with("").ordered
        expect(mock_console).to receive(:puts).with("\e[90m[Tool Call Request] file_read\e[0m").ordered

        formatter_debug.display_message(message)
      end
    end

    context "tool results" do
      it "adds blank line before tool result output" do
        message = {
          "id" => 4,
          "actor" => "orchestrator",
          "role" => "user",
          "tool_result" => {
            "name" => "file_read",
            "result" => { "content" => "file contents" }
          }
        }

        expect(mock_console).to receive(:puts).with("").ordered
        expect(mock_console).to receive(:puts).with("\e[90m[Tool Use Response] file_read\e[0m").ordered

        formatter_debug.display_message(message)
      end
    end

    context "assistant messages" do
      before do
        allow(history).to receive(:session_tokens).and_return({
                                                                "input" => 10,
                                                                "output" => 5,
                                                                "total" => 15,
                                                                "spend" => 0.000150
                                                              })
      end

      it "adds blank line before assistant content" do
        message = {
          "id" => 5,
          "actor" => "orchestrator",
          "role" => "assistant",
          "content" => "The temperature is 48°F.",
          "tokens_input" => 10,
          "tokens_output" => 5
        }

        expect(mock_console).to receive(:puts).with("").ordered
        expect(mock_console).to receive(:puts).with("The temperature is 48°F.").ordered
        expect(mock_console).to receive(:puts).with("").ordered
        token_str = "\e[90mSession tokens: 10 in / 5 out / 15 Total / (0.0% of 200000)\e[0m"
        expect(mock_console).to receive(:puts).with(token_str).ordered
        expect(mock_console).to receive(:puts).with("\e[90mSession spend: $0.000150\e[0m").ordered

        formatter_debug.display_message(message)
      end
    end
  end

  describe "#reset_session" do
    it "resets conversation_id and session_start_time" do
      new_conversation_id = 42

      formatter.reset_session(conversation_id: new_conversation_id)

      # Verify by checking the formatter uses new conversation_id
      expect(history).to receive(:messages_since).with(
        conversation_id: new_conversation_id,
        message_id: 0
      ).and_return([])

      formatter.display_new_messages(conversation_id: new_conversation_id)
    end
  end

  describe "#display_llm_request" do
    it "delegates to llm_request_formatter with internal format" do
      internal_format = {
        system_prompt: "You are a helpful assistant",
        messages: [{ "role" => "user", "content" => "Hello" }],
        tools: [{ "name" => "file_read" }],
        metadata: {
          rag_content: {},
          user_query: "# Test"
        }
      }

      llm_formatter = instance_double(Nu::Agent::Formatters::LlmRequestFormatter)
      allow(Nu::Agent::Formatters::LlmRequestFormatter).to receive(:new).and_return(llm_formatter)

      formatter_with_llm = described_class.new(
        history: history,
        session_start_time: session_start_time,
        conversation_id: conversation_id,
        orchestrator: orchestrator,
        debug: false,
        console: mock_console,
        application: nil
      )

      expect(llm_formatter).to receive(:display_yaml).with(internal_format)

      formatter_with_llm.display_llm_request(internal_format)
    end
  end

  describe "error message display" do
    let(:error_message) do
      {
        "id" => 1,
        "role" => "assistant",
        "content" => "API Error Occurred",
        "error" => {
          "status" => 401,
          "headers" => { "content-type" => "application/json" },
          "body" => '{"error": {"message": "Invalid API key"}}',
          "raw_error" => "Full error details"
        }
      }
    end

    it "displays formatted error with JSON body" do
      expect(mock_console).to receive(:puts).with("\e[31mAPI Error Occurred\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31mStatus: 401\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31mHeaders:\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31m  content-type: application/json\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31mBody:\e[0m")
      expect(mock_console).to receive(:puts).with(a_string_matching(/Invalid API key/))

      formatter.display_message(error_message)
    end

    it "displays error with non-JSON body" do
      error_message["error"]["body"] = "Plain text error"

      expect(mock_console).to receive(:puts).with("\e[31mAPI Error Occurred\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31mStatus: 401\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31mHeaders:\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31m  content-type: application/json\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31mBody:\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31mPlain text error\e[0m")

      formatter.display_message(error_message)
    end

    it "displays error with empty body" do
      error_message["error"]["body"] = nil

      expect(mock_console).to receive(:puts).with("\e[31mAPI Error Occurred\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31mStatus: 401\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31mHeaders:\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31m  content-type: application/json\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31mBody:\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31m(empty)\e[0m")

      formatter.display_message(error_message)
    end

    it "displays error with Hash body" do
      error_message["error"]["body"] = { "error" => "Something went wrong" }

      expect(mock_console).to receive(:puts).with("\e[31mAPI Error Occurred\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31mStatus: 401\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31mHeaders:\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31m  content-type: application/json\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31mBody:\e[0m")
      expect(mock_console).to receive(:puts).with(/Something went wrong/)

      formatter.display_message(error_message)
    end

    it "displays raw_error when body is empty string" do
      error_message["error"]["body"] = ""

      expect(mock_console).to receive(:puts).with("\e[31mAPI Error Occurred\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31mStatus: 401\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31mHeaders:\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31m  content-type: application/json\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31mBody:\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31m\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31mRaw Error (for debugging):\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31mFull error details\e[0m")

      formatter.display_message(error_message)
    end

    it "displays raw_error when body is nil" do
      error_message["error"]["body"] = nil

      expect(mock_console).to receive(:puts).with("\e[31mAPI Error Occurred\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31mStatus: 401\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31mHeaders:\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31m  content-type: application/json\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31mBody:\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31m(empty)\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31mRaw Error (for debugging):\e[0m")
      expect(mock_console).to receive(:puts).with("\e[31mFull error details\e[0m")

      formatter.display_message(error_message)
    end
  end

  describe "system message normalization" do
    it "normalizes system messages by collapsing consecutive blank lines" do
      message = {
        "id" => 1,
        "role" => "system",
        "content" => "Line 1\n\n\n\nLine 2\n\n\nLine 3"
      }

      expect(mock_console).to receive(:puts).with("\e[90m[System] Line 1\e[0m")
      expect(mock_console).to receive(:puts).with("\e[90m\e[0m")
      expect(mock_console).to receive(:puts).with("\e[90mLine 2\e[0m")
      expect(mock_console).to receive(:puts).with("\e[90m\e[0m")
      expect(mock_console).to receive(:puts).with("\e[90mLine 3\e[0m")

      formatter.display_message(message)
    end

    it "handles system messages with only whitespace" do
      message = {
        "id" => 1,
        "role" => "system",
        "content" => "   \n\n   "
      }

      expect(mock_console).not_to receive(:puts)

      formatter.display_message(message)
    end
  end

  describe "empty LLM response warning" do
    it "shows warning in debug mode when LLM returns empty content with tokens" do
      formatter.debug = true

      message = {
        "id" => 1,
        "actor" => "orchestrator",
        "role" => "assistant",
        "content" => "",
        "tokens_input" => 10,
        "tokens_output" => 5,
        "tool_calls" => nil
      }

      allow(history).to receive(:session_tokens).and_return({
                                                              "input" => 10,
                                                              "output" => 5,
                                                              "total" => 15,
                                                              "spend" => 0.000150
                                                            })

      debug_warning = "\e[90m(LLM returned empty response - this may be an API/model issue)\e[0m"
      expect(mock_console).to receive(:puts).with(debug_warning)

      formatter.display_message(message)
    end
  end

  describe "#display_message_created" do
    let(:message_app) { instance_double("Application", history: history) }
    let(:formatter_with_app) do
      described_class.new(
        history: history,
        session_start_time: session_start_time,
        conversation_id: conversation_id,
        orchestrator: orchestrator,
        debug: true,
        console: mock_console,
        application: message_app
      )
    end

    before do
      allow(history).to receive(:workers_idle?).and_return(true)
      allow(history).to receive(:get_int).with("messages_verbosity", default: 0).and_return(0)
    end

    context "when debug is false" do
      it "does not display anything" do
        formatter.debug = false

        expect(mock_console).not_to receive(:puts)

        formatter.display_message_created(actor: "orchestrator", role: "assistant")
      end
    end

    context "when verbosity is less than 2" do
      it "does not display anything" do
        allow(history).to receive(:get_int).with("messages_verbosity", default: 0).and_return(1)

        expect(mock_console).not_to receive(:puts)

        formatter_with_app.display_message_created(actor: "orchestrator", role: "assistant")
      end
    end

    context "when verbosity is 2" do
      it "displays basic message info for user message" do
        allow(history).to receive(:get_int).with("messages_verbosity", default: 0).and_return(2)

        expect(mock_console).to receive(:puts).with("")
        expect(mock_console).to receive(:puts).with("\e[90m[Message Out] Created message\e[0m")

        formatter_with_app.display_message_created(actor: "orchestrator", role: "user")
      end

      it "displays basic message info for assistant message" do
        allow(history).to receive(:get_int).with("messages_verbosity", default: 0).and_return(2)

        expect(mock_console).to receive(:puts).with("")
        expect(mock_console).to receive(:puts).with("\e[90m[Message In] Created message\e[0m")

        formatter_with_app.display_message_created(actor: "orchestrator", role: "assistant")
      end

      it "displays basic message info for system message" do
        allow(history).to receive(:get_int).with("messages_verbosity", default: 0).and_return(2)

        expect(mock_console).to receive(:puts).with("")
        expect(mock_console).to receive(:puts).with("\e[90m[Message Out] Created message\e[0m")

        formatter_with_app.display_message_created(actor: "system", role: "system")
      end

      it "displays redacted message indicator" do
        allow(history).to receive(:get_int).with("messages_verbosity", default: 0).and_return(2)

        expect(mock_console).to receive(:puts).with("")
        expect(mock_console).to receive(:puts).with("\e[90m[Message Out] Created redacted message\e[0m")

        formatter_with_app.display_message_created(actor: "orchestrator", role: "user", redacted: true)
      end
    end

    context "when verbosity is 3 or higher" do
      it "displays detailed message info including role and actor" do
        allow(history).to receive(:get_int).with("messages_verbosity", default: 0).and_return(3)

        expect(mock_console).to receive(:puts).with("")
        expect(mock_console).to receive(:puts).with("\e[90m[Message Out] Created message\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  role: user\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  actor: orchestrator\e[0m")

        formatter_with_app.display_message_created(actor: "orchestrator", role: "user")
      end

      it "displays tool_calls preview" do
        allow(history).to receive(:get_int).with("messages_verbosity", default: 0).and_return(3)

        tool_calls = [
          { "name" => "file_read", "arguments" => { "path" => "/tmp/test.txt" } },
          { "name" => "file_write", "arguments" => {} }
        ]

        expect(mock_console).to receive(:puts).with("")
        expect(mock_console).to receive(:puts).with("\e[90m[Message In] Created message\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  role: assistant\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  actor: orchestrator\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  tool_calls: file_read, file_write\e[0m")
        expect(mock_console).to receive(:puts).with(a_string_matching(/file_read:/))

        formatter_with_app.display_message_created(
          actor: "orchestrator",
          role: "assistant",
          tool_calls: tool_calls
        )
      end

      it "displays tool_result preview" do
        allow(history).to receive(:get_int).with("messages_verbosity", default: 0).and_return(3)

        tool_result = {
          "name" => "file_read",
          "result" => { "content" => "File contents here" }
        }

        expect(mock_console).to receive(:puts).with("")
        expect(mock_console).to receive(:puts).with("\e[90m[Message Out] Created message\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  role: user\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  actor: orchestrator\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  tool_result: file_read\e[0m")
        expect(mock_console).to receive(:puts).with(a_string_matching(/result:/))

        formatter_with_app.display_message_created(
          actor: "orchestrator",
          role: "user",
          tool_result: tool_result
        )
      end

      it "displays content preview" do
        allow(history).to receive(:get_int).with("messages_verbosity", default: 0).and_return(3)

        content = "This is some message content"

        expect(mock_console).to receive(:puts).with("")
        expect(mock_console).to receive(:puts).with("\e[90m[Message Out] Created message\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  role: user\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  actor: orchestrator\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  content: #{content}\e[0m")

        formatter_with_app.display_message_created(
          actor: "orchestrator",
          role: "user",
          content: content
        )
      end

      it "truncates tool call arguments at verbosity 3" do
        allow(history).to receive(:get_int).with("messages_verbosity", default: 0).and_return(3)

        long_arg = "a" * 100
        tool_calls = [{ "name" => "test", "arguments" => { "data" => long_arg } }]

        expect(mock_console).to receive(:puts).with("")
        expect(mock_console).to receive(:puts).with("\e[90m[Message In] Created message\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  role: assistant\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  actor: orchestrator\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  tool_calls: test\e[0m")
        expect(mock_console).to receive(:puts).with(a_string_matching(/\.\.\./))

        formatter_with_app.display_message_created(
          actor: "orchestrator",
          role: "assistant",
          tool_calls: tool_calls
        )
      end

      it "shows longer preview at verbosity 6" do
        allow(history).to receive(:get_int).with("messages_verbosity", default: 0).and_return(6)

        long_arg = "a" * 150
        tool_calls = [{ "name" => "test", "arguments" => { "data" => long_arg } }]

        expect(mock_console).to receive(:puts).with("")
        expect(mock_console).to receive(:puts).with("\e[90m[Message In] Created message\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  role: assistant\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  actor: orchestrator\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  tool_calls: test\e[0m")
        expect(mock_console).to receive(:puts).with(a_string_matching(/.{100}/))

        formatter_with_app.display_message_created(
          actor: "orchestrator",
          role: "assistant",
          tool_calls: tool_calls
        )
      end

      it "displays tool_result without result field" do
        allow(history).to receive(:get_int).with("messages_verbosity", default: 0).and_return(3)

        tool_result = { "name" => "file_read", "result" => nil }

        expect(mock_console).to receive(:puts).with("")
        expect(mock_console).to receive(:puts).with("\e[90m[Message Out] Created message\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  role: user\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  actor: orchestrator\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  tool_result: file_read\e[0m")

        formatter_with_app.display_message_created(
          actor: "orchestrator",
          role: "user",
          tool_result: tool_result
        )
      end

      it "handles tool result with Hash result" do
        allow(history).to receive(:get_int).with("messages_verbosity", default: 0).and_return(3)

        tool_result = {
          "name" => "test",
          "result" => { "status" => "ok", "value" => 123 }
        }

        expect(mock_console).to receive(:puts).with("")
        expect(mock_console).to receive(:puts).with("\e[90m[Message Out] Created message\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  role: user\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  actor: orchestrator\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  tool_result: test\e[0m")
        expect(mock_console).to receive(:puts).with(a_string_matching(/result:/))

        formatter_with_app.display_message_created(
          actor: "orchestrator",
          role: "user",
          tool_result: tool_result
        )
      end

      it "handles tool result with String result" do
        allow(history).to receive(:get_int).with("messages_verbosity", default: 0).and_return(3)

        tool_result = { "name" => "test", "result" => "simple string" }

        expect(mock_console).to receive(:puts).with("")
        expect(mock_console).to receive(:puts).with("\e[90m[Message Out] Created message\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  role: user\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  actor: orchestrator\e[0m")
        expect(mock_console).to receive(:puts).with("\e[90m  tool_result: test\e[0m")
        expect(mock_console).to receive(:puts).with(a_string_matching(/simple string/))

        formatter_with_app.display_message_created(
          actor: "orchestrator",
          role: "user",
          tool_result: tool_result
        )
      end
    end
  end

  describe "#debug=" do
    it "sets debug on llm_request_formatter when it exists" do
      formatter.debug = true
      formatter.debug = false

      # Verify it doesn't crash when llm_request_formatter exists
      expect { formatter.debug = true }.not_to raise_error
    end
  end

  describe "spinner behavior with workers" do
    before do
      allow(history).to receive(:messages_since).and_return([])
    end

    it "restarts spinner after displaying messages if workers are not idle" do
      messages = [
        {
          "id" => 1,
          "actor" => "orchestrator",
          "role" => "assistant",
          "content" => "Working...",
          "tokens_input" => 5,
          "tokens_output" => 3
        }
      ]

      allow(history).to receive_messages(messages_since: messages, session_tokens: {
                                           "input" => 5,
                                           "output" => 3,
                                           "total" => 8,
                                           "spend" => 0.000080
                                         })

      # Workers are busy after displaying messages
      allow(history).to receive(:workers_idle?).and_return(false)

      expect(mock_console).to receive(:hide_spinner).ordered
      expect(mock_console).to receive(:show_spinner).with("Thinking...").ordered

      formatter.display_new_messages(conversation_id: conversation_id)
    end
  end

  describe "edge cases and additional branches" do
    it "handles messages with unknown role" do
      message = {
        "id" => 1,
        "role" => "unknown_role",
        "content" => "Some content"
      }

      # Should not crash, just not display anything
      expect { formatter.display_message(message) }.not_to raise_error
    end

    it "handles display_message_created without application" do
      formatter.debug = true

      expect(mock_console).not_to receive(:puts)

      formatter.display_message_created(actor: "test", role: "user")
    end

    it "handles tool result preview with very long content at verbosity 6" do
      application = instance_double("Application", history: history)
      formatter_with_app = described_class.new(
        history: history,
        session_start_time: session_start_time,
        conversation_id: conversation_id,
        orchestrator: orchestrator,
        debug: true,
        console: mock_console,
        application: application
      )

      allow(history).to receive(:workers_idle?).and_return(true)
      allow(history).to receive(:get_int).with("messages_verbosity", default: 0).and_return(6)

      tool_result = {
        "name" => "test",
        "result" => "a" * 150
      }

      expect(mock_console).to receive(:puts).with("")
      expect(mock_console).to receive(:puts).with("\e[90m[Message Out] Created message\e[0m")
      expect(mock_console).to receive(:puts).with("\e[90m  role: user\e[0m")
      expect(mock_console).to receive(:puts).with("\e[90m  actor: orchestrator\e[0m")
      expect(mock_console).to receive(:puts).with("\e[90m  tool_result: test\e[0m")
      expect(mock_console).to receive(:puts).with(a_string_matching(/.{100}/))

      formatter_with_app.display_message_created(
        actor: "orchestrator",
        role: "user",
        tool_result: tool_result
      )
    end

    it "handles content preview with long content at verbosity 6" do
      application = instance_double("Application", history: history)
      formatter_with_app = described_class.new(
        history: history,
        session_start_time: session_start_time,
        conversation_id: conversation_id,
        orchestrator: orchestrator,
        debug: true,
        console: mock_console,
        application: application
      )

      allow(history).to receive(:workers_idle?).and_return(true)
      allow(history).to receive(:get_int).with("messages_verbosity", default: 0).and_return(6)

      content = "a" * 150

      expect(mock_console).to receive(:puts).with("")
      expect(mock_console).to receive(:puts).with("\e[90m[Message Out] Created message\e[0m")
      expect(mock_console).to receive(:puts).with("\e[90m  role: user\e[0m")
      expect(mock_console).to receive(:puts).with("\e[90m  actor: orchestrator\e[0m")
      expect(mock_console).to receive(:puts).with(a_string_matching(/.{100}/))

      formatter_with_app.display_message_created(
        actor: "orchestrator",
        role: "user",
        content: content
      )
    end

    it "handles assistant message without tokens_output" do
      message = {
        "id" => 1,
        "actor" => "orchestrator",
        "role" => "assistant",
        "content" => "Response",
        "tokens_input" => 10,
        "tokens_output" => nil,
        "tool_calls" => nil
      }

      allow(history).to receive(:session_tokens).and_return({
                                                              "input" => 10,
                                                              "output" => 0,
                                                              "total" => 10,
                                                              "spend" => 0.000100
                                                            })

      expect(mock_console).to receive(:puts).with("")
      expect(mock_console).to receive(:puts).with("Response")

      formatter.display_message(message)
    end

    it "handles debug setter when llm_request_formatter is not initialized" do
      # Create formatter but immediately set debug before @llm_request_formatter is accessed
      new_formatter = described_class.new(
        history: history,
        session_start_time: session_start_time,
        conversation_id: conversation_id,
        orchestrator: orchestrator,
        debug: false,
        console: mock_console,
        application: nil
      )

      # This should not crash
      expect { new_formatter.debug = false }.not_to raise_error
    end

    it "handles display_message_created with verbosity 3 but workers idle (no spinner restart)" do
      application = instance_double("Application", history: history)
      formatter_with_app = described_class.new(
        history: history,
        session_start_time: session_start_time,
        conversation_id: conversation_id,
        orchestrator: orchestrator,
        debug: true,
        console: mock_console,
        application: application
      )

      allow(history).to receive(:workers_idle?).and_return(true)
      allow(history).to receive(:get_int).with("messages_verbosity", default: 0).and_return(3)

      expect(mock_console).to receive(:puts).with("")
      expect(mock_console).to receive(:puts).with("\e[90m[Message Out] Created message\e[0m")
      expect(mock_console).to receive(:puts).with("\e[90m  role: user\e[0m")
      expect(mock_console).to receive(:puts).with("\e[90m  actor: test\e[0m")
      expect(mock_console).not_to receive(:show_spinner)

      formatter_with_app.display_message_created(
        actor: "test",
        role: "user"
      )
    end

    it "handles tool result display in debug mode" do
      formatter.debug = true

      message = {
        "id" => 1,
        "actor" => "orchestrator",
        "role" => "user",
        "tool_result" => {
          "name" => "file_read",
          "result" => { "content" => "test" }
        }
      }

      # Tool results should not be displayed when tools_verbosity is 0 (the default)
      # Even in debug mode, the tool verbosity setting should be respected
      expect(mock_console).not_to receive(:puts)

      formatter.display_message(message)
    end

    it "does not display thread event when debug is false" do
      expect(mock_console).not_to receive(:puts)

      formatter.display_thread_event("Test", "started")
    end

    it "normalizes system message with leading/trailing whitespace" do
      message = {
        "id" => 1,
        "role" => "system",
        "content" => "\n\n\nActual content\n\n\n"
      }

      expect(mock_console).to receive(:puts).with("\e[90m[System] Actual content\e[0m")

      formatter.display_message(message)
    end

    it "handles display_message_created with unknown role type" do
      application = instance_double("Application", history: history)
      formatter_with_app = described_class.new(
        history: history,
        session_start_time: session_start_time,
        conversation_id: conversation_id,
        orchestrator: orchestrator,
        debug: true,
        console: mock_console,
        application: application
      )

      allow(history).to receive(:workers_idle?).and_return(true)
      allow(history).to receive(:get_int).with("messages_verbosity", default: 0).and_return(2)

      expect(mock_console).to receive(:puts).with("")
      expect(mock_console).to receive(:puts).with("\e[90m[Message ] Created message\e[0m")

      formatter_with_app.display_message_created(actor: "test", role: "unknown")
    end

    it "handles tool result not in debug mode" do
      message = {
        "id" => 1,
        "actor" => "orchestrator",
        "role" => "user",
        "tool_result" => {
          "name" => "file_read",
          "result" => { "content" => "test" }
        }
      }

      expect(mock_console).not_to receive(:puts)

      formatter.display_message(message)
    end

    it "handles display_message_created when workers are not idle" do
      application = instance_double("Application", history: history)
      formatter_with_app = described_class.new(
        history: history,
        session_start_time: session_start_time,
        conversation_id: conversation_id,
        orchestrator: orchestrator,
        debug: true,
        console: mock_console,
        application: application
      )

      allow(history).to receive(:workers_idle?).and_return(false)
      allow(history).to receive(:get_int).with("messages_verbosity", default: 0).and_return(3)

      expect(mock_console).to receive(:puts).with("")
      expect(mock_console).to receive(:puts).with("\e[90m[Message Out] Created message\e[0m")
      expect(mock_console).to receive(:puts).with("\e[90m  role: user\e[0m")
      expect(mock_console).to receive(:puts).with("\e[90m  actor: test\e[0m")
      # No longer manually restart spinner - thread-safe puts handles output with spinner

      formatter_with_app.display_message_created(actor: "test", role: "user")
    end

    it "handles assistant message with nil tokens_output and no tool_calls in debug mode" do
      formatter.debug = true

      message = {
        "id" => 1,
        "actor" => "orchestrator",
        "role" => "assistant",
        "content" => "Response",
        "tokens_input" => 10,
        "tokens_output" => nil,
        "tool_calls" => nil
      }

      allow(history).to receive(:session_tokens).and_return({
                                                              "input" => 10,
                                                              "output" => 0,
                                                              "total" => 10,
                                                              "spend" => 0.000100
                                                            })

      expect(mock_console).to receive(:puts).with("")
      expect(mock_console).to receive(:puts).with("Response")

      formatter.display_message(message)
    end

    it "handles display_message_created with verbosity 2 (no detailed info)" do
      application = instance_double("Application", history: history)
      formatter_with_app = described_class.new(
        history: history,
        session_start_time: session_start_time,
        conversation_id: conversation_id,
        orchestrator: orchestrator,
        debug: true,
        console: mock_console,
        application: application
      )

      allow(history).to receive(:workers_idle?).and_return(true)
      allow(history).to receive(:get_int).with("messages_verbosity", default: 0).and_return(2)

      tool_calls = [{ "name" => "test", "arguments" => { "data" => "value" } }]

      expect(mock_console).to receive(:puts).with("")
      expect(mock_console).to receive(:puts).with("\e[90m[Message In] Created message\e[0m")
      expect(mock_console).not_to receive(:puts).with(/role:/)

      formatter_with_app.display_message_created(
        actor: "test",
        role: "assistant",
        tool_calls: tool_calls
      )
    end

    it "handles system message that becomes empty after normalization" do
      message = {
        "id" => 1,
        "role" => "system",
        "content" => ""
      }

      expect(mock_console).not_to receive(:puts)

      formatter.display_message(message)
    end

    it "handles debug setter when @llm_request_formatter is nil (defensive code)" do
      # This tests the defensive "if @llm_request_formatter" check
      # We need to bypass normal initialization to make formatter nil
      formatter_raw = described_class.allocate
      formatter_raw.instance_variable_set(:@debug, false)
      formatter_raw.instance_variable_set(:@llm_request_formatter, nil)

      # Should not crash when formatter is nil
      expect { formatter_raw.debug = true }.not_to raise_error
    end

    it "handles thread event display when workers become idle" do
      formatter.debug = true

      # Workers are idle, so no spinner restart
      allow(history).to receive(:workers_idle?).and_return(true)
      allow(history).to receive(:get_int).with("thread_verbosity", default: 0).and_return(1)

      # No longer manually hide/show spinner - thread-safe puts handles output
      expect(mock_console).to receive(:puts).with("")
      expect(mock_console).to receive(:puts).with("\e[90m[Thread] Test started\e[0m")

      formatter.display_thread_event("Test", "started")
    end

    it "does not display thread event when thread_verbosity is 0 even in debug mode" do
      formatter_with_app = described_class.new(
        history: history,
        session_start_time: session_start_time,
        conversation_id: conversation_id,
        orchestrator: orchestrator,
        debug: true,
        console: mock_console,
        application: application
      )

      allow(history).to receive(:get_int).with("thread_verbosity", default: 0).and_return(0)

      expect(mock_console).not_to receive(:puts)

      formatter_with_app.display_thread_event("Test", "started")
    end

    it "displays thread event when thread_verbosity is 1" do
      formatter_with_app = described_class.new(
        history: history,
        session_start_time: session_start_time,
        conversation_id: conversation_id,
        orchestrator: orchestrator,
        debug: true,
        console: mock_console,
        application: application
      )

      allow(history).to receive(:get_int).with("thread_verbosity", default: 0).and_return(1)

      expect(mock_console).to receive(:puts).with("")
      expect(mock_console).to receive(:puts).with("\e[90m[Thread] Test started\e[0m")

      formatter_with_app.display_thread_event("Test", "started")
    end

    it "handles display_message_created at verbosity 2 (does not display detailed info)" do
      application = instance_double("Application", history: history)
      formatter_with_app = described_class.new(
        history: history,
        session_start_time: session_start_time,
        conversation_id: conversation_id,
        orchestrator: orchestrator,
        debug: true,
        console: mock_console,
        application: application
      )

      allow(history).to receive(:workers_idle?).and_return(true)
      allow(history).to receive(:get_int).with("messages_verbosity", default: 0).and_return(2)

      expect(mock_console).to receive(:puts).with("")
      expect(mock_console).to receive(:puts).with("\e[90m[Message Out] Created message\e[0m")
      expect(mock_console).not_to receive(:puts).with(/role:/)
      expect(mock_console).not_to receive(:show_spinner)

      formatter_with_app.display_message_created(actor: "test", role: "user")
    end

    it "handles assistant message with tool_calls and no content (no empty warning)" do
      formatter.debug = true

      message = {
        "id" => 1,
        "actor" => "orchestrator",
        "role" => "assistant",
        "content" => "",
        "tokens_input" => 10,
        "tokens_output" => 5,
        "tool_calls" => [{ "name" => "test_tool", "arguments" => {} }]
      }

      allow(history).to receive(:session_tokens).and_return({
                                                              "input" => 10,
                                                              "output" => 5,
                                                              "total" => 15,
                                                              "spend" => 0.000150
                                                            })

      # Should not show empty response warning because tool_calls exist
      expect(mock_console).not_to receive(:puts).with(a_string_matching(/LLM returned empty response/))
      # Tool calls won't be displayed without an application
      expect(mock_console).not_to receive(:puts)

      formatter.display_message(message)
    end

    it "handles assistant message with zero tokens_output" do
      formatter.debug = true

      message = {
        "id" => 1,
        "actor" => "orchestrator",
        "role" => "assistant",
        "content" => "",
        "tokens_input" => 10,
        "tokens_output" => 0,
        "tool_calls" => nil
      }

      allow(history).to receive(:session_tokens).and_return({
                                                              "input" => 10,
                                                              "output" => 0,
                                                              "total" => 10,
                                                              "spend" => 0.000100
                                                            })

      # tokens_output is 0 (not positive), so no warning
      expect(mock_console).not_to receive(:puts).with(a_string_matching(/LLM returned empty response/))

      formatter.display_message(message)
    end
  end
end
