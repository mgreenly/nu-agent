# frozen_string_literal: true

require "spec_helper"
require "nu/agent/tools/file_edit/replace_range_operation"
require "tempfile"

RSpec.describe Nu::Agent::Tools::FileEdit::ReplaceRangeOperation do
  let(:operation) { described_class.new }
  let(:temp_file) { Tempfile.new("test") }
  let(:file_path) { temp_file.path }

  after { temp_file.unlink }

  describe "#execute" do
    context "when file does not exist" do
      it "raises ArgumentError" do
        ops = { start_line: 1, end_line: 2, content: "new" }
        expect { operation.execute("/nonexistent/file.txt", ops) }.to raise_error(
          ArgumentError,
          /File not found/
        )
      end
    end

    context "when start_line is invalid" do
      it "returns error" do
        File.write(file_path, "line1\nline2\n")
        ops = { start_line: 0, end_line: 1, content: "new" }

        result = operation.execute(file_path, ops)

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Invalid start_line")
      end
    end

    context "when end_line is invalid" do
      it "returns error" do
        File.write(file_path, "line1\nline2\n")
        ops = { start_line: 1, end_line: 10, content: "new" }

        result = operation.execute(file_path, ops)

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Invalid end_line")
      end
    end

    context "when start_line > end_line" do
      it "returns error" do
        File.write(file_path, "line1\nline2\nline3\n")
        ops = { start_line: 3, end_line: 1, content: "new" }

        result = operation.execute(file_path, ops)

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("start_line")
        expect(result[:error]).to include("end_line")
      end
    end

    context "when replacing single line" do
      it "replaces the line" do
        File.write(file_path, "line1\nline2\nline3\n")
        ops = { start_line: 2, end_line: 2, content: "replaced" }

        result = operation.execute(file_path, ops)

        expect(result[:status]).to eq("success")
        expect(result[:lines_removed]).to eq(1)
        expect(File.read(file_path)).to eq("line1\nreplaced\nline3\n")
      end
    end

    context "when replacing multiple lines" do
      it "replaces the range" do
        File.write(file_path, "line1\nline2\nline3\nline4\n")
        ops = { start_line: 2, end_line: 3, content: "new content" }

        result = operation.execute(file_path, ops)

        expect(result[:status]).to eq("success")
        expect(result[:lines_removed]).to eq(2)
        expect(File.read(file_path)).to eq("line1\nnew content\nline4\n")
      end
    end

    context "when deleting lines with empty content" do
      it "removes the lines" do
        File.write(file_path, "line1\nline2\nline3\n")
        ops = { start_line: 2, end_line: 2, content: "" }

        result = operation.execute(file_path, ops)

        expect(result[:status]).to eq("success")
        expect(result[:lines_removed]).to eq(1)
        expect(result[:lines_added]).to eq(0)
        expect(File.read(file_path)).to eq("line1\nline3\n")
      end
    end

    context "when content does not end with newline" do
      it "adds newline automatically" do
        File.write(file_path, "line1\nline2\n")
        ops = { start_line: 1, end_line: 1, content: "no newline" }

        result = operation.execute(file_path, ops)

        expect(result[:status]).to eq("success")
        expect(File.read(file_path)).to eq("no newline\nline2\n")
      end
    end
  end
end
