# frozen_string_literal: true

require "spec_helper"
require "nu/agent/tools/file_edit/insert_before_operation"
require "tempfile"

RSpec.describe Nu::Agent::Tools::FileEdit::InsertBeforeOperation do
  let(:operation) { described_class.new }
  let(:temp_file) { Tempfile.new("test") }
  let(:file_path) { temp_file.path }

  after { temp_file.unlink }

  describe "#execute" do
    context "when file does not exist" do
      it "raises ArgumentError" do
        ops = { pattern: "foo", content: "bar" }
        expect { operation.execute("/nonexistent/file.txt", ops) }.to raise_error(
          ArgumentError,
          /File not found/
        )
      end
    end

    context "when content is missing" do
      it "raises ArgumentError" do
        File.write(file_path, "foo")
        ops = { pattern: "foo", content: nil }
        expect { operation.execute(file_path, ops) }.to raise_error(
          ArgumentError,
          /content is required/
        )
      end
    end

    context "when pattern is not found" do
      it "returns error status" do
        File.write(file_path, "hello world")
        ops = { pattern: "foo", content: "bar" }

        result = operation.execute(file_path, ops)

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Pattern not found")
      end
    end

    context "when inserting before pattern" do
      it "inserts content before first occurrence" do
        File.write(file_path, "hello world")
        ops = { pattern: "world", content: "beautiful " }

        result = operation.execute(file_path, ops)

        expect(result[:status]).to eq("success")
        expect(result[:operation]).to eq("insert_before")
        expect(File.read(file_path)).to eq("hello beautiful world")
      end
    end

    context "when pattern appears multiple times" do
      it "inserts only before first occurrence" do
        File.write(file_path, "foo bar foo baz")
        ops = { pattern: "foo", content: "X" }

        result = operation.execute(file_path, ops)

        expect(result[:status]).to eq("success")
        expect(File.read(file_path)).to eq("Xfoo bar foo baz")
      end
    end
  end
end
