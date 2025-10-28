# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::Spinner do
  subject(:spinner) { described_class.new }

  let(:captured_output) { StringIO.new }

  before do
    allow($stdout).to receive(:flush)
    allow($stdout).to receive(:write) { |text| captured_output.write(text) }
    allow_any_instance_of(Kernel).to receive(:print) { |_, text| captured_output.write(text) }
  end

  after do
    spinner.stop if spinner.instance_variable_get(:@running)
  end

  describe "#initialize" do
    it "sets the message to empty string by default" do
      expect(spinner.instance_variable_get(:@message)).to eq("")
    end

    it "sets the message when provided" do
      spinner_with_message = described_class.new("Loading...")
      expect(spinner_with_message.instance_variable_get(:@message)).to eq("Loading...")
    end

    it "initializes running to false" do
      expect(spinner.instance_variable_get(:@running)).to be false
    end

    it "initializes thread to nil" do
      expect(spinner.instance_variable_get(:@thread)).to be_nil
    end

    it "initializes start_time to nil" do
      expect(spinner.instance_variable_get(:@start_time)).to be_nil
    end
  end

  describe "#start" do
    it "starts the spinner" do
      spinner.start("Processing...")
      expect(spinner.instance_variable_get(:@running)).to be true
      spinner.stop
    end

    it "creates a thread" do
      spinner.start("Working...")
      expect(spinner.instance_variable_get(:@thread)).to be_a(Thread)
      spinner.stop
    end

    it "sets the message when provided" do
      spinner.start("Custom message")
      expect(spinner.instance_variable_get(:@message)).to eq("Custom message")
      spinner.stop
    end

    it "keeps existing message when not provided" do
      spinner = described_class.new("Initial message")
      spinner.start
      expect(spinner.instance_variable_get(:@message)).to eq("Initial message")
      spinner.stop
    end

    it "sets start_time when provided" do
      start_time = Time.now - 100
      spinner.start("Timing...", start_time: start_time)
      expect(spinner.instance_variable_get(:@start_time)).to eq(start_time)
      spinner.stop
    end

    it "does not start if already running" do
      spinner.start("First")
      original_thread = spinner.instance_variable_get(:@thread)
      spinner.start("Second")
      expect(spinner.instance_variable_get(:@thread)).to eq(original_thread)
      expect(spinner.instance_variable_get(:@message)).to eq("First")
      spinner.stop
    end

    it "initializes frame_index to 0" do
      spinner.start("Spinning...")
      expect(spinner.instance_variable_get(:@frame_index)).to eq(0)
      spinner.stop
    end

    it "animates frames" do
      spinner.start("Animating...")
      sleep 0.25 # Allow a few frames
      spinner.stop
      output = captured_output.string
      expect(output).to match(/⠋|⠙|⠹|⠸|⠼|⠴|⠦|⠧|⠇|⠏/)
    end
  end

  describe "#stop" do
    it "stops the spinner when running" do
      spinner.start("Running...")
      spinner.stop
      expect(spinner.instance_variable_get(:@running)).to be false
    end

    it "clears the thread when stopped" do
      spinner.start("Running...")
      spinner.stop
      expect(spinner.instance_variable_get(:@thread)).to be_nil
    end

    it "does nothing when not running" do
      expect { spinner.stop }.not_to raise_error
      expect(spinner.instance_variable_get(:@running)).to be false
    end

    it "clears the line on stop" do
      spinner.start("Clear me...")
      sleep 0.15
      captured_output.truncate(0)
      captured_output.rewind
      spinner.stop
      expect(captured_output.string).to include("\r\e[K")
    end
  end

  describe "#update_message" do
    it "updates the message while running" do
      spinner.start("Original")
      spinner.update_message("Updated")
      expect(spinner.instance_variable_get(:@message)).to eq("Updated")
      spinner.stop
    end

    it "updates the message when not running" do
      spinner.update_message("New message")
      expect(spinner.instance_variable_get(:@message)).to eq("New message")
    end
  end

  describe "elapsed time formatting" do
    it "formats elapsed time in seconds (< 60s)" do
      start_time = Time.now - 30.5
      spinner.start("Timing...", start_time: start_time)
      sleep 0.15
      spinner.stop
      output = captured_output.string
      expect(output).to match(/30\.\ds/)
    end

    it "formats elapsed time in minutes and seconds (< 1 hour)" do
      start_time = Time.now - 125 # 2 minutes 5 seconds
      spinner.start("Timing...", start_time: start_time)
      sleep 0.15
      spinner.stop
      output = captured_output.string
      expect(output).to match(/2m \d+s/)
    end

    it "formats elapsed time in hours and minutes (>= 1 hour)" do
      start_time = Time.now - 7325 # 2 hours 2 minutes 5 seconds
      spinner.start("Timing...", start_time: start_time)
      sleep 0.15
      spinner.stop
      output = captured_output.string
      expect(output).to match(/2h \d+m/)
    end

    it "displays message without time when start_time is not set" do
      spinner.start("No timing")
      sleep 0.15
      spinner.stop
      output = captured_output.string
      expect(output).to include("No timing")
      # Should not have time format like "(30.5s)" or "(2m 5s)"
      expect(output).not_to match(/\(\d+\.\d+s\)/)
      expect(output).not_to match(/\(\d+m \d+s\)/)
      expect(output).not_to match(/\(\d+h \d+m\)/)
    end
  end

  describe "thread safety" do
    it "handles concurrent start calls safely" do
      threads = 3.times.map do
        Thread.new { spinner.start("Concurrent") }
      end
      threads.each(&:join)
      expect(spinner.instance_variable_get(:@running)).to be true
      spinner.stop
    end

    it "handles concurrent stop calls safely" do
      spinner.start("Running...")
      threads = 3.times.map do
        Thread.new { spinner.stop }
      end
      threads.each(&:join)
      expect(spinner.instance_variable_get(:@running)).to be false
    end

    it "handles concurrent update_message calls safely" do
      spinner.start("Original")
      threads = 5.times.map do |i|
        Thread.new { spinner.update_message("Message #{i}") }
      end
      threads.each(&:join)
      expect(spinner.instance_variable_get(:@message)).to match(/Message \d/)
      spinner.stop
    end
  end

  describe "frame cycling" do
    it "cycles through all frames" do
      spinner.start("Cycling...")
      sleep 1.1 # Enough time for full cycle (10 frames * 0.1s = 1.0s)
      spinner.stop
      output = captured_output.string
      # Check that we see multiple different frames
      frame_count = described_class::FRAMES.count { |frame| output.include?(frame) }
      expect(frame_count).to be >= 5
    end
  end

  describe "output formatting" do
    it "uses light blue color in output" do
      spinner.start("Colored")
      sleep 0.15
      spinner.stop
      output = captured_output.string
      expect(output).to include("\e[94m") # Light blue
      expect(output).to include("\e[0m")  # Reset
    end

    it "includes the spinner frame in output" do
      spinner.start("Frame test")
      sleep 0.15
      spinner.stop
      output = captured_output.string
      has_frame = described_class::FRAMES.any? { |frame| output.include?(frame) }
      expect(has_frame).to be true
    end

    it "includes the message in output" do
      spinner.start("Test message")
      sleep 0.15
      spinner.stop
      output = captured_output.string
      expect(output).to include("Test message")
    end

    it "uses carriage return to overwrite line" do
      spinner.start("Overwriting...")
      sleep 0.15
      spinner.stop
      output = captured_output.string
      expect(output).to include("\r")
    end
  end
end
