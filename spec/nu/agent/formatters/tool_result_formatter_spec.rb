# frozen_string_literal: true

require "spec_helper"
require "nu/agent/formatters/tool_result_formatter"

RSpec.describe Nu::Agent::Formatters::ToolResultFormatter do
  let(:console) { double("console") }
  let(:application) { double("application", verbosity: 0) }
  let(:formatter) { described_class.new(console: console, application: application) }
  let(:message) do
    {
      "tool_result" => {
        "name" => "file_read",
        "result" => "file contents here"
      }
    }
  end

  describe "#display" do
    context "with verbosity 0 (tool name only)" do
      before { allow(console).to receive(:puts) }

      it "displays tool name without result" do
        formatter.display(message)

        expect(console).to have_received(:puts).with("")
        expect(console).to have_received(:puts).with("\e[90m[Tool Use Response] file_read\e[0m")
        # Should not display result at verbosity 0
        expect(console).not_to have_received(:puts).with(a_string_matching(/file contents/))
      end
    end

    context "with verbosity 1 (truncated result)" do
      let(:application) { double("application", verbosity: 1) }

      before { allow(console).to receive(:puts) }

      context "with simple string result" do
        it "displays truncated result" do
          formatter.display(message)

          expect(console).to have_received(:puts).with("\e[90m  file contents here\e[0m")
        end

        it "truncates long results to 30 characters" do
          long_message = {
            "tool_result" => {
              "name" => "execute_bash",
              "result" => "a" * 50
            }
          }

          formatter.display(long_message)

          expect(console).to have_received(:puts).with("\e[90m  #{'a' * 30}...\e[0m")
        end
      end

      context "with hash result" do
        let(:message) do
          {
            "tool_result" => {
              "name" => "file_info",
              "result" => {
                "path" => "/path/to/file.txt",
                "size" => "1024"
              }
            }
          }
        end

        it "displays hash fields with truncation" do
          formatter.display(message)

          expect(console).to have_received(:puts).with("\e[90m  path: /path/to/file.txt\e[0m")
          expect(console).to have_received(:puts).with("\e[90m  size: 1024\e[0m")
        end

        it "truncates long hash values" do
          long_message = {
            "tool_result" => {
              "name" => "test",
              "result" => {
                "output" => "a" * 50
              }
            }
          }

          formatter.display(long_message)

          expect(console).to have_received(:puts).with("\e[90m  output: #{'a' * 30}...\e[0m")
        end

        it "truncates multiline hash values to first line" do
          multiline_message = {
            "tool_result" => {
              "name" => "test",
              "result" => {
                "output" => "line1\nline2\nline3"
              }
            }
          }

          formatter.display(multiline_message)

          expect(console).to have_received(:puts).with("\e[90m  output: line1...\e[0m")
        end
      end
    end

    context "with verbosity 4+ (full result)" do
      let(:application) { double("application", verbosity: 4) }

      before { allow(console).to receive(:puts) }

      context "with simple string result" do
        it "displays full result" do
          formatter.display(message)

          expect(console).to have_received(:puts).with("\e[90m  file contents here\e[0m")
        end
      end

      context "with hash result containing multiline values" do
        let(:message) do
          {
            "tool_result" => {
              "name" => "file_write",
              "result" => {
                "status" => "success",
                "content" => "line1\nline2\nline3"
              }
            }
          }
        end

        it "displays full multiline values" do
          formatter.display(message)

          expect(console).to have_received(:puts).with("\e[90m  status: success\e[0m")
          expect(console).to have_received(:puts).with("\e[90m  content:\e[0m")
          expect(console).to have_received(:puts).with("\e[90m    line1\e[0m")
          expect(console).to have_received(:puts).with("\e[90m    line2\e[0m")
          expect(console).to have_received(:puts).with("\e[90m    line3\e[0m")
        end
      end
    end

    context "when no application provided" do
      let(:formatter) { described_class.new(console: console, application: nil) }

      before { allow(console).to receive(:puts) }

      it "defaults to verbosity 0" do
        formatter.display(message)

        expect(console).to have_received(:puts).with("\e[90m[Tool Use Response] file_read\e[0m")
        expect(console).not_to have_received(:puts).with(a_string_matching(/file contents/))
      end
    end

    context "when error occurs displaying result" do
      let(:application) { double("application", verbosity: 1) }
      let(:bad_message) do
        {
          "tool_result" => {
            "name" => "test_tool",
            "result" => double("obj", to_s: -> { raise "error" })
          }
        }
      end

      before do
        allow(console).to receive(:puts)
      end

      it "displays error message" do
        formatter.display(bad_message)

        expect(console).to have_received(:puts).with(a_string_matching(/Error displaying result/))
      end
    end
  end
end
