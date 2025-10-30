# frozen_string_literal: true

require "spec_helper"
require "nu/agent/metrics_collector"

RSpec.describe Nu::Agent::MetricsCollector do
  let(:collector) { described_class.new }

  describe "#increment" do
    it "increments a counter from 0 to 1" do
      collector.increment(:test_counter)
      expect(collector.get_counter(:test_counter)).to eq(1)
    end

    it "increments a counter multiple times" do
      5.times { collector.increment(:test_counter) }
      expect(collector.get_counter(:test_counter)).to eq(5)
    end

    it "supports incrementing by custom amounts" do
      collector.increment(:test_counter, 10)
      expect(collector.get_counter(:test_counter)).to eq(10)
    end

    it "handles multiple different counters" do
      collector.increment(:counter_a, 3)
      collector.increment(:counter_b, 7)
      expect(collector.get_counter(:counter_a)).to eq(3)
      expect(collector.get_counter(:counter_b)).to eq(7)
    end
  end

  describe "#record_duration" do
    it "records a single duration" do
      collector.record_duration(:test_timer, 100)
      stats = collector.get_timer_stats(:test_timer)
      expect(stats[:count]).to eq(1)
      expect(stats[:p50]).to eq(100)
      expect(stats[:p90]).to eq(100)
      expect(stats[:p99]).to eq(100)
    end

    it "computes percentiles for multiple durations" do
      # Record 100 durations: 1, 2, 3, ..., 100
      (1..100).each { |i| collector.record_duration(:test_timer, i) }

      stats = collector.get_timer_stats(:test_timer)
      expect(stats[:count]).to eq(100)
      expect(stats[:p50]).to be_within(2).of(50)
      expect(stats[:p90]).to be_within(2).of(90)
      expect(stats[:p99]).to be_within(2).of(99)
    end

    it "handles durations with fractional milliseconds" do
      collector.record_duration(:test_timer, 123.45)
      stats = collector.get_timer_stats(:test_timer)
      expect(stats[:p50]).to eq(123.45)
    end
  end

  describe "#get_counter" do
    it "returns 0 for non-existent counter" do
      expect(collector.get_counter(:nonexistent)).to eq(0)
    end
  end

  describe "#get_timer_stats" do
    it "returns default stats for non-existent timer" do
      stats = collector.get_timer_stats(:nonexistent)
      expect(stats[:count]).to eq(0)
      expect(stats[:p50]).to eq(0)
      expect(stats[:p90]).to eq(0)
      expect(stats[:p99]).to eq(0)
    end
  end

  describe "#snapshot" do
    it "returns all metrics in a single hash" do
      collector.increment(:counter_a, 5)
      collector.increment(:counter_b, 10)
      collector.record_duration(:timer_a, 100)
      collector.record_duration(:timer_a, 200)

      snapshot = collector.snapshot
      expect(snapshot[:counters][:counter_a]).to eq(5)
      expect(snapshot[:counters][:counter_b]).to eq(10)
      expect(snapshot[:timers][:timer_a][:count]).to eq(2)
    end

    it "returns empty hashes for no metrics" do
      snapshot = collector.snapshot
      expect(snapshot[:counters]).to eq({})
      expect(snapshot[:timers]).to eq({})
    end
  end

  describe "#reset" do
    it "clears all counters and timers" do
      collector.increment(:counter_a, 5)
      collector.record_duration(:timer_a, 100)

      collector.reset

      expect(collector.get_counter(:counter_a)).to eq(0)
      stats = collector.get_timer_stats(:timer_a)
      expect(stats[:count]).to eq(0)
    end
  end

  describe "thread safety" do
    it "handles concurrent increments correctly" do
      threads = 10.times.map do
        Thread.new do
          100.times { collector.increment(:concurrent_counter) }
        end
      end

      threads.each(&:join)

      expect(collector.get_counter(:concurrent_counter)).to eq(1000)
    end

    it "handles concurrent duration recordings correctly" do
      threads = 10.times.map do
        Thread.new do
          100.times { |i| collector.record_duration(:concurrent_timer, i) }
        end
      end

      threads.each(&:join)

      stats = collector.get_timer_stats(:concurrent_timer)
      expect(stats[:count]).to eq(1000)
    end
  end
end
