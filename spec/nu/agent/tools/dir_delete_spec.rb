# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Nu::Agent::Tools::DirDelete do
  let(:tool) { described_class.new }
  let(:test_dir) { File.join(Dir.pwd, "tmp", "dir_delete_test") }
  let(:target_dir) { File.join(test_dir, "to_delete") }

  before do
    FileUtils.rm_rf(test_dir)
    FileUtils.mkdir_p(test_dir)
  end

  after do
    FileUtils.rm_rf(test_dir)
  end

  describe "#name" do
    it "returns the tool name" do
      expect(tool.name).to eq("dir_delete")
    end
  end

  describe "#description" do
    it "returns a description" do
      expect(tool.description).to include("PREFERRED tool for deleting directories")
    end

    it "mentions two-step confirmation" do
      expect(tool.description).to include("TWO-STEP CONFIRMATION")
    end

    it "includes a warning about permanent deletion" do
      expect(tool.description).to include("WARNING")
      expect(tool.description).to include("Cannot be undone")
    end
  end

  describe "#parameters" do
    it "defines expected parameters" do
      params = tool.parameters

      expect(params).to have_key(:path)
      expect(params).to have_key(:confirm_delete)
    end

    it "marks path as required" do
      expect(tool.parameters[:path][:required]).to be true
    end

    it "marks confirm_delete as optional" do
      expect(tool.parameters[:confirm_delete][:required]).to be false
    end
  end

  describe "#execute" do
    context "with missing path parameter" do
      it "returns error when path is nil" do
        result = tool.execute(arguments: {})

        expect(result[:status]).to eq("error")
        expect(result[:error]).to eq("path is required")
      end

      it "returns error when path is empty string" do
        result = tool.execute(arguments: { path: "" })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to eq("path is required")
      end
    end

    context "with path validation errors" do
      it "returns error when path is outside project directory" do
        result = tool.execute(arguments: { path: "/etc/some_dir" })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Access denied")
        expect(result[:error]).to include("must be within project directory")
      end

      it "returns error when path contains .. that resolves outside project" do
        result = tool.execute(arguments: { path: "tmp/../../../etc" })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Access denied")
        expect(result[:error]).to include("must be within project directory")
      end

      it "returns error when path contains .. in directory name itself" do
        weird_dir = File.join(test_dir, "dir..name")
        FileUtils.mkdir_p(weird_dir)

        result = tool.execute(arguments: { path: weird_dir })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Access denied")
        expect(result[:error]).to include("cannot contain '..'")
      end

      it "returns error when attempting to delete project root" do
        result = tool.execute(arguments: { path: Dir.pwd })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Access denied")
        expect(result[:error]).to include("Cannot delete project root directory")
      end

      it "returns error when directory does not exist" do
        result = tool.execute(arguments: { path: File.join(test_dir, "nonexistent") })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Directory not found")
      end
    end

    context "with path resolution" do
      before do
        FileUtils.mkdir_p(target_dir)
      end

      it "handles absolute paths" do
        result = tool.execute(arguments: { path: target_dir })

        expect(result[:status]).to eq("confirmation_required")
        expect(result[:path]).to eq(target_dir)
      end

      it "handles relative paths" do
        relative_path = File.join("tmp", "dir_delete_test", "to_delete")
        result = tool.execute(arguments: { path: relative_path })

        expect(result[:status]).to eq("confirmation_required")
        expect(result[:path]).to eq(relative_path)
      end
    end

    context "with string keys in arguments" do
      before do
        FileUtils.mkdir_p(target_dir)
      end

      it "accepts string keys for all parameters" do
        result = tool.execute(
          arguments: {
            "path" => target_dir,
            "confirm_delete" => false
          }
        )

        expect(result[:status]).to eq("confirmation_required")
      end
    end

    context "in preview mode (confirm_delete not set or false)" do
      before do
        FileUtils.mkdir_p(target_dir)
        File.write(File.join(target_dir, "file1.txt"), "content1")
        File.write(File.join(target_dir, "file2.txt"), "content2")
        FileUtils.mkdir_p(File.join(target_dir, "subdir"))
        File.write(File.join(target_dir, "subdir", "file3.txt"), "content3")
      end

      it "returns confirmation_required status when confirm_delete is not provided" do
        result = tool.execute(arguments: { path: target_dir })

        expect(result[:status]).to eq("confirmation_required")
      end

      it "returns confirmation_required status when confirm_delete is false" do
        result = tool.execute(arguments: { path: target_dir, confirm_delete: false })

        expect(result[:status]).to eq("confirmation_required")
      end

      it "returns file count" do
        result = tool.execute(arguments: { path: target_dir })

        expect(result[:files_to_delete]).to eq(3)
      end

      it "returns directory count" do
        result = tool.execute(arguments: { path: target_dir })

        expect(result[:directories_to_delete]).to eq(1)
      end

      it "returns total size in bytes" do
        result = tool.execute(arguments: { path: target_dir })

        # 3 files with "content1", "content2", "content3" = 8 + 8 + 8 = 24 bytes
        expect(result[:total_size_bytes]).to eq(24)
      end

      it "includes warning message" do
        result = tool.execute(arguments: { path: target_dir })

        expect(result[:warning]).to include("DESTRUCTIVE OPERATION")
        expect(result[:warning]).to include("permanently delete")
      end

      it "includes instructions for confirmation" do
        result = tool.execute(arguments: { path: target_dir })

        expect(result[:message]).to include("confirm_delete: true")
      end

      it "sets confirmed to false" do
        result = tool.execute(arguments: { path: target_dir })

        expect(result[:confirmed]).to be false
      end

      it "does not delete the directory" do
        tool.execute(arguments: { path: target_dir })

        expect(Dir.exist?(target_dir)).to be true
      end
    end

    context "with empty directory" do
      before do
        FileUtils.mkdir_p(target_dir)
      end

      it "returns zero counts for empty directory" do
        result = tool.execute(arguments: { path: target_dir })

        expect(result[:files_to_delete]).to eq(0)
        expect(result[:directories_to_delete]).to eq(0)
        expect(result[:total_size_bytes]).to eq(0)
      end
    end

    context "in deletion mode (confirm_delete=true)" do
      before do
        FileUtils.mkdir_p(target_dir)
        File.write(File.join(target_dir, "file1.txt"), "content1")
        File.write(File.join(target_dir, "file2.txt"), "content2")
        FileUtils.mkdir_p(File.join(target_dir, "subdir"))
        File.write(File.join(target_dir, "subdir", "file3.txt"), "content3")
      end

      it "returns success status" do
        result = tool.execute(arguments: { path: target_dir, confirm_delete: true })

        expect(result[:status]).to eq("success")
      end

      it "returns success message" do
        result = tool.execute(arguments: { path: target_dir, confirm_delete: true })

        expect(result[:message]).to include("deleted successfully")
      end

      it "returns count of files deleted" do
        result = tool.execute(arguments: { path: target_dir, confirm_delete: true })

        expect(result[:files_deleted]).to eq(3)
      end

      it "returns count of directories deleted" do
        result = tool.execute(arguments: { path: target_dir, confirm_delete: true })

        expect(result[:directories_deleted]).to eq(1)
      end

      it "sets confirmed to true" do
        result = tool.execute(arguments: { path: target_dir, confirm_delete: true })

        expect(result[:confirmed]).to be true
      end

      it "actually deletes the directory" do
        tool.execute(arguments: { path: target_dir, confirm_delete: true })

        expect(Dir.exist?(target_dir)).to be false
      end

      it "deletes all files and subdirectories" do
        tool.execute(arguments: { path: target_dir, confirm_delete: true })

        expect(File.exist?(File.join(target_dir, "file1.txt"))).to be false
        expect(File.exist?(File.join(target_dir, "subdir", "file3.txt"))).to be false
        expect(Dir.exist?(File.join(target_dir, "subdir"))).to be false
      end
    end

    context "with deletion errors" do
      before do
        FileUtils.mkdir_p(target_dir)
      end

      it "handles StandardError during deletion from perform_deletion" do
        # Mock FileUtils.rm_rf to raise an error for target_dir only
        allow(FileUtils).to receive(:rm_rf).and_call_original
        allow(FileUtils).to receive(:rm_rf).with(target_dir).and_raise(StandardError.new("Permission denied"))

        result = tool.execute(arguments: { path: target_dir, confirm_delete: true })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Failed to delete directory")
        expect(result[:error]).to include("Permission denied")
      end

      it "handles StandardError during stats calculation" do
        # Mock Dir.glob to raise an error during stats calculation
        allow(Dir).to receive(:glob).and_raise(StandardError.new("I/O error"))

        result = tool.execute(arguments: { path: target_dir })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Failed to process directory")
        expect(result[:error]).to include("I/O error")
      end
    end

    context "with complex directory structure" do
      before do
        # Create a more complex structure
        FileUtils.mkdir_p(File.join(target_dir, "level1", "level2", "level3"))
        10.times do |i|
          File.write(File.join(target_dir, "file#{i}.txt"), "content#{i}")
        end
        File.write(File.join(target_dir, "level1", "file.txt"), "nested")
        File.write(File.join(target_dir, "level1", "level2", "deep.txt"), "deep")
      end

      it "counts all files recursively" do
        result = tool.execute(arguments: { path: target_dir })

        expect(result[:files_to_delete]).to eq(12)
      end

      it "counts all directories recursively" do
        result = tool.execute(arguments: { path: target_dir })

        expect(result[:directories_to_delete]).to eq(3)
      end

      it "calculates total size correctly" do
        result = tool.execute(arguments: { path: target_dir })

        # 10 files with "content0" through "content9" (8-9 bytes each)
        # + "nested" (6 bytes) + "deep" (4 bytes)
        expected_size = (0..9).sum { |i| "content#{i}".bytesize } + 6 + 4
        expect(result[:total_size_bytes]).to eq(expected_size)
      end

      it "deletes entire structure when confirmed" do
        tool.execute(arguments: { path: target_dir, confirm_delete: true })

        expect(Dir.exist?(target_dir)).to be false
        expect(Dir.exist?(File.join(target_dir, "level1", "level2", "level3"))).to be false
      end
    end
  end
end
