# frozen_string_literal: true

require "spec_helper"
require "nu/agent/tools/file_edit/append_operation"
require "tempfile"

RSpec.describe Nu::Agent::Tools::FileEdit::AppendOperation do
  let(:operation) { described_class.new }
  let(:temp_file) { Tempfile.new("test") }
  let(:file_path) { temp_file.path }

  after { temp_file.unlink }

  describe "#execute" do
    context "when file does not exist" do
      it "raises ArgumentError" do
        ops = { content: "new content" }
        expect { operation.execute("/nonexistent/file.txt", ops) }.to raise_error(
          ArgumentError,
          /File not found/
        )
      end
    end

    context "when appending to empty file" do
      it "adds content to the file" do
        File.write(file_path, "")
        ops = { content: "hello world" }

        result = operation.execute(file_path, ops)

        expect(result[:status]).to eq("success")
        expect(result[:operation]).to eq("append")
        expect(result[:bytes_added]).to eq(11)
        expect(File.read(file_path)).to eq("hello world")
      end
    end

    context "when appending to existing content" do
      it "adds content to the end" do
        File.write(file_path, "existing content")
        ops = { content: " new content" }

        result = operation.execute(file_path, ops)

        expect(result[:status]).to eq("success")
        expect(File.read(file_path)).to eq("existing content new content")
      end
    end

    context "when appending multiple lines" do
      it "preserves line breaks" do
        File.write(file_path, "line1\n")
        ops = { content: "line2\nline3\n" }

        result = operation.execute(file_path, ops)

        expect(result[:status]).to eq("success")
        expect(File.read(file_path)).to eq("line1\nline2\nline3\n")
      end
    end
  end
end
