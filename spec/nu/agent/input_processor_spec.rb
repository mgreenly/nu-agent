# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::InputProcessor do
  let(:history) { instance_double(Nu::Agent::History) }
  let(:formatter) { instance_double(Nu::Agent::Formatter) }
  let(:console) { instance_double(Nu::Agent::ConsoleIO) }
  let(:orchestrator) { instance_double(Nu::Agent::Clients::Anthropic) }
  let(:event_bus) { instance_double(Nu::Agent::EventBus) }
  let(:operation_mutex) { Mutex.new }
  let(:active_threads) { [] }
  let(:application) do
    instance_double(
      Nu::Agent::Application,
      history: history,
      formatter: formatter,
      console: console,
      orchestrator: orchestrator,
      event_bus: event_bus,
      operation_mutex: operation_mutex,
      active_threads: active_threads,
      conversation_id: 1,
      session_start_time: Time.now - 3600,
      output_line: nil,
      debug: false
    )
  end
  let(:user_actor) { "testuser" }

  let(:processor) do
    described_class.new(
      application: application,
      user_actor: user_actor
    )
  end

  describe "#process" do
    context "when input is a command" do
      it "delegates to handle_command" do
        allow(application).to receive(:handle_command).with("/help").and_return(:continue)

        result = processor.process("/help")

        expect(result).to eq(:continue)
        expect(application).to have_received(:handle_command).with("/help")
      end
    end

    context "when input is regular text" do
      let(:input) { "Hello, how are you?" }
      let(:thread) { instance_double(Thread, alive?: false) }
      let(:chat_orchestrator) { instance_double(Nu::Agent::ChatLoopOrchestrator) }

      before do
        allow(formatter).to receive(:exchange_start_time=)
        allow(console).to receive(:show_spinner)
        allow(console).to receive(:hide_spinner)
        allow(history).to receive(:increment_workers)
        allow(history).to receive(:decrement_workers)
        allow(formatter).to receive(:display_thread_event)
        allow(formatter).to receive(:wait_for_completion)
        allow(Nu::Agent::ChatLoopOrchestrator).to receive(:new).and_return(chat_orchestrator)
        allow(chat_orchestrator).to receive(:execute)

        # Stub Thread.new to call the block immediately instead of spawning a thread
        allow(Thread).to receive(:new) do |*args, &block|
          block.call(*args)
          thread
        end
        allow(thread).to receive(:join)
      end

      it "starts spinner and increments workers" do
        processor.process(input)

        expect(console).to have_received(:show_spinner).with("Thinking...")
        expect(history).to have_received(:increment_workers)
      end

      it "creates ChatLoopOrchestrator and spawns thread" do
        processor.process(input)

        expect(Nu::Agent::ChatLoopOrchestrator).to have_received(:new).with(
          history: history,
          formatter: formatter,
          application: application,
          user_actor: user_actor,
          event_bus: event_bus
        )
        expect(chat_orchestrator).to have_received(:execute)
      end

      it "waits for completion and displays thread finished event" do
        processor.process(input)

        expect(formatter).to have_received(:wait_for_completion).with(conversation_id: 1)
        expect(formatter).to have_received(:display_thread_event).with("Orchestrator", "Finished")
      end

      it "hides spinner in ensure block" do
        processor.process(input)

        expect(console).to have_received(:hide_spinner)
      end

      it "returns :continue" do
        result = processor.process(input)

        expect(result).to eq(:continue)
      end

      context "when Interrupt is raised" do
        before do
          allow(formatter).to receive(:wait_for_completion).and_raise(Interrupt)
          allow(thread).to receive(:alive?).and_return(true)
          allow(thread).to receive(:kill)
        end

        it "hides spinner and outputs abort message" do
          processor.process(input)

          # hide_spinner is called twice - once in rescue block, once in ensure block
          expect(console).to have_received(:hide_spinner).at_least(:once)
          expect(application).to have_received(:output_line).with(
            "(Ctrl-C) Operation aborted by user.",
            type: :debug
          )
        end

        it "kills active threads and clears list" do
          active_threads << thread
          # Allow kill to be called multiple times since we add thread to active_threads twice
          allow(thread).to receive(:kill)

          processor.process(input)

          expect(thread).to have_received(:kill).at_least(:once)
          expect(active_threads).to be_empty
        end

        it "decrements workers" do
          processor.process(input)

          # Incremented once at start, decremented once in Interrupt handler
          expect(history).to have_received(:decrement_workers).at_least(:once)
        end
      end
    end
  end
end
