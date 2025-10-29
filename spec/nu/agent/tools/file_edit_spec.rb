# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Nu::Agent::Tools::FileEdit do
  let(:tool) { described_class.new }
  let(:test_dir) { File.join(Dir.pwd, "tmp", "file_edit_test") }
  let(:test_file) { File.join(test_dir, "test.txt") }

  before do
    FileUtils.rm_rf(test_dir)
    FileUtils.mkdir_p(test_dir)
  end

  after do
    FileUtils.rm_rf(test_dir)
  end

  describe "#name" do
    it "returns the tool name" do
      expect(tool.name).to eq("file_edit")
    end
  end

  describe "#description" do
    it "returns a description" do
      expect(tool.description).to include("PREFERRED tool for editing files")
      expect(tool.description).to include("exact string replacement")
    end
  end

  describe "#parameters" do
    it "defines expected parameters" do
      params = tool.parameters

      expect(params).to have_key(:file)
      expect(params).to have_key(:old_string)
      expect(params).to have_key(:new_string)
      expect(params).to have_key(:replace_all)
      expect(params).to have_key(:append)
      expect(params).to have_key(:prepend)
      expect(params).to have_key(:insert_after)
      expect(params).to have_key(:insert_before)
      expect(params).to have_key(:content)
      expect(params).to have_key(:insert_line)
      expect(params).to have_key(:replace_range_start)
      expect(params).to have_key(:replace_range_end)
    end

    it "marks file as required" do
      expect(tool.parameters[:file][:required]).to be true
    end
  end

  describe "#execute" do
    context "with missing file parameter" do
      it "returns error when file is nil" do
        result = tool.execute(arguments: {})

        expect(result[:status]).to eq("error")
        expect(result[:error]).to eq("file path is required")
      end

      it "returns error when file is empty string" do
        result = tool.execute(arguments: { file: "", old_string: "old", new_string: "new" })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to eq("file path is required")
      end
    end

    context "with string keys in arguments" do
      it "accepts string keys for file parameter" do
        File.write(test_file, "original content")

        result = tool.execute(arguments: { "file" => test_file, "old_string" => "original", "new_string" => "updated" })

        expect(result[:status]).to eq("success")
      end
    end

    context "with no valid operation" do
      it "returns error when no operation is specified" do
        File.write(test_file, "content")

        result = tool.execute(arguments: { file: test_file })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Must provide either")
      end
    end

    context "with replace operation (old_string + new_string)" do
      it "replaces first occurrence of old_string with new_string" do
        File.write(test_file, "Hello world\nHello again")

        result = tool.execute(arguments: { file: test_file, old_string: "Hello", new_string: "Hi" })

        expect(result[:status]).to eq("success")
        expect(File.read(test_file)).to eq("Hi world\nHello again")
      end

      it "accepts string keys for replace parameters" do
        File.write(test_file, "Hello world")

        result = tool.execute(
          arguments: { "file" => test_file, "old_string" => "Hello", "new_string" => "Hi" }
        )

        expect(result[:status]).to eq("success")
      end

      it "replaces all occurrences when replace_all is true" do
        File.write(test_file, "Hello world\nHello again")

        result = tool.execute(
          arguments: { file: test_file, old_string: "Hello", new_string: "Hi", replace_all: true }
        )

        expect(result[:status]).to eq("success")
        expect(File.read(test_file)).to eq("Hi world\nHi again")
      end
    end

    context "with append operation" do
      it "appends content to end of file" do
        File.write(test_file, "existing content")

        result = tool.execute(arguments: { file: test_file, append: true, content: "\nnew line" })

        expect(result[:status]).to eq("success")
        expect(File.read(test_file)).to eq("existing content\nnew line")
      end

      it "accepts string keys for append parameter" do
        File.write(test_file, "existing")

        result = tool.execute(arguments: { "file" => test_file, "append" => true, "content" => " appended" })

        expect(result[:status]).to eq("success")
      end
    end

    context "with prepend operation" do
      it "prepends content to beginning of file" do
        File.write(test_file, "existing content")

        result = tool.execute(arguments: { file: test_file, prepend: true, content: "new line\n" })

        expect(result[:status]).to eq("success")
        expect(File.read(test_file)).to eq("new line\nexisting content")
      end

      it "accepts string keys for prepend parameter" do
        File.write(test_file, "existing")

        result = tool.execute(arguments: { "file" => test_file, "prepend" => true, "content" => "prepended " })

        expect(result[:status]).to eq("success")
      end
    end

    context "with insert_after operation" do
      it "inserts content after first match" do
        File.write(test_file, "Line 1\nLine 2\nLine 3")

        result = tool.execute(arguments: { file: test_file, insert_after: "Line 1", content: "\nInserted" })

        expect(result[:status]).to eq("success")
        expect(File.read(test_file)).to eq("Line 1\nInserted\nLine 2\nLine 3")
      end

      it "accepts string keys for insert_after parameters" do
        File.write(test_file, "content")

        result = tool.execute(
          arguments: { "file" => test_file, "insert_after" => "content", "content" => " added" }
        )

        expect(result[:status]).to eq("success")
      end
    end

    context "with insert_before operation" do
      it "inserts content before first match" do
        File.write(test_file, "Line 1\nLine 2\nLine 3")

        result = tool.execute(arguments: { file: test_file, insert_before: "Line 2", content: "Inserted\n" })

        expect(result[:status]).to eq("success")
        expect(File.read(test_file)).to eq("Line 1\nInserted\nLine 2\nLine 3")
      end

      it "accepts string keys for insert_before parameters" do
        File.write(test_file, "content")

        result = tool.execute(
          arguments: { "file" => test_file, "insert_before" => "content", "content" => "before " }
        )

        expect(result[:status]).to eq("success")
      end
    end

    context "with insert_line operation" do
      it "inserts content at specific line number" do
        File.write(test_file, "Line 1\nLine 2\nLine 3")

        result = tool.execute(arguments: { file: test_file, insert_line: 2, content: "Inserted\n" })

        expect(result[:status]).to eq("success")
        expect(File.read(test_file)).to eq("Line 1\nInserted\nLine 2\nLine 3")
      end

      it "accepts string keys for insert_line parameters" do
        File.write(test_file, "Line 1\nLine 2")

        result = tool.execute(
          arguments: { "file" => test_file, "insert_line" => 1, "content" => "First\n" }
        )

        expect(result[:status]).to eq("success")
      end
    end

    context "with replace_range operation" do
      it "replaces a range of lines with content" do
        File.write(test_file, "Line 1\nLine 2\nLine 3\nLine 4")

        result = tool.execute(
          arguments: { file: test_file, replace_range_start: 2, replace_range_end: 3, content: "New content\n" }
        )

        expect(result[:status]).to eq("success")
        expect(File.read(test_file)).to eq("Line 1\nNew content\nLine 4")
      end

      it "accepts string keys for replace_range parameters" do
        File.write(test_file, "Line 1\nLine 2\nLine 3")

        result = tool.execute(
          arguments: {
            "file" => test_file,
            "replace_range_start" => 1,
            "replace_range_end" => 2,
            "content" => "Replaced\n"
          }
        )

        expect(result[:status]).to eq("success")
      end
    end

    context "with error handling" do
      it "handles StandardError during execution" do
        File.write(test_file, "content")

        # Mock the strategy to raise an error
        allow_any_instance_of(Nu::Agent::Tools::FileEdit::ReplaceOperation)
          .to receive(:execute).and_raise(StandardError.new("Test error"))

        result = tool.execute(arguments: { file: test_file, old_string: "old", new_string: "new" })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to eq("Test error")
      end
    end

    context "with operation priority" do
      it "selects replace operation when both old_string and new_string are provided" do
        File.write(test_file, "original")

        result = tool.execute(
          arguments: { file: test_file, old_string: "original", new_string: "replaced", append: "ignored" }
        )

        expect(result[:status]).to eq("success")
        expect(File.read(test_file)).to eq("replaced")
      end
    end
  end
end
