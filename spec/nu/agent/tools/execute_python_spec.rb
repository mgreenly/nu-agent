# frozen_string_literal: true

require "spec_helper"
require "open3"

RSpec.describe Nu::Agent::Tools::ExecutePython do
  let(:tool) { described_class.new }

  describe "#name" do
    it "returns the tool name" do
      expect(tool.name).to eq("execute_python")
    end
  end

  describe "#available?" do
    it "returns true when python3 is available" do
      allow(tool).to receive(:system).with("which python3 > /dev/null 2>&1").and_return(true)

      expect(tool.available?).to be true
    end

    it "returns false when python3 is not available" do
      allow(tool).to receive(:system).with("which python3 > /dev/null 2>&1").and_return(false)

      expect(tool).not_to be_available
    end
  end

  describe "#description" do
    it "returns a description" do
      expect(tool.description).to include("Execute Python code")
    end

    it "mentions data analysis" do
      expect(tool.description).to include("data analysis")
    end

    it "mentions scripting" do
      expect(tool.description).to include("scripting")
    end
  end

  describe "#parameters" do
    it "defines expected parameters" do
      params = tool.parameters

      expect(params).to have_key(:code)
      expect(params).to have_key(:timeout)
    end

    it "marks code as required" do
      expect(tool.parameters[:code][:required]).to be true
    end

    it "marks timeout as optional" do
      expect(tool.parameters[:timeout][:required]).to be false
    end
  end

  describe "#execute" do
    context "with missing code parameter" do
      it "raises ArgumentError when code is nil" do
        expect do
          tool.execute(arguments: {})
        end.to raise_error(ArgumentError, "code is required")
      end

      it "raises ArgumentError when code is empty string" do
        expect do
          tool.execute(arguments: { code: "" })
        end.to raise_error(ArgumentError, "code is required")
      end
    end

    context "with string keys in arguments" do
      before do
        allow(Open3).to receive(:capture3).and_return(["output", "", instance_double(Process::Status, exitstatus: 0)])
      end

      it "accepts string keys for all parameters" do
        result = tool.execute(
          arguments: {
            "code" => "print('test')",
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

        tool.execute(arguments: { code: "print('test')" })
      end

      it "uses specified timeout" do
        expect(Open3).to receive(:capture3) do |*args|
          expect(args[1]).to eq("60s")
          ["", "", instance_double(Process::Status, exitstatus: 0)]
        end

        tool.execute(arguments: { code: "print('test')", timeout: 60 })
      end

      it "clamps timeout to minimum of 1 second" do
        expect(Open3).to receive(:capture3) do |*args|
          expect(args[1]).to eq("1s")
          ["", "", instance_double(Process::Status, exitstatus: 0)]
        end

        tool.execute(arguments: { code: "print('test')", timeout: 0 })
      end

      it "clamps timeout to maximum of 300 seconds" do
        expect(Open3).to receive(:capture3) do |*args|
          expect(args[1]).to eq("300s")
          ["", "", instance_double(Process::Status, exitstatus: 0)]
        end

        tool.execute(arguments: { code: "print('test')", timeout: 500 })
      end
    end

    context "with successful code execution" do
      it "returns stdout output" do
        allow(Open3).to receive(:capture3).and_return(
          ["Hello World\n", "", instance_double(Process::Status, exitstatus: 0)]
        )

        result = tool.execute(arguments: { code: "print('Hello World')" })

        expect(result[:stdout]).to eq("Hello World\n")
      end

      it "returns zero exit code" do
        allow(Open3).to receive(:capture3).and_return(
          ["", "", instance_double(Process::Status, exitstatus: 0)]
        )

        result = tool.execute(arguments: { code: "pass" })

        expect(result[:exit_code]).to eq(0)
      end

      it "returns success as true" do
        allow(Open3).to receive(:capture3).and_return(
          ["", "", instance_double(Process::Status, exitstatus: 0)]
        )

        result = tool.execute(arguments: { code: "pass" })

        expect(result[:success]).to be true
      end

      it "returns timed_out as false" do
        allow(Open3).to receive(:capture3).and_return(
          ["", "", instance_double(Process::Status, exitstatus: 0)]
        )

        result = tool.execute(arguments: { code: "pass" })

        expect(result[:timed_out]).to be false
      end

      it "passes chdir option with current directory" do
        expect(Open3).to receive(:capture3) do |*_args, **kwargs|
          expect(kwargs[:chdir]).to eq(Dir.pwd)
          ["", "", instance_double(Process::Status, exitstatus: 0)]
        end

        tool.execute(arguments: { code: "import os; print(os.getcwd())" })
      end
    end

    context "with failed code execution" do
      it "returns non-zero exit code" do
        allow(Open3).to receive(:capture3).and_return(
          ["", "NameError: name 'foo' is not defined", instance_double(Process::Status, exitstatus: 1)]
        )

        result = tool.execute(arguments: { code: "print(foo)" })

        expect(result[:exit_code]).to eq(1)
      end

      it "returns success as false" do
        allow(Open3).to receive(:capture3).and_return(
          ["", "error", instance_double(Process::Status, exitstatus: 1)]
        )

        result = tool.execute(arguments: { code: "raise Exception('error')" })

        expect(result[:success]).to be false
      end

      it "returns stderr output" do
        allow(Open3).to receive(:capture3).and_return(
          ["", "Error message\n", instance_double(Process::Status, exitstatus: 1)]
        )

        result = tool.execute(arguments: { code: "import sys; sys.stderr.write('Error message\\n')" })

        expect(result[:stderr]).to eq("Error message\n")
      end

      it "returns both stdout and stderr when present" do
        allow(Open3).to receive(:capture3).and_return(
          ["Some output\n", "Some error\n", instance_double(Process::Status, exitstatus: 1)]
        )

        result = tool.execute(arguments: { code: "print('output'); raise Exception('error')" })

        expect(result[:stdout]).to eq("Some output\n")
        expect(result[:stderr]).to eq("Some error\n")
      end
    end

    context "with code timeout" do
      it "detects timeout with exit code 124" do
        allow(Open3).to receive(:capture3).and_return(
          ["", "", instance_double(Process::Status, exitstatus: 124)]
        )

        result = tool.execute(arguments: { code: "import time; time.sleep(100)", timeout: 1 })

        expect(result[:timed_out]).to be true
      end

      it "sets stderr message on timeout" do
        allow(Open3).to receive(:capture3).and_return(
          ["", "", instance_double(Process::Status, exitstatus: 124)]
        )

        result = tool.execute(arguments: { code: "import time; time.sleep(100)", timeout: 5 })

        expect(result[:stderr]).to eq("Code timed out after 5 seconds")
      end

      it "returns exit code 124 on timeout" do
        allow(Open3).to receive(:capture3).and_return(
          ["", "", instance_double(Process::Status, exitstatus: 124)]
        )

        result = tool.execute(arguments: { code: "import time; time.sleep(100)", timeout: 1 })

        expect(result[:exit_code]).to eq(124)
      end

      it "returns success as false on timeout" do
        allow(Open3).to receive(:capture3).and_return(
          ["", "", instance_double(Process::Status, exitstatus: 124)]
        )

        result = tool.execute(arguments: { code: "import time; time.sleep(100)", timeout: 1 })

        expect(result[:success]).to be false
      end
    end

    context "with StandardError during execution" do
      it "handles execution errors" do
        allow(Open3).to receive(:capture3).and_raise(StandardError.new("System error"))

        result = tool.execute(arguments: { code: "print('test')" })

        expect(result[:stderr]).to eq("Execution failed: System error")
        expect(result[:exit_code]).to eq(1)
        expect(result[:success]).to be false
      end

      it "returns empty stdout on error" do
        allow(Open3).to receive(:capture3).and_raise(StandardError.new("System error"))

        result = tool.execute(arguments: { code: "print('test')" })

        expect(result[:stdout]).to eq("")
      end

      it "returns timed_out as false on StandardError" do
        allow(Open3).to receive(:capture3).and_raise(StandardError.new("System error"))

        result = tool.execute(arguments: { code: "print('test')" })

        expect(result[:timed_out]).to be false
      end
    end
  end
end
