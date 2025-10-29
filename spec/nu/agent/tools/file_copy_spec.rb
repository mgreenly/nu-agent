# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Nu::Agent::Tools::FileCopy do
  let(:tool) { described_class.new }
  let(:test_dir) { File.join(Dir.pwd, "tmp", "file_copy_test") }
  let(:source_file) { File.join(test_dir, "source.txt") }
  let(:dest_file) { File.join(test_dir, "destination.txt") }

  before do
    FileUtils.rm_rf(test_dir)
    FileUtils.mkdir_p(test_dir)
  end

  after do
    FileUtils.rm_rf(test_dir)
  end

  describe "#name" do
    it "returns the tool name" do
      expect(tool.name).to eq("file_copy")
    end
  end

  describe "#description" do
    it "returns a description" do
      expect(tool.description).to include("PREFERRED tool for copying files")
    end

    it "mentions the original remains unchanged" do
      expect(tool.description).to include("original remains unchanged")
    end

    it "mentions it creates parent directories automatically" do
      expect(tool.description).to include("creates destination parent directories")
    end

    it "includes a warning about overwriting" do
      expect(tool.description).to include("WARNING")
      expect(tool.description).to include("Overwrites destination")
    end
  end

  describe "#parameters" do
    it "defines expected parameters" do
      params = tool.parameters

      expect(params).to have_key(:source)
      expect(params).to have_key(:destination)
    end

    it "marks source as required" do
      expect(tool.parameters[:source][:required]).to be true
    end

    it "marks destination as required" do
      expect(tool.parameters[:destination][:required]).to be true
    end
  end

  describe "#execute" do
    context "with missing parameters" do
      it "returns error when source is nil" do
        result = tool.execute(arguments: { destination: dest_file })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to eq("source path is required")
      end

      it "returns error when source is empty string" do
        result = tool.execute(arguments: { source: "", destination: dest_file })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to eq("source path is required")
      end

      it "returns error when destination is nil" do
        result = tool.execute(arguments: { source: source_file })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to eq("destination path is required")
      end

      it "returns error when destination is empty string" do
        result = tool.execute(arguments: { source: source_file, destination: "" })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to eq("destination path is required")
      end
    end

    context "with path validation errors" do
      before do
        File.write(source_file, "test content")
      end

      it "returns error when source path is outside project directory" do
        result = tool.execute(arguments: { source: "/etc/passwd", destination: dest_file })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Access denied")
        expect(result[:error]).to include("must be within project directory")
      end

      it "returns error when destination path is outside project directory" do
        result = tool.execute(arguments: { source: source_file, destination: "/tmp/outside.txt" })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Access denied")
        expect(result[:error]).to include("must be within project directory")
      end

      it "returns error when source path contains .. that resolves outside project" do
        result = tool.execute(arguments: { source: "tmp/../../../etc/passwd", destination: dest_file })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Access denied")
        expect(result[:error]).to include("must be within project directory")
      end

      it "returns error when source path contains .. in filename itself" do
        weird_file = File.join(test_dir, "file..txt")
        File.write(weird_file, "content")

        result = tool.execute(arguments: { source: weird_file, destination: dest_file })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Access denied")
        expect(result[:error]).to include("cannot contain '..'")
      end

      it "returns error when destination path contains .. in filename itself" do
        result = tool.execute(arguments: { source: source_file, destination: File.join(test_dir, "dest..txt") })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Access denied")
        expect(result[:error]).to include("cannot contain '..'")
      end
    end

    context "with source file validation errors" do
      it "returns error when source file does not exist" do
        result = tool.execute(arguments: { source: source_file, destination: dest_file })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Source file not found")
      end

      it "returns error when source is a directory" do
        dir_path = File.join(test_dir, "directory")
        FileUtils.mkdir_p(dir_path)

        result = tool.execute(arguments: { source: dir_path, destination: dest_file })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Source is not a file")
      end
    end

    context "with path resolution" do
      before do
        File.write(source_file, "test content")
      end

      it "handles absolute paths for source" do
        result = tool.execute(arguments: { source: source_file, destination: dest_file })

        expect(result[:status]).to eq("success")
        expect(result[:source]).to eq(source_file)
      end

      it "handles relative paths for source" do
        relative_source = File.join("tmp", "file_copy_test", "source.txt")
        result = tool.execute(arguments: { source: relative_source, destination: dest_file })

        expect(result[:status]).to eq("success")
        expect(result[:source]).to eq(relative_source)
      end

      it "handles absolute paths for destination" do
        result = tool.execute(arguments: { source: source_file, destination: dest_file })

        expect(result[:status]).to eq("success")
        expect(result[:destination]).to eq(dest_file)
      end

      it "handles relative paths for destination" do
        relative_dest = File.join("tmp", "file_copy_test", "destination.txt")
        result = tool.execute(arguments: { source: source_file, destination: relative_dest })

        expect(result[:status]).to eq("success")
        expect(result[:destination]).to eq(relative_dest)
      end
    end

    context "with string keys in arguments" do
      before do
        File.write(source_file, "test content")
      end

      it "accepts string keys for all parameters" do
        result = tool.execute(
          arguments: {
            "source" => source_file,
            "destination" => dest_file
          }
        )

        expect(result[:status]).to eq("success")
      end
    end

    context "when copying files successfully" do
      before do
        File.write(source_file, "test content")
      end

      it "returns success status" do
        result = tool.execute(arguments: { source: source_file, destination: dest_file })

        expect(result[:status]).to eq("success")
      end

      it "returns success message" do
        result = tool.execute(arguments: { source: source_file, destination: dest_file })

        expect(result[:message]).to include("copied successfully")
      end

      it "includes source path in response" do
        result = tool.execute(arguments: { source: source_file, destination: dest_file })

        expect(result[:source]).to eq(source_file)
      end

      it "includes destination path in response" do
        result = tool.execute(arguments: { source: source_file, destination: dest_file })

        expect(result[:destination]).to eq(dest_file)
      end

      it "includes bytes_copied in response" do
        result = tool.execute(arguments: { source: source_file, destination: dest_file })

        expect(result[:bytes_copied]).to eq(12) # "test content" is 12 bytes
      end

      it "actually copies the file" do
        tool.execute(arguments: { source: source_file, destination: dest_file })

        expect(File.exist?(dest_file)).to be true
      end

      it "preserves the source file" do
        tool.execute(arguments: { source: source_file, destination: dest_file })

        expect(File.exist?(source_file)).to be true
      end

      it "preserves file content in destination" do
        original_content = "test content with data"
        File.write(source_file, original_content)

        tool.execute(arguments: { source: source_file, destination: dest_file })

        expect(File.read(dest_file)).to eq(original_content)
      end

      it "preserves file content in source" do
        original_content = "test content with data"
        File.write(source_file, original_content)

        tool.execute(arguments: { source: source_file, destination: dest_file })

        expect(File.read(source_file)).to eq(original_content)
      end
    end

    context "when copying to different directory" do
      before do
        File.write(source_file, "test content")
      end

      it "copies file to subdirectory" do
        subdir_dest = File.join(test_dir, "subdir", "copied.txt")
        result = tool.execute(arguments: { source: source_file, destination: subdir_dest })

        expect(result[:status]).to eq("success")
        expect(File.exist?(source_file)).to be true
        expect(File.exist?(subdir_dest)).to be true
      end

      it "creates parent directories if they don't exist" do
        nested_dest = File.join(test_dir, "level1", "level2", "level3", "copied.txt")
        tool.execute(arguments: { source: source_file, destination: nested_dest })

        expect(File.exist?(nested_dest)).to be true
        expect(Dir.exist?(File.join(test_dir, "level1", "level2", "level3"))).to be true
      end
    end

    context "when destination already exists" do
      before do
        File.write(source_file, "source content")
        File.write(dest_file, "destination content")
      end

      it "overwrites the destination file" do
        tool.execute(arguments: { source: source_file, destination: dest_file })

        expect(File.exist?(source_file)).to be true
        expect(File.exist?(dest_file)).to be true
        expect(File.read(dest_file)).to eq("source content")
      end
    end

    context "with copy errors" do
      before do
        File.write(source_file, "test content")
      end

      it "handles StandardError during copy operation" do
        # Mock FileUtils.cp to raise an error
        allow(FileUtils).to receive(:cp).and_raise(StandardError.new("Permission denied"))

        result = tool.execute(arguments: { source: source_file, destination: dest_file })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Failed to copy file")
        expect(result[:error]).to include("Permission denied")
      end
    end
  end
end
