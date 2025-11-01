# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/debug_command"

RSpec.describe Nu::Agent::Commands::DebugCommand do
  let(:application) { instance_double("Nu::Agent::Application") }
  let(:history) { instance_double("Nu::Agent::History") }
  let(:formatter) { instance_double("Nu::Agent::Formatter") }
  let(:console) { instance_double("Nu::Agent::ConsoleIO") }
  let(:command) { described_class.new(application) }

  before do
    allow(application).to receive_messages(history: history, formatter: formatter, console: console)
    allow(application).to receive(:debug=)
    allow(formatter).to receive(:debug=)
    allow(console).to receive(:debug=)
    allow(history).to receive(:set_config)
    allow(console).to receive(:puts)
  end

  describe "#execute" do
    context "when no argument provided" do
      it "displays usage message" do
        allow(application).to receive(:debug).and_return(false)
        expect(console).to receive(:puts).with("\e[90mUsage: /debug <on|off>\e[0m")
        expect(console).to receive(:puts).with("\e[90mCurrent: debug=off\e[0m")
        expect(console).to receive(:puts).with("\e[90m\e[0m")
        expect(console).to receive(:puts).with("\e[90mControl specific debug output with subsystem commands:\e[0m")
        expect(console).to receive(:puts)
          .with("\e[90m  /llm verbosity <level>              - LLM API interactions\e[0m")
        expect(console).to receive(:puts)
          .with("\e[90m  /tools-debug verbosity <level>      - Tool calls and results\e[0m")
        expect(console).to receive(:puts).with("\e[90m  /messages verbosity <level>         - Message tracking\e[0m")
        expect(console).to receive(:puts).with("\e[90m  /search verbosity <level>           - Search internals\e[0m")
        expect(console).to receive(:puts).with("\e[90m  /stats verbosity <level>            - Statistics/costs\e[0m")
        expect(console).to receive(:puts).with("\e[90m\e[0m")
        expect(console).to receive(:puts).with("\e[90mUse /<subsystem> help to see verbosity levels.\e[0m")
        command.execute("/debug")
      end

      it "returns :continue" do
        allow(application).to receive(:debug).and_return(false)
        expect(command.execute("/debug")).to eq(:continue)
      end
    end

    context "when turning debug on" do
      it "enables debug mode" do
        expect(application).to receive(:debug=).with(true)
        expect(formatter).to receive(:debug=).with(true)
        expect(history).to receive(:set_config).with("debug", "true")
        expect(console).to receive(:puts).with("\e[90mdebug=on\e[0m")
        command.execute("/debug on")
      end

      it "returns :continue" do
        expect(command.execute("/debug on")).to eq(:continue)
      end
    end

    context "when turning debug off" do
      it "disables debug mode" do
        expect(application).to receive(:debug=).with(false)
        expect(formatter).to receive(:debug=).with(false)
        expect(history).to receive(:set_config).with("debug", "false")
        expect(console).to receive(:puts).with("\e[90mdebug=off\e[0m")
        command.execute("/debug off")
      end

      it "returns :continue" do
        expect(command.execute("/debug off")).to eq(:continue)
      end
    end

    context "when invalid argument provided" do
      it "displays error message" do
        expect(console).to receive(:puts).with("\e[90mInvalid option. Use: /debug <on|off>\e[0m")
        command.execute("/debug invalid")
      end

      it "returns :continue" do
        expect(command.execute("/debug invalid")).to eq(:continue)
      end
    end
  end
end
