# frozen_string_literal: true

require "spec_helper"
require "open3"

RSpec.describe Nu::Agent::Tools::ExecuteBash do
  let(:tool) { described_class.new }

  describe "#name" do
    it "returns the tool name" do
      expect(tool.name).to eq("execute_bash")
    end
  end

  describe "#description" do
    it "returns a description" do
      expect(tool.description).to include("Execute bash commands")
    end

    it "mentions system operations" do
      expect(tool.description).to include("system operations")
    end

    it "mentions CLI tools" do
      expect(tool.description).to include("CLI tools")
    end
  end

  describe "#parameters" do
    it "defines expected parameters" do
      params = tool.parameters

      expect(params).to have_key(:command)
      expect(params).to have_key(:timeout)
    end

    it "marks command as required" do
      expect(tool.parameters[:command][:required]).to be true
    end

    it "marks timeout as optional" do
      expect(tool.parameters[:timeout][:required]).to be false
    end
  end

  describe "#execute" do
    context "with missing command parameter" do
      it "raises ArgumentError when command is nil" do
        expect do
          tool.execute(arguments: {})
        end.to raise_error(ArgumentError, "command is required")
      end

      it "raises ArgumentError when command is empty string" do
        expect do
          tool.execute(arguments: { command: "" })
        end.to raise_error(ArgumentError, "command is required")
      end
    end

    context "with string keys in arguments" do
      before do
        allow(Open3).to receive(:capture3).and_return(["output", "", instance_double(Process::Status, exitstatus: 0)])
      end

      it "accepts string keys for all parameters" do
        result = tool.execute(
          arguments: {
            "command" => "echo test",
            "timeout" => 10
          }
        )

        expect(result[:success]).to be true
      end
    end

    context "with timeout parameter" do
      before do
        allow(Open3).to receive(:capture3).and_return(["", "", instance_double(Process::Status, exitstatus: 0)])
      end

      it "defaults to 30 seconds when not specified" do
        expect(Open3).to receive(:capture3) do |*args|
          expect(args[1]).to eq("30s")
          ["", "", instance_double(Process::Status, exitstatus: 0)]
        end

        tool.execute(arguments: { command: "echo test" })
      end

      it "uses specified timeout" do
        expect(Open3).to receive(:capture3) do |*args|
          expect(args[1]).to eq("60s")
          ["", "", instance_double(Process::Status, exitstatus: 0)]
        end

        tool.execute(arguments: { command: "echo test", timeout: 60 })
      end

      it "clamps timeout to minimum of 1 second" do
        expect(Open3).to receive(:capture3) do |*args|
          expect(args[1]).to eq("1s")
          ["", "", instance_double(Process::Status, exitstatus: 0)]
        end

        tool.execute(arguments: { command: "echo test", timeout: 0 })
      end

      it "clamps timeout to maximum of 300 seconds" do
        expect(Open3).to receive(:capture3) do |*args|
          expect(args[1]).to eq("300s")
          ["", "", instance_double(Process::Status, exitstatus: 0)]
        end

        tool.execute(arguments: { command: "echo test", timeout: 500 })
      end
    end

    context "with successful command execution" do
      it "returns stdout output" do
        allow(Open3).to receive(:capture3).and_return(
          ["Hello World\n", "", instance_double(Process::Status, exitstatus: 0)]
        )

        result = tool.execute(arguments: { command: "echo 'Hello World'" })

        expect(result[:stdout]).to eq("Hello World\n")
      end

      it "returns zero exit code" do
        allow(Open3).to receive(:capture3).and_return(
          ["", "", instance_double(Process::Status, exitstatus: 0)]
        )

        result = tool.execute(arguments: { command: "echo test" })

        expect(result[:exit_code]).to eq(0)
      end

      it "returns success as true" do
        allow(Open3).to receive(:capture3).and_return(
          ["", "", instance_double(Process::Status, exitstatus: 0)]
        )

        result = tool.execute(arguments: { command: "echo test" })

        expect(result[:success]).to be true
      end

      it "returns timed_out as false" do
        allow(Open3).to receive(:capture3).and_return(
          ["", "", instance_double(Process::Status, exitstatus: 0)]
        )

        result = tool.execute(arguments: { command: "echo test" })

        expect(result[:timed_out]).to be false
      end

      it "passes chdir option with current directory" do
        expect(Open3).to receive(:capture3) do |*_args, **kwargs|
          expect(kwargs[:chdir]).to eq(Dir.pwd)
          ["", "", instance_double(Process::Status, exitstatus: 0)]
        end

        tool.execute(arguments: { command: "pwd" })
      end
    end

    context "with failed command execution" do
      it "returns non-zero exit code" do
        allow(Open3).to receive(:capture3).and_return(
          ["", "command not found", instance_double(Process::Status, exitstatus: 127)]
        )

        result = tool.execute(arguments: { command: "nonexistent_command" })

        expect(result[:exit_code]).to eq(127)
      end

      it "returns success as false" do
        allow(Open3).to receive(:capture3).and_return(
          ["", "error", instance_double(Process::Status, exitstatus: 1)]
        )

        result = tool.execute(arguments: { command: "false" })

        expect(result[:success]).to be false
      end

      it "returns stderr output" do
        allow(Open3).to receive(:capture3).and_return(
          ["", "Error message\n", instance_double(Process::Status, exitstatus: 1)]
        )

        result = tool.execute(arguments: { command: "invalid" })

        expect(result[:stderr]).to eq("Error message\n")
      end

      it "returns both stdout and stderr when present" do
        allow(Open3).to receive(:capture3).and_return(
          ["Some output\n", "Some error\n", instance_double(Process::Status, exitstatus: 1)]
        )

        result = tool.execute(arguments: { command: "command_with_both" })

        expect(result[:stdout]).to eq("Some output\n")
        expect(result[:stderr]).to eq("Some error\n")
      end
    end

    context "with command timeout" do
      it "detects timeout with exit code 124" do
        allow(Open3).to receive(:capture3).and_return(
          ["", "", instance_double(Process::Status, exitstatus: 124)]
        )

        result = tool.execute(arguments: { command: "sleep 100", timeout: 1 })

        expect(result[:timed_out]).to be true
      end

      it "sets stderr message on timeout" do
        allow(Open3).to receive(:capture3).and_return(
          ["", "", instance_double(Process::Status, exitstatus: 124)]
        )

        result = tool.execute(arguments: { command: "sleep 100", timeout: 5 })

        expect(result[:stderr]).to eq("Command timed out after 5 seconds")
      end

      it "returns exit code 124 on timeout" do
        allow(Open3).to receive(:capture3).and_return(
          ["", "", instance_double(Process::Status, exitstatus: 124)]
        )

        result = tool.execute(arguments: { command: "sleep 100", timeout: 1 })

        expect(result[:exit_code]).to eq(124)
      end

      it "returns success as false on timeout" do
        allow(Open3).to receive(:capture3).and_return(
          ["", "", instance_double(Process::Status, exitstatus: 124)]
        )

        result = tool.execute(arguments: { command: "sleep 100", timeout: 1 })

        expect(result[:success]).to be false
      end
    end

    context "with StandardError during execution" do
      it "handles execution errors" do
        allow(Open3).to receive(:capture3).and_raise(StandardError.new("System error"))

        result = tool.execute(arguments: { command: "echo test" })

        expect(result[:stderr]).to eq("Execution failed: System error")
        expect(result[:exit_code]).to eq(1)
        expect(result[:success]).to be false
      end

      it "returns empty stdout on error" do
        allow(Open3).to receive(:capture3).and_raise(StandardError.new("System error"))

        result = tool.execute(arguments: { command: "echo test" })

        expect(result[:stdout]).to eq("")
      end

      it "returns timed_out as false on StandardError" do
        allow(Open3).to receive(:capture3).and_raise(StandardError.new("System error"))

        result = tool.execute(arguments: { command: "echo test" })

        expect(result[:timed_out]).to be false
      end
    end
  end
end
