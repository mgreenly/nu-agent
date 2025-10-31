# frozen_string_literal: true

require "spec_helper"
require "nu/agent/pausable_task"

module Nu
  module Agent
    module PausableTaskSpec
      # Concrete test implementation of PausableTask
      class TestTask < PausableTask
        attr_reader :work_count, :work_mutex

        def initialize(status_info:, shutdown_flag:)
          super
          @work_count = 0
          @work_mutex = Mutex.new
        end

        protected

        def do_work
          @work_mutex.synchronize { @work_count += 1 }
          sleep 0.1 # Simulate work
        end
      end

      # Failing task for error handling tests
      class FailingTask < PausableTask
        protected

        def do_work
          raise StandardError, "Test error"
        end
      end
    end
  end
end

RSpec.describe Nu::Agent::PausableTask do
  let(:status_mutex) { Mutex.new }
  let(:status_hash) { { "running" => false, "paused" => false } }
  let(:shutdown_flag) { { value: false } }

  describe "#initialize" do
    it "initializes with status hash and mutex" do
      task = Nu::Agent::PausableTaskSpec::TestTask.new(
        status_info: { status: status_hash, mutex: status_mutex },
        shutdown_flag: shutdown_flag
      )

      expect(task).to be_a(described_class)
    end
  end

  describe "#start_worker" do
    it "starts a background thread that performs work" do
      task = Nu::Agent::PausableTaskSpec::TestTask.new(
        status_info: { status: status_hash, mutex: status_mutex },
        shutdown_flag: shutdown_flag
      )

      thread = task.start_worker
      expect(thread).to be_a(Thread)
      expect(thread.alive?).to be true

      sleep 0.3 # Let it do some work

      shutdown_flag[:value] = true
      thread.join(1)
      expect(task.work_count).to be > 0
    end

    it "marks status as running when active" do
      task = Nu::Agent::PausableTaskSpec::TestTask.new(
        status_info: { status: status_hash, mutex: status_mutex },
        shutdown_flag: shutdown_flag
      )

      thread = task.start_worker
      sleep 0.2

      status_mutex.synchronize do
        expect(status_hash["running"]).to be true
      end

      shutdown_flag[:value] = true
      thread.join(1)
    end
  end

  describe "#pause and #resume" do
    it "pauses work execution when pause is called" do
      task = Nu::Agent::PausableTaskSpec::TestTask.new(
        status_info: { status: status_hash, mutex: status_mutex },
        shutdown_flag: shutdown_flag
      )

      thread = task.start_worker
      sleep 0.2 # Let first work cycle complete

      initial_count = task.work_count
      task.pause

      # Wait and verify work has paused
      # Need to wait through potential sleep cycles
      sleep 1.0
      paused_count = task.work_count
      expect(paused_count).to eq(initial_count)

      status_mutex.synchronize do
        expect(status_hash["paused"]).to be true
      end

      # Resume and verify work continues
      task.resume
      # Need to wait long enough for: any remaining sleep from previous cycle (up to 3s)
      # + wake from pause + check_pause + do_work (0.1s)
      # Being generous with timing to avoid flakiness
      sleep 4.0
      resumed_count = task.work_count
      expect(resumed_count).to be > paused_count

      status_mutex.synchronize do
        expect(status_hash["paused"]).to be false
      end

      shutdown_flag[:value] = true
      thread.join(1)
    end

    it "can be paused and resumed multiple times" do
      task = Nu::Agent::PausableTaskSpec::TestTask.new(
        status_info: { status: status_hash, mutex: status_mutex },
        shutdown_flag: shutdown_flag
      )

      thread = task.start_worker

      # First pause/resume cycle
      sleep 0.1
      task.pause
      sleep 0.1
      task.resume

      # Second pause/resume cycle
      sleep 0.1
      task.pause
      sleep 0.1
      task.resume

      sleep 0.1

      expect(task.work_count).to be > 0

      shutdown_flag[:value] = true
      thread.join(1)
    end
  end

  describe "#wait_until_paused" do
    it "returns true when task pauses within timeout" do
      task = Nu::Agent::PausableTaskSpec::TestTask.new(
        status_info: { status: status_hash, mutex: status_mutex },
        shutdown_flag: shutdown_flag
      )

      thread = task.start_worker
      sleep 0.1

      task.pause
      result = task.wait_until_paused(timeout: 2)

      expect(result).to be true

      shutdown_flag[:value] = true
      thread.join(1)
    end

    it "returns false when timeout is exceeded" do
      task = Nu::Agent::PausableTaskSpec::TestTask.new(
        status_info: { status: status_hash, mutex: status_mutex },
        shutdown_flag: shutdown_flag
      )

      # Don't start the worker, so it can't actually pause
      result = task.wait_until_paused(timeout: 0.1)

      expect(result).to be false
    end
  end

  describe "shutdown handling" do
    it "stops work when shutdown is requested" do
      task = Nu::Agent::PausableTaskSpec::TestTask.new(
        status_info: { status: status_hash, mutex: status_mutex },
        shutdown_flag: shutdown_flag
      )

      thread = task.start_worker
      sleep 0.2

      shutdown_flag[:value] = true
      thread.join(1)

      expect(thread.alive?).to be false
      status_mutex.synchronize do
        expect(status_hash["running"]).to be false
      end
    end

    it "exits cleanly even when paused" do
      task = Nu::Agent::PausableTaskSpec::TestTask.new(
        status_info: { status: status_hash, mutex: status_mutex },
        shutdown_flag: shutdown_flag
      )

      thread = task.start_worker
      sleep 0.2

      task.pause
      sleep 0.3 # Wait for pause to take effect

      shutdown_flag[:value] = true
      thread.join(2) # Give more time for shutdown while paused

      expect(thread.alive?).to be false
    end
  end

  describe "error handling" do
    it "marks status as not running on error" do
      task = Nu::Agent::PausableTaskSpec::FailingTask.new(
        status_info: { status: status_hash, mutex: status_mutex },
        shutdown_flag: shutdown_flag
      )

      thread = task.start_worker
      sleep 0.2

      status_mutex.synchronize do
        expect(status_hash["running"]).to be false
      end

      thread.join(1)
    end
  end

  describe "shutdown_flag variants" do
    it "works with a simple boolean shutdown flag" do
      # Test the else branch in shutdown_requested? method
      simple_flag = false
      task = Nu::Agent::PausableTaskSpec::TestTask.new(
        status_info: { status: status_hash, mutex: status_mutex },
        shutdown_flag: simple_flag
      )

      thread = task.start_worker
      sleep 0.2

      # Task should be running with non-hash flag
      expect(task.work_count).to be > 0

      # Can't set simple boolean flag from outside (it's not a reference)
      # So we just join with timeout which will eventually stop
      thread.kill
      thread.join(0.5)
    end

    it "checks shutdown after pausing and resuming" do
      task = Nu::Agent::PausableTaskSpec::TestTask.new(
        status_info: { status: status_hash, mutex: status_mutex },
        shutdown_flag: shutdown_flag
      )

      thread = task.start_worker
      sleep 0.2

      # Pause the task
      task.pause
      sleep 0.5

      # Request shutdown while paused
      shutdown_flag[:value] = true

      # Resume - should check shutdown and exit
      task.resume

      # Should exit quickly after resume
      expect(thread.join(2)).to eq(thread)
      expect(thread.alive?).to be false
    end
  end
end
