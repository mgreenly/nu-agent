# frozen_string_literal: true

require "spec_helper"
require "nu/agent/tools/file_edit/replace_operation"
require "tempfile"

RSpec.describe Nu::Agent::Tools::FileEdit::ReplaceOperation do
  let(:operation) { described_class.new }
  let(:temp_file) { Tempfile.new("test") }
  let(:file_path) { temp_file.path }

  after { temp_file.unlink }

  describe "#execute" do
    context "when file does not exist" do
      it "raises ArgumentError" do
        ops = { old_string: "foo", new_string: "bar", replace_all: false }
        expect { operation.execute("/nonexistent/file.txt", ops) }.to raise_error(
          ArgumentError,
          /File not found/
        )
      end
    end

    context "when old_string is not found" do
      it "returns error status" do
        File.write(file_path, "hello world")
        ops = { old_string: "foo", new_string: "bar", replace_all: false }

        result = operation.execute(file_path, ops)

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("old_string not found in file")
        expect(result[:replacements]).to eq(0)
      end
    end

    context "when replacing first occurrence only" do
      it "replaces only the first match" do
        File.write(file_path, "foo bar foo baz")
        ops = { old_string: "foo", new_string: "qux", replace_all: false }

        result = operation.execute(file_path, ops)

        expect(result[:status]).to eq("success")
        expect(result[:replacements]).to eq(1)
        expect(result[:total_occurrences]).to eq(2)
        expect(result[:replaced_all]).to be(false)
        expect(File.read(file_path)).to eq("qux bar foo baz")
      end
    end

    context "when replacing all occurrences" do
      it "replaces all matches" do
        File.write(file_path, "foo bar foo baz foo")
        ops = { old_string: "foo", new_string: "qux", replace_all: true }

        result = operation.execute(file_path, ops)

        expect(result[:status]).to eq("success")
        expect(result[:replacements]).to eq(3)
        expect(result[:total_occurrences]).to eq(3)
        expect(result[:replaced_all]).to be(true)
        expect(File.read(file_path)).to eq("qux bar qux baz qux")
      end
    end

    context "when replacing with empty string" do
      it "deletes the old_string" do
        File.write(file_path, "hello world")
        ops = { old_string: "hello ", new_string: "", replace_all: false }

        result = operation.execute(file_path, ops)

        expect(result[:status]).to eq("success")
        expect(File.read(file_path)).to eq("world")
      end
    end

    context "when replacing multiline content" do
      it "handles newlines correctly" do
        File.write(file_path, "line1\nline2\nline3")
        ops = { old_string: "line2\n", new_string: "replaced\n", replace_all: false }

        result = operation.execute(file_path, ops)

        expect(result[:status]).to eq("success")
        expect(File.read(file_path)).to eq("line1\nreplaced\nline3")
      end
    end
  end
end
