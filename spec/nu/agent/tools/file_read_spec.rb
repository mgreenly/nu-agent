# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Nu::Agent::Tools::FileRead do
  let(:tool) { described_class.new }
  let(:test_dir) { File.join(Dir.pwd, "tmp", "file_read_test") }
  let(:test_file) { File.join(test_dir, "test.txt") }

  before do
    FileUtils.rm_rf(test_dir)
    FileUtils.mkdir_p(test_dir)

    # Create a test file with 20 numbered lines
    content = (1..20).map { |i| "Line #{i}\n" }.join
    File.write(test_file, content)
  end

  after do
    FileUtils.rm_rf(test_dir)
  end

  describe "#name" do
    it "returns the tool name" do
      expect(tool.name).to eq("file_read")
    end
  end

  describe "#description" do
    it "returns a description" do
      expect(tool.description).to include("PREFERRED tool for reading file contents")
    end
  end

  describe "#parameters" do
    it "defines expected parameters" do
      params = tool.parameters

      expect(params).to have_key(:file)
      expect(params).to have_key(:start_line)
      expect(params).to have_key(:end_line)
      expect(params).to have_key(:offset)
      expect(params).to have_key(:limit)
      expect(params).to have_key(:show_line_numbers)
    end

    it "marks file as required" do
      expect(tool.parameters[:file][:required]).to be true
    end
  end

  describe "#execute" do
    context "with missing file parameter" do
      it "returns error when file is nil" do
        result = tool.execute(arguments: {})

        expect(result[:error]).to eq("file path is required")
        expect(result[:content]).to be_nil
      end

      it "returns error when file is empty string" do
        result = tool.execute(arguments: { file: "" })

        expect(result[:error]).to eq("file path is required")
        expect(result[:content]).to be_nil
      end
    end

    context "with file validation errors" do
      it "returns error when file does not exist" do
        result = tool.execute(arguments: { file: File.join(test_dir, "nonexistent.txt") })

        expect(result[:error]).to include("File not found")
        expect(result[:content]).to be_nil
      end

      it "returns error when path is a directory" do
        result = tool.execute(arguments: { file: test_dir })

        expect(result[:error]).to include("Not a file")
        expect(result[:content]).to be_nil
      end

      it "returns error when file is not readable" do
        # Create a non-readable file
        unreadable_file = File.join(test_dir, "unreadable.txt")
        File.write(unreadable_file, "content")
        File.chmod(0o000, unreadable_file)

        result = tool.execute(arguments: { file: unreadable_file })

        expect(result[:error]).to include("File not readable")
        expect(result[:content]).to be_nil

        # Clean up - restore permissions
        File.chmod(0o644, unreadable_file)
      end
    end

    context "with path resolution" do
      it "handles absolute paths" do
        result = tool.execute(arguments: { file: test_file })

        expect(result[:file]).to eq(test_file)
        expect(result[:error]).to be_nil
      end

      it "handles relative paths" do
        relative_path = File.join("tmp", "file_read_test", "test.txt")
        result = tool.execute(arguments: { file: relative_path })

        expect(result[:file]).to eq(relative_path)
        expect(result[:error]).to be_nil
      end
    end

    context "with string keys in arguments" do
      it "accepts string keys for all parameters" do
        result = tool.execute(
          arguments: {
            "file" => test_file,
            "start_line" => 1,
            "end_line" => 5,
            "show_line_numbers" => false
          }
        )

        expect(result[:error]).to be_nil
        expect(result[:lines_read]).to eq(5)
      end
    end

    context "when reading entire file" do
      it "reads all lines with default limit" do
        result = tool.execute(arguments: { file: test_file })

        expect(result[:error]).to be_nil
        expect(result[:file]).to eq(test_file)
        expect(result[:total_lines]).to eq(20)
        expect(result[:lines_read]).to eq(20)
        expect(result[:content]).to include("Line 1")
        expect(result[:content]).to include("Line 20")
        expect(result[:truncated]).to be false
      end

      it "includes line numbers by default" do
        result = tool.execute(arguments: { file: test_file })

        expect(result[:content]).to match(/\s+1\t/)
        expect(result[:content]).to match(/\s+20\t/)
      end

      it "formats line numbers with consistent width" do
        result = tool.execute(arguments: { file: test_file })

        # Line numbers should be right-aligned in 6-character field
        expect(result[:content]).to match(/\s{5}1\tLine 1/)
        expect(result[:content]).to match(/\s{4}20\tLine 20/)
      end
    end

    context "with show_line_numbers false" do
      it "excludes line numbers from output" do
        result = tool.execute(arguments: { file: test_file, show_line_numbers: false })

        expect(result[:error]).to be_nil
        expect(result[:content]).not_to match(/\d+\t/)
        expect(result[:content]).to include("Line 1\n")
        expect(result[:content]).to include("Line 20\n")
      end
    end

    context "with start_line and end_line" do
      it "reads specific line range" do
        result = tool.execute(arguments: { file: test_file, start_line: 5, end_line: 10 })

        expect(result[:error]).to be_nil
        expect(result[:lines_read]).to eq(6)
        expect(result[:content]).to include("Line 5")
        expect(result[:content]).to include("Line 10")
        expect(result[:content]).not_to include("Line 4")
        expect(result[:content]).not_to include("Line 11")
      end

      it "numbers lines correctly based on start_line" do
        result = tool.execute(arguments: { file: test_file, start_line: 5, end_line: 7 })

        expect(result[:content]).to match(/\s+5\tLine 5/)
        expect(result[:content]).to match(/\s+6\tLine 6/)
        expect(result[:content]).to match(/\s+7\tLine 7/)
      end

      it "handles start_line beyond file length" do
        result = tool.execute(arguments: { file: test_file, start_line: 100, end_line: 110 })

        expect(result[:error]).to be_nil
        expect(result[:lines_read]).to eq(0)
        expect(result[:content]).to eq("")
      end

      it "clamps end_line to file length" do
        result = tool.execute(arguments: { file: test_file, start_line: 18, end_line: 100 })

        expect(result[:error]).to be_nil
        expect(result[:lines_read]).to eq(3)
        expect(result[:content]).to include("Line 18")
        expect(result[:content]).to include("Line 20")
      end
    end

    context "with offset and limit" do
      it "reads lines starting from offset" do
        result = tool.execute(arguments: { file: test_file, offset: 5, limit: 3 })

        expect(result[:error]).to be_nil
        expect(result[:lines_read]).to eq(3)
        expect(result[:content]).to include("Line 6")
        expect(result[:content]).to include("Line 8")
        expect(result[:content]).not_to include("Line 5")
        expect(result[:content]).not_to include("Line 9")
      end

      it "numbers lines correctly based on offset" do
        result = tool.execute(arguments: { file: test_file, offset: 5, limit: 3 })

        expect(result[:content]).to match(/\s+6\tLine 6/)
        expect(result[:content]).to match(/\s+7\tLine 7/)
        expect(result[:content]).to match(/\s+8\tLine 8/)
      end

      it "handles offset beyond file length" do
        result = tool.execute(arguments: { file: test_file, offset: 100, limit: 10 })

        expect(result[:error]).to be_nil
        expect(result[:lines_read]).to eq(0)
        expect(result[:content]).to eq("")
      end

      it "handles offset near end of file" do
        result = tool.execute(arguments: { file: test_file, offset: 18, limit: 10 })

        expect(result[:error]).to be_nil
        expect(result[:lines_read]).to eq(2)
        expect(result[:content]).to include("Line 19")
        expect(result[:content]).to include("Line 20")
      end
    end

    context "with limit only" do
      it "reads first N lines" do
        result = tool.execute(arguments: { file: test_file, limit: 5 })

        expect(result[:error]).to be_nil
        expect(result[:lines_read]).to eq(5)
        expect(result[:content]).to include("Line 1")
        expect(result[:content]).to include("Line 5")
        expect(result[:content]).not_to include("Line 6")
      end

      it "numbers lines from 1 when using limit only" do
        result = tool.execute(arguments: { file: test_file, limit: 3 })

        expect(result[:content]).to match(/\s+1\tLine 1/)
        expect(result[:content]).to match(/\s+2\tLine 2/)
        expect(result[:content]).to match(/\s+3\tLine 3/)
      end
    end

    context "with truncation" do
      it "sets truncated to true when limit is reached and file has more lines" do
        result = tool.execute(arguments: { file: test_file, limit: 10 })

        expect(result[:lines_read]).to eq(10)
        expect(result[:total_lines]).to eq(20)
        expect(result[:truncated]).to be true
      end

      it "sets truncated to false when all lines are read" do
        result = tool.execute(arguments: { file: test_file, limit: 100 })

        expect(result[:lines_read]).to eq(20)
        expect(result[:total_lines]).to eq(20)
        expect(result[:truncated]).to be false
      end

      it "sets truncated to false when lines_read equals limit but equals total_lines" do
        result = tool.execute(arguments: { file: test_file, limit: 20 })

        expect(result[:lines_read]).to eq(20)
        expect(result[:total_lines]).to eq(20)
        expect(result[:truncated]).to be false
      end
    end

    context "with file read errors" do
      it "handles StandardError during file operations" do
        # Mock File.readlines to raise an error
        allow(File).to receive(:readlines).and_raise(StandardError.new("Disk error"))

        result = tool.execute(arguments: { file: test_file })

        expect(result[:error]).to include("Failed to read file: Disk error")
        expect(result[:content]).to be_nil
      end
    end

    context "with large files" do
      it "respects default 2000 line limit" do
        # Create a file with 3000 lines
        large_file = File.join(test_dir, "large.txt")
        content = (1..3000).map { |i| "Line #{i}\n" }.join
        File.write(large_file, content)

        result = tool.execute(arguments: { file: large_file })

        expect(result[:error]).to be_nil
        expect(result[:lines_read]).to eq(2000)
        expect(result[:total_lines]).to eq(3000)
        expect(result[:truncated]).to be true
      end
    end
  end

  describe "metadata" do
    describe "#operation_type" do
      it "returns :read" do
        expect(tool.operation_type).to eq(:read)
      end
    end

    describe "#scope" do
      it "returns :confined" do
        expect(tool.scope).to eq(:confined)
      end
    end
  end
end
