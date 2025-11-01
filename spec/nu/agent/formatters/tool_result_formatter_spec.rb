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

    context "with batch and thread info" do
      before { allow(console).to receive(:puts) }

      it "includes batch and thread in header when provided" do
        formatter.display(message, batch: 2, thread: 3)

        expect(console).to have_received(:puts).with(
          "\e[90m[Tool Use Response] (Batch 2/Thread 3) file_read\e[0m"
        )
      end

      it "displays without batch/thread when not provided" do
        formatter.display(message)

        expect(console).to have_received(:puts).with("\e[90m[Tool Use Response] file_read\e[0m")
        expect(console).not_to have_received(:puts).with(a_string_matching(/Batch/))
      end

      it "works with only batch number (no thread)" do
        formatter.display(message, batch: 1)

        expect(console).to have_received(:puts).with(
          "\e[90m[Tool Use Response] (Batch 1) file_read\e[0m"
        )
      end
    end

    context "with timing information" do
      before { allow(console).to receive(:puts) }

      context "with duration only" do
        it "displays duration less than 1ms" do
          formatter.display(message, duration: 0.0005)

          expect(console).to have_received(:puts).with(
            /\[Tool Use Response\] file_read \[Duration: <1ms\]/
          )
        end

        it "displays duration in milliseconds when less than 1 second" do
          formatter.display(message, duration: 0.250)

          expect(console).to have_received(:puts).with(
            /\[Tool Use Response\] file_read \[Duration: 250ms\]/
          )
        end

        it "displays duration in seconds when 1 second or more" do
          formatter.display(message, duration: 2.5)

          expect(console).to have_received(:puts).with(
            /\[Tool Use Response\] file_read \[Duration: 2\.50s\]/
          )
        end
      end

      context "with full timing (start_time, duration, batch_start_time)" do
        it "displays start time, end time, and duration" do
          start_time = Time.new(2025, 10, 31, 14, 30, 15, 123)
          batch_start_time = Time.new(2025, 10, 31, 14, 30, 10, 0)
          duration = 0.250

          formatter.display(message, start_time: start_time, duration: duration, batch_start_time: batch_start_time)

          # Check that timing information is included with formatted times
          expect(console).to have_received(:puts).with(
            /\[Start: \d{2}:\d{2}:\d{2}\.\d{3}, End: \d{2}:\d{2}:\d{2}\.\d{3}, Duration: 250ms\]/
          )
        end

        it "calculates end time correctly from start time and duration" do
          start_time = Time.new(2025, 10, 31, 10, 0, 0, 0)
          batch_start_time = Time.new(2025, 10, 31, 9, 59, 0, 0)
          duration = 1.5

          formatter.display(message, start_time: start_time, duration: duration, batch_start_time: batch_start_time)

          # Should show start at 10:00:00, end at 10:00:01.500
          expect(console).to have_received(:puts).with(
            /\[Start: 10:00:00\.000, End: 10:00:01\.500, Duration: 1500ms\]/
          )
        end
      end
    end
  end
end
