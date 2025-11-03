# frozen_string_literal: true

require "spec_helper"
require "nu/agent/formatters/tool_call_formatter"
require "nu/agent/subsystem_debugger"

RSpec.describe Nu::Agent::Formatters::ToolCallFormatter do
  let(:console) { double("console") }
  let(:history) { double("history") }
  let(:application) { double("application", debug: true, history: history) }
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
    context "with tools_verbosity 0 (no output)" do
      before do
        allow(console).to receive(:puts)
        allow(history).to receive(:get_int).with("tools_verbosity", default: 0).and_return(0)
      end

      it "does not display anything" do
        formatter.display(tool_call)

        expect(console).not_to have_received(:puts)
      end
    end

    context "with tools_verbosity 1 (tool name only)" do
      before do
        allow(console).to receive(:puts)
        allow(history).to receive(:get_int).with("tools_verbosity", default: 0).and_return(1)
      end

      it "displays tool name without arguments" do
        formatter.display(tool_call)

        expect(console).to have_received(:puts).with("")
        expect(console).to have_received(:puts).with("\e[90m[Tool Call Request] file_read\e[0m")
        # Should not display arguments at verbosity 1
        expect(console).not_to have_received(:puts).with(a_string_matching(/path:/))
      end

      it "shows count indicator when multiple tool calls" do
        formatter.display(tool_call, index: 2, total: 3)

        expect(console).to have_received(:puts).with("\e[90m[Tool Call Request] file_read (2/3)\e[0m")
      end
    end

    context "with tools_verbosity 2 (truncated arguments)" do
      before do
        allow(console).to receive(:puts)
        allow(history).to receive(:get_int).with("tools_verbosity", default: 0).and_return(2)
      end

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

    context "with tools_verbosity 3+ (full arguments)" do
      before do
        allow(console).to receive(:puts)
        allow(history).to receive(:get_int).with("tools_verbosity", default: 0).and_return(3)
      end

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

      it "skips empty lines in multiline values" do
        multiline_tool_call = {
          "name" => "file_write",
          "arguments" => {
            "content" => "line1\n\nline3\n"
          }
        }

        formatter.display(multiline_tool_call)

        expect(console).to have_received(:puts).with("\e[90m  content:\e[0m")
        expect(console).to have_received(:puts).with("\e[90m    line1\e[0m")
        expect(console).to have_received(:puts).with("\e[90m    line3\e[0m")
        # Empty line should not be printed
        expect(console).to have_received(:puts).exactly(5).times
      end
    end

    context "when debug is false" do
      let(:application) { double("application", debug: false, history: history) }

      before do
        allow(console).to receive(:puts)
        allow(history).to receive(:get_int).with("tools_verbosity", default: 0).and_return(1)
      end

      it "does not display anything" do
        formatter.display(tool_call)

        expect(console).not_to have_received(:puts)
      end
    end

    context "when no application provided" do
      let(:formatter) { described_class.new(console: console, application: nil) }

      before { allow(console).to receive(:puts) }

      it "defaults to tools_verbosity 0 and displays nothing" do
        formatter.display(tool_call)

        expect(console).not_to have_received(:puts)
      end
    end

    context "with empty arguments" do
      let(:tool_call) { { "name" => "get_weather", "arguments" => {} } }

      before do
        allow(console).to receive(:puts)
        allow(history).to receive(:get_int).with("tools_verbosity", default: 0).and_return(1)
      end

      it "displays tool name only" do
        formatter.display(tool_call)

        expect(console).to have_received(:puts).with("\e[90m[Tool Call Request] get_weather\e[0m")
      end
    end

    context "with nil arguments" do
      let(:tool_call) { { "name" => "get_weather", "arguments" => nil } }

      before do
        allow(console).to receive(:puts)
        allow(history).to receive(:get_int).with("tools_verbosity", default: 0).and_return(2)
      end

      it "displays tool name without arguments" do
        formatter.display(tool_call)

        expect(console).to have_received(:puts).with("")
        expect(console).to have_received(:puts).with("\e[90m[Tool Call Request] get_weather\e[0m")
        # Should not try to display nil arguments
        expect(console).not_to have_received(:puts).with(a_string_matching(/:/))
      end
    end

    context "when error occurs displaying arguments" do
      let(:bad_tool_call) do
        {
          "name" => "test_tool",
          "arguments" => { "bad" => double("obj", to_s: -> { raise "error" }) }
        }
      end

      before do
        allow(console).to receive(:puts)
        allow(history).to receive(:get_int).with("tools_verbosity", default: 0).and_return(2)
      end

      it "displays error message" do
        formatter.display(bad_tool_call)

        expect(console).to have_received(:puts).with(a_string_matching(/Error displaying arguments/))
      end
    end

    context "with batch and thread info" do
      before do
        allow(console).to receive(:puts)
        allow(history).to receive(:get_int).with("tools_verbosity", default: 0).and_return(1)
      end

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
