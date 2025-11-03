# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/help_command"

RSpec.describe Nu::Agent::Commands::HelpCommand do
  let(:console) { instance_double("Nu::Agent::ConsoleIO") }
  let(:application) { instance_double("Nu::Agent::Application", console: console) }
  let(:command) { described_class.new(application) }

  describe ".description" do
    it "returns the command description" do
      expect(described_class.description).to eq("Show this help message")
    end
  end

  describe "#execute" do
    before do
      allow(console).to receive(:puts)
      allow(application).to receive(:output_lines)
      # Mock registered_commands with a default set for all tests
      allow(application).to receive(:registered_commands).and_return(
        {
          "/backup" => Class.new,
          "/clear" => Class.new,
          "/debug" => Class.new,
          "/exit" => Class.new,
          "/help" => described_class,
          "/info" => Class.new,
          "/migrate-exchanges" => Class.new,
          "/model" => Class.new,
          "/models" => Class.new,
          "/persona" => Class.new,
          "/personas" => Class.new,
          "/rag" => Class.new,
          "/redaction" => Class.new,
          "/reset" => Class.new,
          "/tools" => Class.new,
          "/verbosity" => Class.new,
          "/worker" => Class.new
        }
      )
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
      before do
        # Mock the registered_commands method with a minimal set for testing
        allow(application).to receive(:registered_commands).and_return(
          {
            "/help" => described_class,
            "/exit" => Class.new,
            "/clear" => Class.new,
            "/reset" => Class.new,
            "/info" => Class.new,
            "/tools" => Class.new,
            "/verbosity" => Class.new,
            "/model" => Class.new,
            "/models" => Class.new,
            "/persona" => Class.new,
            "/personas" => Class.new,
            "/worker" => Class.new,
            "/rag" => Class.new,
            "/redaction" => Class.new,
            "/backup" => Class.new,
            "/migrate-exchanges" => Class.new,
            "/debug" => Class.new,
            "/llm" => Class.new,
            "/messages" => Class.new,
            "/search" => Class.new,
            "/stats" => Class.new,
            "/tools-debug" => Class.new
          }
        )
      end

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
        # Create test command classes that are not in the hardcoded dictionary
        test_command_class = Class.new do
          def self.description
            "Test command description"
          end
        end

        another_test_class = Class.new do
          def self.description
            "Another test description"
          end
        end

        # Expect the help command to query the registry for all registered commands
        # Include some known commands and some test commands not in the hardcoded dictionary
        expect(application).to receive(:registered_commands).and_return(
          {
            "/help" => described_class,
            "/llm" => Class.new, # This is in hardcoded dict
            "/test-command" => test_command_class,
            "/another-test" => another_test_class
          }
        )

        expect(application).to receive(:output_lines) do |*lines, **_kwargs|
          help_text = lines.join("\n")
          # Verify hardcoded commands are included
          expect(help_text).to match(/Show this help message/)
          expect(help_text).to match(/Manage LLM subsystem debugging/)
          # Verify dynamic commands use their description methods
          expect(help_text).to match(/Test command description/)
          expect(help_text).to match(/Another test description/)
        end

        command.execute("/help")
      end

      it "shows '(No description available)' for commands without description method" do
        command_without_description = Class.new

        expect(application).to receive(:registered_commands).and_return(
          {
            "/help" => described_class,
            "/no-desc" => command_without_description
          }
        )

        expect(application).to receive(:output_lines) do |*lines, **_kwargs|
          help_text = lines.join("\n")
          expect(help_text).to match(%r{/no-desc.*\(No description available\)})
        end

        command.execute("/help")
      end

      it "handles commands with single-line descriptions correctly" do
        expect(application).to receive(:registered_commands).and_return(
          {
            "/clear" => Class.new
          }
        )

        expect(application).to receive(:output_lines) do |*lines, **_kwargs|
          help_text = lines.join("\n")
          # Verify single-line description is formatted correctly
          expect(help_text).to match(%r{/clear\s+-\s+Clear the screen})
          # Ensure no additional indented lines for single-line descriptions
          expect(help_text.lines.count { |line| line.strip.empty? || line.match?(/^\s{33}/) }).to eq(0)
        end

        command.execute("/help")
      end
    end
  end
end
