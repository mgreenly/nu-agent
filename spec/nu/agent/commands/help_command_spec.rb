# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/help_command"

RSpec.describe Nu::Agent::Commands::HelpCommand do
  let(:console) { instance_double("Nu::Agent::ConsoleIO") }
  let(:application) { instance_double("Nu::Agent::Application", console: console) }
  let(:command) { described_class.new(application) }

  describe "#execute" do
    before do
      allow(console).to receive(:puts)
      allow(application).to receive(:output_lines)
    end

    it "prints a blank line to console" do
      expect(console).to receive(:puts).with("")
      command.execute("/help")
    end

    it "outputs help text using output_lines" do
      expect(application).to receive(:output_lines) do |*lines, type:|
        expect(type).to eq(:command)
        expect(lines).to include(match(/Available commands/))
        expect(lines).to include(match(%r{/help.*Show this help message}))
      end
      command.execute("/help")
    end

    it "returns :continue" do
      expect(command.execute("/help")).to eq(:continue)
    end

    it "includes /worker command documentation" do
      expect(application).to receive(:output_lines) do |*lines, **_kwargs|
        help_text = lines.join("\n")
        expect(help_text).to match(%r{/worker.*Manage background workers})
      end
      command.execute("/help")
    end

    it "does not include deprecated /summarizer command" do
      expect(application).to receive(:output_lines) do |*lines, **_kwargs|
        help_text = lines.join("\n")
        expect(help_text).not_to match(%r{/summarizer})
      end
      command.execute("/help")
    end

    it "does not include deprecated /fix command" do
      expect(application).to receive(:output_lines) do |*lines, **_kwargs|
        help_text = lines.join("\n")
        expect(help_text).not_to match(%r{/fix.*Scan and fix database})
      end
      command.execute("/help")
    end

    it "does not include deprecated /index-man command" do
      expect(application).to receive(:output_lines) do |*lines, **_kwargs|
        help_text = lines.join("\n")
        expect(help_text).not_to match(%r{/index-man})
      end
      command.execute("/help")
    end

    it "includes /persona command documentation" do
      expect(application).to receive(:output_lines) do |*lines, **_kwargs|
        help_text = lines.join("\n")
        # Should be one-line like /worker pattern
        pattern = %r{/persona \[<name>\|<command>\]\s+-\s+Manage agent personas \(use /persona for details\)}
        expect(help_text).to match(pattern)
      end
      command.execute("/help")
    end

    describe "dynamic command listing" do
      it "includes all registered commands in help output" do
        expect(application).to receive(:output_lines) do |*lines, **_kwargs|
          help_text = lines.join("\n")
          # Check for all main commands
          expect(help_text).to match(%r{/help})
          expect(help_text).to match(%r{/exit})
          expect(help_text).to match(%r{/clear})
          expect(help_text).to match(%r{/reset})
          expect(help_text).to match(%r{/info})
          expect(help_text).to match(%r{/tools})
          expect(help_text).to match(%r{/verbosity})
          expect(help_text).to match(%r{/model})
          expect(help_text).to match(%r{/models})
          expect(help_text).to match(%r{/persona})
          expect(help_text).to match(%r{/personas})
          expect(help_text).to match(%r{/worker})
          expect(help_text).to match(%r{/rag})
          expect(help_text).to match(%r{/redaction})
          expect(help_text).to match(%r{/backup})
          expect(help_text).to match(%r{/migrate-exchanges})
          expect(help_text).to match(%r{/debug})
        end
        command.execute("/help")
      end

      it "includes subsystem commands in help output" do
        expect(application).to receive(:output_lines) do |*lines, **_kwargs|
          help_text = lines.join("\n")
          # Check for subsystem debug commands
          expect(help_text).to match(%r{/llm.*Manage LLM subsystem debugging})
          expect(help_text).to match(%r{/messages.*Manage Messages subsystem debugging})
          expect(help_text).to match(%r{/search.*Manage Search subsystem debugging})
          expect(help_text).to match(%r{/stats.*Manage Stats subsystem debugging})
          expect(help_text).to match(%r{/tools-debug.*Manage Tools subsystem debugging})
        end
        command.execute("/help")
      end

      it "dynamically retrieves command descriptions from registry" do
        # This test verifies that HelpCommand uses the registry to get commands
        # rather than hardcoded help text
        # Expect the help command to query the registry for all registered commands
        expect(application).to receive(:registered_commands).and_return(
          {
            "/help" => described_class,
            "/llm" => Nu::Agent::Commands::Subsystems::LlmCommand,
            "/messages" => Nu::Agent::Commands::Subsystems::MessagesCommand
          }
        )

        # Expect each command class to be asked for its description
        expect(described_class).to receive(:description).and_return("Show this help message")
        expect(Nu::Agent::Commands::Subsystems::LlmCommand).to receive(:description)
          .and_return("Manage LLM subsystem debugging")
        expect(Nu::Agent::Commands::Subsystems::MessagesCommand).to receive(:description)
          .and_return("Manage Messages subsystem debugging")

        expect(application).to receive(:output_lines) do |*lines, **_kwargs|
          help_text = lines.join("\n")
          expect(help_text).to match(/Show this help message/)
          expect(help_text).to match(/Manage LLM subsystem debugging/)
          expect(help_text).to match(/Manage Messages subsystem debugging/)
        end

        command.execute("/help")
      end
    end
  end
end
