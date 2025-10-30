# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::Workers::ExchangeSummarizer do
  let(:history) { instance_double(Nu::Agent::History) }
  let(:summarizer) { instance_double(Nu::Agent::Clients::Anthropic) }
  let(:application) { instance_double(Nu::Agent::Application) }
  let(:config_store) { instance_double(Nu::Agent::ConfigStore) }
  let(:status_mutex) { Mutex.new }
  let(:exchange_summarizer_status) do
    {
      "running" => false,
      "total" => 0,
      "completed" => 0,
      "failed" => 0,
      "current_exchange_id" => nil,
      "last_summary" => nil,
      "spend" => 0.0
    }
  end

  describe "#initialize" do
    it "initializes with required dependencies" do
      allow(config_store).to receive(:get_int).with("exchange_summarizer_verbosity", default: 0).and_return(0)

      summarizer_worker = described_class.new(
        history: history,
        summarizer: summarizer,
        application: application,
        status_info: { status: exchange_summarizer_status, mutex: status_mutex },
        current_conversation_id: 1,
        config_store: config_store
      )

      expect(summarizer_worker).to be_a(described_class)
    end

    it "loads verbosity from config store dynamically on each debug_output call" do
      allow(config_store).to receive(:get_int).with("exchange_summarizer_verbosity", default: 0).and_return(2)
      allow(application).to receive(:debug).and_return(true)
      allow(application).to receive(:output_line)

      summarizer_worker = described_class.new(
        history: history,
        summarizer: summarizer,
        application: application,
        status_info: { status: exchange_summarizer_status, mutex: status_mutex },
        current_conversation_id: 1,
        config_store: config_store
      )

      # Call debug_output to trigger verbosity loading
      summarizer_worker.send(:debug_output, "test message", level: 1)

      expect(config_store).to have_received(:get_int).with("exchange_summarizer_verbosity", default: 0)
    end
  end

  describe "#start_worker" do
    let(:summarizer_worker) do
      allow(config_store).to receive(:get_int).with("exchange_summarizer_verbosity", default: 0).and_return(0)
      described_class.new(
        history: history,
        summarizer: summarizer,
        application: application,
        status_info: { status: exchange_summarizer_status, mutex: status_mutex },
        current_conversation_id: 1,
        config_store: config_store
      )
    end

    it "spawns a background thread" do
      # Mock the summarization process to block indefinitely so thread stays alive
      semaphore = Queue.new
      allow(summarizer_worker).to receive(:summarize_exchanges) { semaphore.pop }

      thread = summarizer_worker.start_worker

      # Give thread time to start
      sleep(0.01)

      expect(thread).to be_a(Thread)
      expect(thread).to be_alive

      # Clean up
      thread.kill
      thread.join
    end

    it "handles StandardError and sets running to false" do
      # Mock summarize_exchanges to raise an error
      allow(summarizer_worker).to receive(:summarize_exchanges).and_raise(StandardError.new("Test error"))

      # Start worker and let it crash
      thread = summarizer_worker.start_worker
      sleep(0.05) # Give thread time to crash

      # Verify status was updated
      expect(exchange_summarizer_status["running"]).to be false

      thread.join(1) # Clean up
    end
  end

  describe "#summarize_exchanges" do
    let(:summarizer_worker) do
      allow(config_store).to receive(:get_int).with("exchange_summarizer_verbosity", default: 0).and_return(0)
      described_class.new(
        history: history,
        summarizer: summarizer,
        application: application,
        status_info: { status: exchange_summarizer_status, mutex: status_mutex },
        current_conversation_id: 1,
        config_store: config_store
      )
    end

    before do
      # Mock shutdown check
      allow(application).to receive(:instance_variable_get).with(:@shutdown).and_return(false)
      # Mock debug mode
      allow(application).to receive(:debug).and_return(false)
    end

    it "returns early when no exchanges need summarization" do
      allow(history).to receive(:get_unsummarized_exchanges).with(exclude_conversation_id: 1).and_return([])

      summarizer_worker.summarize_exchanges

      expect(exchange_summarizer_status["running"]).to be false
    end

    it "handles empty exchanges (no messages)" do
      exchange = { "id" => 100, "conversation_id" => 2 }
      allow(history).to receive(:get_unsummarized_exchanges).with(exclude_conversation_id: 1).and_return([exchange])
      allow(history).to receive(:messages).with(
        conversation_id: 2,
        include_in_context_only: false
      ).and_return([])
      allow(summarizer).to receive(:model).and_return("claude-sonnet-4-5")
      allow(application).to receive(:send).with(:enter_critical_section)
      allow(application).to receive(:send).with(:exit_critical_section)
      allow(history).to receive(:update_exchange_summary)

      summarizer_worker.summarize_exchanges

      expect(exchange_summarizer_status["completed"]).to eq(1)
      expect(exchange_summarizer_status["last_summary"]).to eq("empty exchange")
    end

    it "summarizes exchanges with messages" do
      exchange = { "id" => 100, "conversation_id" => 2, "exchange_number" => 1 }
      messages = [
        { "role" => "user", "content" => "What is Ruby?", "redacted" => false, "exchange_id" => 100 },
        { "role" => "assistant", "content" => "Ruby is a programming language.", "redacted" => false,
          "exchange_id" => 100 }
      ]
      allow(history).to receive(:get_unsummarized_exchanges).with(exclude_conversation_id: 1).and_return([exchange])
      allow(history).to receive(:messages).with(
        conversation_id: 2,
        include_in_context_only: false
      ).and_return(messages)
      allow(summarizer).to receive_messages(model: "claude-sonnet-4-5", send_message: {
                                              "content" => "User asked about Ruby programming language.",
                                              "spend" => 0.0005
                                            })
      allow(application).to receive(:send).with(:enter_critical_section)
      allow(application).to receive(:send).with(:exit_critical_section)
      allow(history).to receive(:update_exchange_summary)

      summarizer_worker.summarize_exchanges

      expect(exchange_summarizer_status["completed"]).to eq(1)
      expect(exchange_summarizer_status["last_summary"]).to eq("User asked about Ruby programming language.")
      expect(exchange_summarizer_status["spend"]).to eq(0.0005)
    end

    it "filters messages by exchange_id" do
      exchange = { "id" => 100, "conversation_id" => 2, "exchange_number" => 1 }
      messages = [
        { "role" => "user", "content" => "First exchange", "redacted" => false, "exchange_id" => 99 },
        { "role" => "user", "content" => "Second exchange", "redacted" => false, "exchange_id" => 100 },
        { "role" => "assistant", "content" => "Response to second", "redacted" => false, "exchange_id" => 100 }
      ]
      allow(history).to receive(:get_unsummarized_exchanges).with(exclude_conversation_id: 1).and_return([exchange])
      allow(history).to receive(:messages).with(
        conversation_id: 2,
        include_in_context_only: false
      ).and_return(messages)
      allow(summarizer).to receive(:model).and_return("claude-sonnet-4-5")

      # Capture the actual prompt sent to verify only exchange 100 messages are included
      captured_prompt = nil
      allow(summarizer).to receive(:send_message) do |args|
        captured_prompt = args[:messages].first["content"]
        { "content" => "Summary", "spend" => 0.001 }
      end

      allow(application).to receive(:send).with(:enter_critical_section)
      allow(application).to receive(:send).with(:exit_critical_section)
      allow(history).to receive(:update_exchange_summary)

      summarizer_worker.summarize_exchanges

      # Verify only exchange 100 messages were included in prompt
      expect(captured_prompt).to include("user: Second exchange")
      expect(captured_prompt).to include("assistant: Response to second")
      expect(captured_prompt).not_to include("First exchange")
    end

    it "handles API errors gracefully" do
      exchange = { "id" => 100, "conversation_id" => 2, "exchange_number" => 1 }
      messages = [{ "role" => "user", "content" => "Hello", "redacted" => false, "exchange_id" => 100 }]
      allow(history).to receive(:get_unsummarized_exchanges).with(exclude_conversation_id: 1).and_return([exchange])
      allow(history).to receive(:messages).with(
        conversation_id: 2,
        include_in_context_only: false
      ).and_return(messages)
      allow(summarizer).to receive(:send_message).and_return({ "error" => "API error" })

      summarizer_worker.summarize_exchanges

      expect(exchange_summarizer_status["failed"]).to eq(1)
      expect(exchange_summarizer_status["completed"]).to eq(0)
    end

    it "filters redacted messages" do
      exchange = { "id" => 100, "conversation_id" => 2, "exchange_number" => 1 }
      messages = [
        { "role" => "user", "content" => "Hello", "redacted" => false, "exchange_id" => 100 },
        { "role" => "assistant", "content" => "Tool call", "redacted" => true, "exchange_id" => 100 },
        { "role" => "assistant", "content" => "Hi there!", "redacted" => false, "exchange_id" => 100 }
      ]
      allow(history).to receive(:get_unsummarized_exchanges).with(exclude_conversation_id: 1).and_return([exchange])
      allow(history).to receive(:messages).with(
        conversation_id: 2,
        include_in_context_only: false
      ).and_return(messages)
      allow(summarizer).to receive(:model).and_return("claude-sonnet-4-5")

      # Capture the actual prompt sent to verify redacted messages are filtered
      captured_prompt = nil
      allow(summarizer).to receive(:send_message) do |args|
        captured_prompt = args[:messages].first["content"]
        { "content" => "Summary", "spend" => 0.001 }
      end

      allow(application).to receive(:send).with(:enter_critical_section)
      allow(application).to receive(:send).with(:exit_critical_section)
      allow(history).to receive(:update_exchange_summary)

      summarizer_worker.summarize_exchanges

      # Verify redacted message was not included in prompt
      expect(captured_prompt).to include("user: Hello")
      expect(captured_prompt).to include("assistant: Hi there!")
      expect(captured_prompt).not_to include("Tool call")
    end

    it "handles exceptions during exchange processing" do
      exchange = { "id" => 100, "conversation_id" => 2 }
      allow(history).to receive(:get_unsummarized_exchanges).with(exclude_conversation_id: 1).and_return([exchange])
      allow(history).to receive(:messages).and_raise(StandardError.new("Database error"))
      allow(history).to receive(:create_failed_job)

      summarizer_worker.summarize_exchanges

      expect(exchange_summarizer_status["failed"]).to eq(1)
    end

    it "handles empty summary response" do
      exchange = { "id" => 100, "conversation_id" => 2, "exchange_number" => 1 }
      messages = [{ "role" => "user", "content" => "Hello", "redacted" => false, "exchange_id" => 100 }]
      allow(history).to receive(:get_unsummarized_exchanges).with(exclude_conversation_id: 1).and_return([exchange])
      allow(history).to receive(:messages).with(
        conversation_id: 2,
        include_in_context_only: false
      ).and_return(messages)
      allow(summarizer).to receive(:send_message).and_return({ "content" => "", "spend" => 0.001 })

      summarizer_worker.summarize_exchanges

      expect(exchange_summarizer_status["failed"]).to eq(1)
      expect(exchange_summarizer_status["completed"]).to eq(0)
    end

    it "handles shutdown during LLM call" do
      exchange = { "id" => 100, "conversation_id" => 2, "exchange_number" => 1 }
      messages = [{ "role" => "user", "content" => "Hello", "redacted" => false, "exchange_id" => 100 }]
      allow(history).to receive(:get_unsummarized_exchanges).with(exclude_conversation_id: 1).and_return([exchange])
      allow(history).to receive(:messages).with(
        conversation_id: 2,
        include_in_context_only: false
      ).and_return(messages)

      # Mock a slow LLM call that takes longer than the shutdown check
      call_count = 0
      allow(application).to receive(:instance_variable_get).with(:@shutdown) do
        call_count += 1
        call_count > 2 # Return false initially, then true to trigger shutdown
      end

      # Mock a slow send_message call
      allow(summarizer).to receive(:send_message) do
        sleep(0.3) # Simulate slow API call
        { "content" => "Summary", "spend" => 0.001 }
      end

      summarizer_worker.summarize_exchanges

      # No summary should be saved due to shutdown
      expect(exchange_summarizer_status["completed"]).to eq(0)
    end
  end

  describe "#debug_output" do
    let(:summarizer_worker) do
      allow(config_store).to receive(:get_int).with("exchange_summarizer_verbosity", default: 0).and_return(verbosity)
      described_class.new(
        history: history,
        summarizer: summarizer,
        application: application,
        status_info: { status: exchange_summarizer_status, mutex: status_mutex },
        current_conversation_id: 1,
        config_store: config_store
      )
    end

    context "when debug is disabled" do
      let(:verbosity) { 3 }

      it "does not output anything" do
        allow(application).to receive(:debug).and_return(false)
        expect(application).not_to receive(:output_line)

        summarizer_worker.send(:debug_output, "test message", level: 0)
      end
    end

    context "when debug is enabled" do
      before do
        allow(application).to receive(:debug).and_return(true)
      end

      context "with verbosity 0" do
        let(:verbosity) { 0 }

        it "outputs level 0 messages" do
          expect(application).to receive(:output_line).with("[ExchangeSummarizer] test message", type: :debug)
          summarizer_worker.send(:debug_output, "test message", level: 0)
        end

        it "does not output level 1 messages" do
          expect(application).not_to receive(:output_line)
          summarizer_worker.send(:debug_output, "test message", level: 1)
        end
      end

      context "with verbosity 2" do
        let(:verbosity) { 2 }

        it "outputs level 0 messages" do
          expect(application).to receive(:output_line).with("[ExchangeSummarizer] level 0", type: :debug)
          summarizer_worker.send(:debug_output, "level 0", level: 0)
        end

        it "outputs level 1 messages" do
          expect(application).to receive(:output_line).with("[ExchangeSummarizer] level 1", type: :debug)
          summarizer_worker.send(:debug_output, "level 1", level: 1)
        end

        it "outputs level 2 messages" do
          expect(application).to receive(:output_line).with("[ExchangeSummarizer] level 2", type: :debug)
          summarizer_worker.send(:debug_output, "level 2", level: 2)
        end

        it "does not output level 3 messages" do
          expect(application).not_to receive(:output_line)
          summarizer_worker.send(:debug_output, "level 3", level: 3)
        end
      end
    end
  end
end
