# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::EventBus do
  subject(:event_bus) { described_class.new }

  describe "#initialize" do
    it "creates an empty subscribers hash" do
      expect(event_bus.instance_variable_get(:@subscribers)).to be_a(Hash)
      expect(event_bus.instance_variable_get(:@subscribers)).to be_empty
    end

    it "initializes a mutex for thread safety" do
      expect(event_bus.instance_variable_get(:@mutex)).to be_a(Mutex)
    end
  end

  describe "#subscribe" do
    it "registers a subscriber for an event type" do
      callback = proc { |_data| }
      event_bus.subscribe(:test_event, &callback)

      subscribers = event_bus.instance_variable_get(:@subscribers)
      expect(subscribers[:test_event]).to include(callback)
    end

    it "allows multiple subscribers for the same event type" do
      callback1 = proc { |_data| }
      callback2 = proc { |_data| }

      event_bus.subscribe(:test_event, &callback1)
      event_bus.subscribe(:test_event, &callback2)

      subscribers = event_bus.instance_variable_get(:@subscribers)
      expect(subscribers[:test_event]).to include(callback1, callback2)
    end

    it "returns the callback for later unsubscription" do
      callback = proc { |_data| }
      result = event_bus.subscribe(:test_event, &callback)

      expect(result).to eq(callback)
    end

    it "raises error if no block given" do
      expect { event_bus.subscribe(:test_event) }.to raise_error(ArgumentError)
    end
  end

  describe "#unsubscribe" do
    it "removes a specific subscriber" do
      callback1 = proc { |_data| }
      callback2 = proc { |_data| }

      event_bus.subscribe(:test_event, &callback1)
      event_bus.subscribe(:test_event, &callback2)
      event_bus.unsubscribe(:test_event, callback1)

      subscribers = event_bus.instance_variable_get(:@subscribers)
      expect(subscribers[:test_event]).not_to include(callback1)
      expect(subscribers[:test_event]).to include(callback2)
    end

    it "does nothing if event type doesn't exist" do
      callback = proc { |_data| }

      expect { event_bus.unsubscribe(:nonexistent, callback) }.not_to raise_error
    end

    it "does nothing if callback not found" do
      callback1 = proc { |_data| }
      callback2 = proc { |_data| }

      event_bus.subscribe(:test_event, &callback1)

      expect { event_bus.unsubscribe(:test_event, callback2) }.not_to raise_error
    end
  end

  describe "#publish" do
    it "calls all subscribers for the event type" do
      results = []
      callback1 = proc { |data| results << "callback1: #{data}" }
      callback2 = proc { |data| results << "callback2: #{data}" }

      event_bus.subscribe(:test_event, &callback1)
      event_bus.subscribe(:test_event, &callback2)
      event_bus.publish(:test_event, "test data")

      expect(results).to contain_exactly("callback1: test data", "callback2: test data")
    end

    it "does nothing if no subscribers exist" do
      expect { event_bus.publish(:nonexistent, "data") }.not_to raise_error
    end

    it "passes data to subscribers" do
      received_data = nil
      callback = proc { |data| received_data = data }

      event_bus.subscribe(:test_event, &callback)
      event_bus.publish(:test_event, { key: "value" })

      expect(received_data).to eq({ key: "value" })
    end

    it "handles nil data" do
      received_data = :not_set
      callback = proc { |data| received_data = data }

      event_bus.subscribe(:test_event, &callback)
      event_bus.publish(:test_event, nil)

      expect(received_data).to be_nil
    end

    it "continues if a subscriber raises an error" do
      results = []
      callback1 = proc { |_data| raise "Error in callback1" }
      callback2 = proc { |data| results << data }

      event_bus.subscribe(:test_event, &callback1)
      event_bus.subscribe(:test_event, &callback2)

      expect { event_bus.publish(:test_event, "test") }.not_to raise_error
      expect(results).to eq(["test"])
    end
  end

  describe "thread safety" do
    it "handles concurrent subscriptions safely" do
      threads = []
      10.times do |i|
        threads << Thread.new do
          event_bus.subscribe(:"event_#{i}") { |_data| nil }
        end
      end
      threads.each(&:join)

      subscribers = event_bus.instance_variable_get(:@subscribers)
      expect(subscribers.keys.length).to eq(10)
    end

    it "handles concurrent publications safely" do
      counter = 0
      mutex = Mutex.new

      callback = proc do |_data|
        mutex.synchronize { counter += 1 }
      end

      event_bus.subscribe(:test_event, &callback)

      threads = []
      10.times do
        threads << Thread.new { event_bus.publish(:test_event, "data") }
      end
      threads.each(&:join)

      expect(counter).to eq(10)
    end
  end

  describe "event types" do
    it "supports user_input_received event" do
      received = false
      event_bus.subscribe(:user_input_received) { |_data| received = true }
      event_bus.publish(:user_input_received, "input text")

      expect(received).to be true
    end

    it "supports assistant_token_streamed event" do
      received = false
      event_bus.subscribe(:assistant_token_streamed) { |_data| received = true }
      event_bus.publish(:assistant_token_streamed, "token")

      expect(received).to be true
    end

    it "supports exchange_completed event" do
      received = false
      event_bus.subscribe(:exchange_completed) { |_data| received = true }
      event_bus.publish(:exchange_completed, { exchange_id: 1 })

      expect(received).to be true
    end

    it "supports worker_status_updated event" do
      received = false
      event_bus.subscribe(:worker_status_updated) { |_data| received = true }
      event_bus.publish(:worker_status_updated, { worker: "summarizer", status: "idle" })

      expect(received).to be true
    end
  end

  describe "#clear" do
    it "removes all subscribers" do
      event_bus.subscribe(:event1) { |_data| nil }
      event_bus.subscribe(:event2) { |_data| nil }

      event_bus.clear

      subscribers = event_bus.instance_variable_get(:@subscribers)
      expect(subscribers).to be_empty
    end
  end

  describe "#subscriber_count" do
    it "returns total number of subscribers" do
      event_bus.subscribe(:event1) { |_data| nil }
      event_bus.subscribe(:event1) { |_data| nil }
      event_bus.subscribe(:event2) { |_data| nil }

      expect(event_bus.subscriber_count).to eq(3)
    end

    it "returns 0 when no subscribers" do
      expect(event_bus.subscriber_count).to eq(0)
    end
  end

  describe "#subscribers?" do
    it "returns true when event type has subscribers" do
      event_bus.subscribe(:test_event) { |_data| nil }

      expect(event_bus.subscribers?(:test_event)).to be true
    end

    it "returns false when event type has no subscribers" do
      expect(event_bus.subscribers?(:test_event)).to be false
    end
  end
end
