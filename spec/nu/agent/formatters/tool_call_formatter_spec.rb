# frozen_string_literal: true

require "spec_helper"
require "nu/agent/formatters/tool_call_formatter"

RSpec.describe Nu::Agent::Formatters::ToolCallFormatter do
  let(:console) { double("console") }
  let(:application) { double("application", verbosity: 0) }
  let(:formatter) { described_class.new(console: console, application: application) }
  let(:tool_call) do
    {
      "name" => "file_read",
      "arguments" => {
        "path" => "/path/to/file.txt",
        "encoding" => "utf-8"
      }
    }
  end

  describe "#display" do
    context "with verbosity 0 (tool name only)" do
      before { allow(console).to receive(:puts) }

      it "displays tool name without arguments" do
        formatter.display(tool_call)

        expect(console).to have_received(:puts).with("")
        expect(console).to have_received(:puts).with("\e[90m[Tool Call Request] file_read\e[0m")
        # Should not display arguments at verbosity 0
        expect(console).not_to have_received(:puts).with(a_string_matching(/path:/))
      end

      it "shows count indicator when multiple tool calls" do
        formatter.display(tool_call, index: 2, total: 3)

        expect(console).to have_received(:puts).with("\e[90m[Tool Call Request] file_read (2/3)\e[0m")
      end
    end

    context "with verbosity 1 (truncated arguments)" do
      let(:application) { double("application", verbosity: 1) }

      before { allow(console).to receive(:puts) }

      it "displays truncated arguments" do
        formatter.display(tool_call)

        expect(console).to have_received(:puts).with("")
        expect(console).to have_received(:puts).with("\e[90m[Tool Call Request] file_read\e[0m")
        expect(console).to have_received(:puts).with("\e[90m  path: /path/to/file.txt\e[0m")
        expect(console).to have_received(:puts).with("\e[90m  encoding: utf-8\e[0m")
      end

      it "truncates long arguments to 30 characters" do
        long_tool_call = {
          "name" => "execute_bash",
          "arguments" => {
            "command" => "a" * 50
          }
        }

        formatter.display(long_tool_call)

        expect(console).to have_received(:puts).with("\e[90m  command: #{'a' * 30}...\e[0m")
      end
    end

    context "with verbosity 4+ (full arguments)" do
      let(:application) { double("application", verbosity: 4) }

      before { allow(console).to receive(:puts) }

      it "displays full arguments" do
        formatter.display(tool_call)

        expect(console).to have_received(:puts).with("\e[90m  path: /path/to/file.txt\e[0m")
        expect(console).to have_received(:puts).with("\e[90m  encoding: utf-8\e[0m")
      end

      it "handles multiline values" do
        multiline_tool_call = {
          "name" => "file_write",
          "arguments" => {
            "content" => "line1\nline2\nline3"
          }
        }

        formatter.display(multiline_tool_call)

        expect(console).to have_received(:puts).with("\e[90m  content:\e[0m")
        expect(console).to have_received(:puts).with("\e[90m    line1\e[0m")
        expect(console).to have_received(:puts).with("\e[90m    line2\e[0m")
        expect(console).to have_received(:puts).with("\e[90m    line3\e[0m")
      end
    end

    context "when no application provided" do
      let(:formatter) { described_class.new(console: console, application: nil) }

      before { allow(console).to receive(:puts) }

      it "defaults to verbosity 0" do
        formatter.display(tool_call)

        expect(console).to have_received(:puts).with("\e[90m[Tool Call Request] file_read\e[0m")
        expect(console).not_to have_received(:puts).with(a_string_matching(/path:/))
      end
    end

    context "with empty arguments" do
      let(:tool_call) { { "name" => "get_weather", "arguments" => {} } }

      before { allow(console).to receive(:puts) }

      it "displays tool name only" do
        formatter.display(tool_call)

        expect(console).to have_received(:puts).with("\e[90m[Tool Call Request] get_weather\e[0m")
      end
    end

    context "when error occurs displaying arguments" do
      let(:application) { double("application", verbosity: 1) }
      let(:bad_tool_call) do
        {
          "name" => "test_tool",
          "arguments" => { "bad" => double("obj", to_s: -> { raise "error" }) }
        }
      end

      before { allow(console).to receive(:puts) }

      it "displays error message" do
        formatter.display(bad_tool_call)

        expect(console).to have_received(:puts).with(a_string_matching(/Error displaying arguments/))
      end
    end

    context "with batch and thread info" do
      before { allow(console).to receive(:puts) }

      it "includes batch and thread in header when provided" do
        formatter.display(tool_call, batch: 2, thread: 3, index: 5, total: 10)

        expect(console).to have_received(:puts).with(
          "\e[90m[Tool Call Request] (Batch 2/Thread 3) file_read (5/10)\e[0m"
        )
      end

      it "displays without batch/thread when not provided" do
        formatter.display(tool_call)

        expect(console).to have_received(:puts).with("\e[90m[Tool Call Request] file_read\e[0m")
        expect(console).not_to have_received(:puts).with(a_string_matching(/Batch/))
      end

      it "includes batch and thread even without count indicator" do
        formatter.display(tool_call, batch: 1, thread: 2)

        expect(console).to have_received(:puts).with(
          "\e[90m[Tool Call Request] (Batch 1/Thread 2) file_read\e[0m"
        )
      end

      it "works with only batch number (no thread)" do
        formatter.display(tool_call, batch: 3)

        expect(console).to have_received(:puts).with(
          "\e[90m[Tool Call Request] (Batch 3) file_read\e[0m"
        )
      end
    end
  end
end
