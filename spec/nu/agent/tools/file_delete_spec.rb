# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Nu::Agent::Tools::FileDelete do
  let(:tool) { described_class.new }
  let(:test_dir) { File.join(Dir.pwd, "tmp", "file_delete_test") }
  let(:test_file) { File.join(test_dir, "test.txt") }

  before do
    FileUtils.rm_rf(test_dir)
    FileUtils.mkdir_p(test_dir)
    File.write(test_file, "test content")
  end

  after do
    FileUtils.rm_rf(test_dir)
  end

  describe "#name" do
    it "returns the tool name" do
      expect(tool.name).to eq("file_delete")
    end
  end

  describe "#description" do
    it "returns a description" do
      expect(tool.description).to include("PREFERRED tool for deleting files")
      expect(tool.description).to include("WARNING: Cannot be undone")
    end
  end

  describe "#parameters" do
    it "defines expected parameters" do
      params = tool.parameters

      expect(params).to have_key(:file)
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
        result = tool.execute(arguments: { file: "" })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to eq("file path is required")
      end
    end

    context "with file validation errors" do
      it "returns error when file does not exist" do
        result = tool.execute(arguments: { file: File.join(test_dir, "nonexistent.txt") })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("File not found")
      end

      it "returns error when path is a directory" do
        result = tool.execute(arguments: { file: test_dir })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Not a file")
      end
    end

    context "with path resolution" do
      it "handles absolute paths" do
        result = tool.execute(arguments: { file: test_file })

        expect(result[:status]).to eq("success")
        expect(result[:file]).to eq(test_file)
        expect(result[:message]).to eq("File deleted successfully")
        expect(File.exist?(test_file)).to be false
      end

      it "handles relative paths" do
        relative_path = File.join("tmp", "file_delete_test", "test.txt")
        result = tool.execute(arguments: { file: relative_path })

        expect(result[:status]).to eq("success")
        expect(result[:file]).to eq(relative_path)
        expect(result[:message]).to eq("File deleted successfully")
        expect(File.exist?(test_file)).to be false
      end
    end

    context "with path security validation" do
      it "raises error when path is outside project directory" do
        outside_path = "/tmp/outside_project.txt"
        File.write(outside_path, "content")

        expect do
          tool.execute(arguments: { file: outside_path })
        end.to raise_error(ArgumentError, /Access denied: File must be within project directory/)

        # Clean up
        FileUtils.rm_f(outside_path)
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
      it "accepts string keys for file parameter" do
        result = tool.execute(arguments: { "file" => test_file })

        expect(result[:status]).to eq("success")
        expect(result[:file]).to eq(test_file)
        expect(File.exist?(test_file)).to be false
      end
    end

    context "with deletion errors" do
      it "handles StandardError during file deletion" do
        allow(File).to receive(:delete).and_raise(StandardError.new("Permission denied"))

        result = tool.execute(arguments: { file: test_file })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Failed to delete file: Permission denied")
      end
    end

    context "successful deletion" do
      it "deletes the file and returns success" do
        expect(File.exist?(test_file)).to be true

        result = tool.execute(arguments: { file: test_file })

        expect(result[:status]).to eq("success")
        expect(result[:file]).to eq(test_file)
        expect(result[:message]).to eq("File deleted successfully")
        expect(File.exist?(test_file)).to be false
      end
    end
  end
end
