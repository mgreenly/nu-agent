# frozen_string_literal: true

require "spec_helper"
require "nu/agent/tools/file_edit/insert_line_operation"
require "tempfile"

RSpec.describe Nu::Agent::Tools::FileEdit::InsertLineOperation do
  let(:operation) { described_class.new }
  let(:temp_file) { Tempfile.new("test") }
  let(:file_path) { temp_file.path }

  after { temp_file.unlink }

  describe "#execute" do
    context "when file does not exist" do
      it "raises ArgumentError" do
        ops = { line_number: 1, content: "new line" }
        expect { operation.execute("/nonexistent/file.txt", ops) }.to raise_error(
          ArgumentError,
          /File not found/
        )
      end
    end

    context "when content is missing" do
      it "raises ArgumentError" do
        File.write(file_path, "line1\n")
        ops = { line_number: 1, content: nil }
        expect { operation.execute(file_path, ops) }.to raise_error(
          ArgumentError,
          /content is required/
        )
      end
    end

    context "when line number is invalid" do
      it "returns error for line number too low" do
        File.write(file_path, "line1\n")
        ops = { line_number: 0, content: "new line" }

        result = operation.execute(file_path, ops)

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Invalid line number")
      end

      it "returns error for line number too high" do
        File.write(file_path, "line1\n")
        ops = { line_number: 10, content: "new line" }

        result = operation.execute(file_path, ops)

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Invalid line number")
      end
    end

    context "when inserting at beginning of file" do
      it "inserts before line 1" do
        File.write(file_path, "line1\nline2\n")
        ops = { line_number: 1, content: "new line" }

        result = operation.execute(file_path, ops)

        expect(result[:status]).to eq("success")
        expect(File.read(file_path)).to eq("new line\nline1\nline2\n")
      end
    end

    context "when inserting in middle of file" do
      it "inserts before specified line" do
        File.write(file_path, "line1\nline2\nline3\n")
        ops = { line_number: 2, content: "inserted" }

        result = operation.execute(file_path, ops)

        expect(result[:status]).to eq("success")
        expect(File.read(file_path)).to eq("line1\ninserted\nline2\nline3\n")
      end
    end

    context "when inserting at end of file" do
      it "appends after last line" do
        File.write(file_path, "line1\nline2\n")
        ops = { line_number: 3, content: "last line" }

        result = operation.execute(file_path, ops)

        expect(result[:status]).to eq("success")
        expect(File.read(file_path)).to eq("line1\nline2\nlast line\n")
      end
    end

    context "when content does not end with newline" do
      it "adds newline automatically" do
        File.write(file_path, "line1\n")
        ops = { line_number: 1, content: "no newline" }

        result = operation.execute(file_path, ops)

        expect(result[:status]).to eq("success")
        expect(File.read(file_path)).to eq("no newline\nline1\n")
      end
    end
  end
end
