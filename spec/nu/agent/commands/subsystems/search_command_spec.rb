# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/subsystems/search_command"

RSpec.describe Nu::Agent::Commands::Subsystems::SearchCommand do
  let(:application) { instance_double("Nu::Agent::Application") }
  let(:history) { instance_double("Nu::Agent::History") }
  let(:console) { instance_double("Nu::Agent::ConsoleIO") }
  let(:command) { described_class.new(application) }

  before do
    allow(application).to receive_messages(history: history, console: console)
    allow(console).to receive(:puts)
    allow(application).to receive(:output_line)
    allow(application).to receive(:output_lines)
  end

  describe "#initialize" do
    it "initializes with correct subsystem name and config key" do
      expect(command.instance_variable_get(:@subsystem_name)).to eq("search")
      expect(command.instance_variable_get(:@config_key)).to eq("search_verbosity")
    end
  end

  describe "#execute" do
    it "shows help text with verbosity levels" do
      expect(application).to receive(:output_lines) do |*lines|
        expect(lines.flatten.any? { |line| line.include?("Search Subsystem") }).to be true
        expect(lines.flatten.any? { |line| line.include?("0 - No search debug output") }).to be true
      end
      command.execute("help")
    end
  end
end
