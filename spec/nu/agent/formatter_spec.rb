# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::Formatter do
  let(:history) { instance_double(Nu::Agent::History) }
  let(:orchestrator) { instance_double("Orchestrator", max_context: 200_000) }
  let(:mock_console) do
    instance_double(
      Nu::Agent::ConsoleIO,
      puts: nil,
      show_spinner: nil,
      hide_spinner: nil
    )
  end
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
      application: nil
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
        allow(history).to receive(:messages_since).and_return(messages)
        allow(history).to receive(:workers_idle?).and_return(true)
        allow(history).to receive(:session_tokens).and_return({
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

        # Enable debug mode to show token stats
        formatter.debug = true

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
    let(:application) { instance_double("Application") }
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
      allow(history).to receive(:session_tokens).and_return({
                                                              "input" => 20,
                                                              "output" => 10,
                                                              "total" => 30,
                                                              "spend" => 0.000300
                                                            })
      allow(history).to receive(:workers_idle?).and_return(true)
    end

    describe "level 0: tool name only" do
      before do
        allow(application).to receive(:verbosity).and_return(0)
      end

      it "displays tool call name without arguments" do
        expect(mock_console).to receive(:puts).with("\e[90m[Tool Call Request] file_read\e[0m")

        formatter_with_app.display_message(tool_call_message)
      end

      it "displays tool result name without result details" do
        expect(mock_console).to receive(:puts).with("\e[90m[Tool Use Response] file_read\e[0m")

        formatter_with_app.display_message(tool_result_message)
      end
    end

    describe "level 1: tool name + first 30 chars of params + thread notifications" do
      before do
        allow(application).to receive(:verbosity).and_return(1)
      end

      it "displays tool call arguments truncated to 30 characters" do
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

    describe "level 2: truncated params (same as level 1)" do
      before do
        allow(application).to receive(:verbosity).and_return(2)
      end

      it "displays tool call arguments truncated to 30 chars" do
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

    describe "level 3: truncated params (same as levels 1-2)" do
      before do
        allow(application).to receive(:verbosity).and_return(3)
      end

      it "displays tool call arguments truncated to 30 chars" do
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
    let(:formatter_debug) do
      described_class.new(
        history: history,
        session_start_time: session_start_time,
        conversation_id: conversation_id,
        orchestrator: orchestrator,
        debug: true,
        console: mock_console,
        application: nil
      )
    end

    context "thread events" do
      before do
        allow(history).to receive(:workers_idle?).and_return(true)
      end

      it "adds blank line before thread event output" do
        expect(mock_console).to receive(:puts).with("").ordered
        expect(mock_console).to receive(:puts).with("\e[90m[Thread] Orchestrator Starting\e[0m").ordered

        formatter_debug.display_thread_event("Orchestrator", "Starting")
      end
    end

    context "spell checker messages" do
      it "adds blank line before spell check request" do
        message = {
          "id" => 1,
          "actor" => "spell_checker",
          "role" => "user",
          "content" => "Fix this text"
        }

        expect(mock_console).to receive(:puts).with("").ordered
        expect(mock_console).to receive(:puts).with("\e[90m[Spell Check Request]\e[0m").ordered
        expect(mock_console).to receive(:puts).with("\e[90mFix this text\e[0m").ordered

        formatter_debug.display_message(message)
      end

      it "adds blank line before spell check result" do
        message = {
          "id" => 2,
          "actor" => "spell_checker",
          "role" => "assistant",
          "content" => "corrected"
        }

        expect(mock_console).to receive(:puts).with("").ordered
        expect(mock_console).to receive(:puts).with("\e[90m[Spell Check Result]\e[0m").ordered
        expect(mock_console).to receive(:puts).with("\e[90mcorrected\e[0m").ordered

        formatter_debug.display_message(message)
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
end
