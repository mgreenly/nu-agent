# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/help_command"

RSpec.describe Nu::Agent::Commands::HelpCommand do
  let(:app) do
    instance_double("Application",
                    console: console,
                    output_lines: nil,
                    registered_commands: {
                      "/help" => described_class,
                      "/verbosity" => double("VerbosityCommand", description: nil)
                    })
  end
  let(:console) { instance_double("ConsoleIO", puts: nil) }
  let(:command) { described_class.new(app) }

  describe "verbosity help text" do
    it "does not contain old detailed level descriptions" do
      # Capture the output
      output_lines = []
      allow(app).to receive(:output_lines) do |*lines, **_options|
        output_lines.concat(lines)
      end

      command.execute(nil)

      full_output = output_lines.join("\n")

      # Check that old level descriptions are NOT present
      expect(full_output).not_to include("Level 0: Thread lifecycle events")
      expect(full_output).not_to include("Level 1: Level 0 + truncated")
      expect(full_output).not_to include("Level 2: Level 1 + message creation")
      expect(full_output).not_to include("Level 3: Level 2 + message role")
      expect(full_output).not_to include("Level 4: Level 3 + full tool")
      expect(full_output).not_to include("Level 5: Level 4 + tools array")
      expect(full_output).not_to include("Level 6: Level 5 + longer message")
    end

    it "contains new simplified verbosity description" do
      # Capture the output
      output_lines = []
      allow(app).to receive(:output_lines) do |*lines, **_options|
        output_lines.concat(lines)
      end

      command.execute(nil)

      full_output = output_lines.join("\n")

      # Check that new text IS present
      expect(full_output).to include("Set verbosity levels for debugging")
      expect(full_output).to include("/verbosity [<subsystem>] [<level>]")
    end
  end
end
