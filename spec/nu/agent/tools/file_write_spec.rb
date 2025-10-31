# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Nu::Agent::Tools::FileWrite do
  let(:tool) { described_class.new }
  let(:test_dir) { File.join(Dir.pwd, "tmp", "file_write_test") }
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
      expect(tool.name).to eq("file_write")
    end
  end

  describe "#description" do
    it "returns a description" do
      expect(tool.description).to include("PREFERRED tool for creating new files")
      expect(tool.description).to include("WARNING: Replaces entire file contents")
    end
  end

  describe "#parameters" do
    it "defines expected parameters" do
      params = tool.parameters

      expect(params).to have_key(:file)
      expect(params).to have_key(:content)
    end

    it "marks file as required" do
      expect(tool.parameters[:file][:required]).to be true
    end

    it "marks content as required" do
      expect(tool.parameters[:content][:required]).to be true
    end
  end

  describe "#execute" do
    context "with missing file parameter" do
      it "returns error when file is nil" do
        result = tool.execute(arguments: { content: "test" })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to eq("file path is required")
      end

      it "returns error when file is empty string" do
        result = tool.execute(arguments: { file: "", content: "test" })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to eq("file path is required")
      end
    end

    context "with missing content parameter" do
      it "returns error when content is nil" do
        result = tool.execute(arguments: { file: test_file })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to eq("content is required")
      end

      it "allows empty string content" do
        result = tool.execute(arguments: { file: test_file, content: "" })

        expect(result[:status]).to eq("success")
        expect(result[:bytes_written]).to eq(0)
        expect(result[:lines_written]).to eq(0)
        expect(File.read(test_file)).to eq("")
      end
    end

    context "with path resolution" do
      it "handles absolute paths" do
        result = tool.execute(arguments: { file: test_file, content: "test content" })

        expect(result[:status]).to eq("success")
        expect(result[:file]).to eq(test_file)
        expect(File.read(test_file)).to eq("test content")
      end

      it "handles relative paths" do
        relative_path = File.join("tmp", "file_write_test", "relative.txt")
        result = tool.execute(arguments: { file: relative_path, content: "test content" })

        expect(result[:status]).to eq("success")
        expect(result[:file]).to eq(relative_path)
        expect(File.exist?(File.join(Dir.pwd, relative_path))).to be true
      end
    end

    context "with path security validation" do
      it "raises error when path is outside project directory" do
        outside_path = "/tmp/outside_project.txt"

        expect do
          tool.execute(arguments: { file: outside_path, content: "test" })
        end.to raise_error(ArgumentError, /Access denied: File must be within project directory/)
      end

      it "raises error when validate_path receives path containing .." do
        # Test the validate_path method directly since File.expand_path normalizes ".." before validation
        path_with_dotdot = File.join(Dir.pwd, "some", "..", "path")

        expect do
          tool.send(:validate_path, path_with_dotdot)
        end.to raise_error(ArgumentError, /Access denied: Path cannot contain '..'/)
      end
    end

    context "with string keys in arguments" do
      it "accepts string keys for all parameters" do
        result = tool.execute(arguments: { "file" => test_file, "content" => "test content" })

        expect(result[:status]).to eq("success")
        expect(result[:file]).to eq(test_file)
        expect(File.read(test_file)).to eq("test content")
      end
    end

    context "with parent directory creation" do
      it "creates parent directories if they do not exist" do
        nested_file = File.join(test_dir, "deeply", "nested", "path", "file.txt")
        expect(File.exist?(File.dirname(nested_file))).to be false

        result = tool.execute(arguments: { file: nested_file, content: "nested content" })

        expect(result[:status]).to eq("success")
        expect(File.exist?(nested_file)).to be true
        expect(File.read(nested_file)).to eq("nested content")
      end
    end

    context "with write errors" do
      it "handles StandardError during file write" do
        allow(File).to receive(:write).and_raise(StandardError.new("Permission denied"))

        result = tool.execute(arguments: { file: test_file, content: "test" })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Failed to write file: Permission denied")
      end
    end

    context "successful writes" do
      it "writes content and returns success" do
        result = tool.execute(arguments: { file: test_file, content: "test content" })

        expect(result[:status]).to eq("success")
        expect(result[:file]).to eq(test_file)
        expect(result[:bytes_written]).to eq("test content".bytesize)
        expect(result[:lines_written]).to eq(1)
        expect(File.read(test_file)).to eq("test content")
      end

      it "overwrites existing file content" do
        File.write(test_file, "old content")

        result = tool.execute(arguments: { file: test_file, content: "new content" })

        expect(result[:status]).to eq("success")
        expect(File.read(test_file)).to eq("new content")
      end

      it "correctly counts bytes for multi-byte characters" do
        content = "Hello 世界"
        result = tool.execute(arguments: { file: test_file, content: content })

        expect(result[:status]).to eq("success")
        expect(result[:bytes_written]).to eq(content.bytesize)
        expect(result[:bytes_written]).to be > content.length
      end

      it "correctly counts lines in multi-line content" do
        content = "Line 1\nLine 2\nLine 3\n"
        result = tool.execute(arguments: { file: test_file, content: content })

        expect(result[:status]).to eq("success")
        expect(result[:lines_written]).to eq(3)
      end

      it "counts single line for content without newline" do
        content = "Single line"
        result = tool.execute(arguments: { file: test_file, content: content })

        expect(result[:status]).to eq("success")
        expect(result[:lines_written]).to eq(1)
      end
    end
  end

  describe "metadata" do
    describe "#operation_type" do
      it "returns :write" do
        expect(tool.operation_type).to eq(:write)
      end
    end

    describe "#scope" do
      it "returns :confined" do
        expect(tool.scope).to eq(:confined)
      end
    end
  end
end
