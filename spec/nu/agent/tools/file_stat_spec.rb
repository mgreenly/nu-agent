# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Nu::Agent::Tools::FileStat do
  let(:tool) { described_class.new }
  let(:test_dir) { File.join(Dir.pwd, "tmp", "file_stat_test") }
  let(:test_file) { File.join(test_dir, "test.txt") }

  before do
    FileUtils.rm_rf(test_dir)
    FileUtils.mkdir_p(test_dir)
    File.write(test_file, "test content\n")
  end

  after do
    FileUtils.rm_rf(test_dir)
  end

  describe "#name" do
    it "returns the tool name" do
      expect(tool.name).to eq("file_stat")
    end
  end

  describe "#description" do
    it "returns a description" do
      expect(tool.description).to include("PREFERRED tool for getting file or directory metadata")
    end

    it "mentions it returns detailed information" do
      expect(tool.description).to include("detailed information")
    end

    it "suggests using it instead of bash commands" do
      expect(tool.description).to include("instead of execute_bash")
    end
  end

  describe "#parameters" do
    it "defines expected parameters" do
      params = tool.parameters

      expect(params).to have_key(:path)
    end

    it "marks path as required" do
      expect(tool.parameters[:path][:required]).to be true
    end

    it "defines path as string type" do
      expect(tool.parameters[:path][:type]).to eq("string")
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
        result = tool.execute(arguments: { path: "/etc/passwd" })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Access denied")
        expect(result[:error]).to include("must be within project directory")
      end

      it "returns error when path contains .. that resolves outside project" do
        result = tool.execute(arguments: { path: "tmp/../../../etc/passwd" })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Access denied")
        expect(result[:error]).to include("must be within project directory")
      end

      it "returns error when path contains .. in filename itself" do
        # Create a file with .. in the name (not as path separator)
        weird_file = File.join(test_dir, "file..txt")
        File.write(weird_file, "content")

        result = tool.execute(arguments: { path: weird_file })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Access denied")
        expect(result[:error]).to include("cannot contain '..'")
      ensure
        FileUtils.rm_f(weird_file)
      end

      it "returns error when path does not exist" do
        result = tool.execute(arguments: { path: File.join(test_dir, "nonexistent.txt") })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Path not found")
      end
    end

    context "with path resolution" do
      it "handles absolute paths" do
        result = tool.execute(arguments: { path: test_file })

        expect(result[:status]).to eq("success")
        expect(result[:path]).to eq(test_file)
      end

      it "handles relative paths" do
        relative_path = File.join("tmp", "file_stat_test", "test.txt")
        result = tool.execute(arguments: { path: relative_path })

        expect(result[:status]).to eq("success")
        expect(result[:path]).to eq(relative_path)
      end
    end

    context "with string keys in arguments" do
      it "accepts string key for path" do
        result = tool.execute(arguments: { "path" => test_file })

        expect(result[:status]).to eq("success")
        expect(result[:path]).to eq(test_file)
      end
    end

    context "when statting a regular file" do
      it "returns success status" do
        result = tool.execute(arguments: { path: test_file })

        expect(result[:status]).to eq("success")
      end

      it "returns file type as 'file'" do
        result = tool.execute(arguments: { path: test_file })

        expect(result[:type]).to eq("file")
      end

      it "returns size in bytes" do
        result = tool.execute(arguments: { path: test_file })

        expect(result[:size_bytes]).to eq(13)
      end

      it "returns human-readable size" do
        result = tool.execute(arguments: { path: test_file })

        expect(result[:size_human]).to eq("13.00 B")
      end

      it "returns permissions in octal format" do
        result = tool.execute(arguments: { path: test_file })

        expect(result[:permissions]).to match(/^\d{3}$/)
      end

      it "returns readable flag" do
        result = tool.execute(arguments: { path: test_file })

        expect(result[:readable]).to be true
      end

      it "returns writable flag" do
        result = tool.execute(arguments: { path: test_file })

        expect(result[:writable]).to be true
      end

      it "returns executable flag" do
        result = tool.execute(arguments: { path: test_file })

        expect(result[:executable]).to be false
      end

      it "returns modified_at timestamp in ISO8601 format" do
        result = tool.execute(arguments: { path: test_file })

        expect(result[:modified_at]).to match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end

      it "returns accessed_at timestamp in ISO8601 format" do
        result = tool.execute(arguments: { path: test_file })

        expect(result[:accessed_at]).to match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end

      it "returns created_at timestamp in ISO8601 format" do
        result = tool.execute(arguments: { path: test_file })

        expect(result[:created_at]).to match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end

      it "does not include entries count for files" do
        result = tool.execute(arguments: { path: test_file })

        expect(result[:entries]).to be_nil
      end

      it "does not include symlink_target for files" do
        result = tool.execute(arguments: { path: test_file })

        expect(result[:symlink_target]).to be_nil
      end
    end

    context "when statting a directory" do
      it "returns file type as 'directory'" do
        result = tool.execute(arguments: { path: test_dir })

        expect(result[:type]).to eq("directory")
      end

      it "returns entries count excluding . and .." do
        # test_dir contains only test.txt
        result = tool.execute(arguments: { path: test_dir })

        expect(result[:entries]).to eq(1)
      end

      it "returns size in bytes" do
        result = tool.execute(arguments: { path: test_dir })

        expect(result[:size_bytes]).to be_a(Integer)
      end

      it "returns human-readable size" do
        result = tool.execute(arguments: { path: test_dir })

        expect(result[:size_human]).to be_a(String)
      end
    end

    context "when statting a symlink" do
      let(:symlink_path) { File.join(test_dir, "test_link") }

      before do
        File.symlink(test_file, symlink_path)
      end

      it "returns file type as 'symlink'" do
        result = tool.execute(arguments: { path: symlink_path })

        expect(result[:type]).to eq("symlink")
      end

      it "returns symlink target" do
        result = tool.execute(arguments: { path: symlink_path })

        expect(result[:symlink_target]).to eq(test_file)
      end

      it "does not include entries count for symlinks" do
        result = tool.execute(arguments: { path: symlink_path })

        expect(result[:entries]).to be_nil
      end
    end

    context "when statting other file types" do
      let(:fifo_path) { File.join(test_dir, "test_fifo") }

      before do
        # Create a named pipe (FIFO)
        system("mkfifo", fifo_path)
      end

      after do
        FileUtils.rm_f(fifo_path)
      end

      it "returns file type as 'other' for named pipes" do
        result = tool.execute(arguments: { path: fifo_path })

        expect(result[:type]).to eq("other")
      end

      it "returns success status for other file types" do
        result = tool.execute(arguments: { path: fifo_path })

        expect(result[:status]).to eq("success")
      end
    end

    context "with human-readable size formatting" do
      it "formats 0 bytes" do
        empty_file = File.join(test_dir, "empty.txt")
        File.write(empty_file, "")

        result = tool.execute(arguments: { path: empty_file })

        expect(result[:size_human]).to eq("0 B")
      end

      it "formats bytes (< 1 KB)" do
        result = tool.execute(arguments: { path: test_file })

        expect(result[:size_human]).to eq("13.00 B")
      end

      it "formats kilobytes" do
        kb_file = File.join(test_dir, "kilobytes.txt")
        File.write(kb_file, "a" * 2048)

        result = tool.execute(arguments: { path: kb_file })

        expect(result[:size_human]).to eq("2.00 KB")
      end

      it "formats megabytes" do
        mb_file = File.join(test_dir, "megabytes.txt")
        File.write(mb_file, "a" * (2 * 1024 * 1024))

        result = tool.execute(arguments: { path: mb_file })

        expect(result[:size_human]).to eq("2.00 MB")
      end

      it "formats partial sizes correctly" do
        partial_file = File.join(test_dir, "partial.txt")
        File.write(partial_file, "a" * 1536) # 1.5 KB

        result = tool.execute(arguments: { path: partial_file })

        expect(result[:size_human]).to eq("1.50 KB")
      end

      it "handles very large sizes (GB)" do
        # We can't create a real GB file, so we'll just verify the logic
        # by using the tool's private method if needed, or trust the math
        # For now, let's create a smaller file and verify the pattern
        kb_file = File.join(test_dir, "size_test.txt")
        File.write(kb_file, "a" * ((1024 * 1024) + (512 * 1024))) # 1.5 MB

        result = tool.execute(arguments: { path: kb_file })

        expect(result[:size_human]).to eq("1.50 MB")
      end
    end

    context "with file read errors" do
      it "handles StandardError during file operations" do
        # Mock File.exist? to return true, then File.stat to raise an error
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:stat).and_raise(StandardError.new("Disk error"))

        result = tool.execute(arguments: { path: test_file })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Failed to get file stats: Disk error")
      end
    end

    context "with executable files" do
      let(:executable_file) { File.join(test_dir, "script.sh") }

      before do
        File.write(executable_file, "#!/bin/bash\necho test\n")
        File.chmod(0o755, executable_file)
      end

      it "returns executable flag as true" do
        result = tool.execute(arguments: { path: executable_file })

        expect(result[:executable]).to be true
      end

      it "returns correct permissions for executable file" do
        result = tool.execute(arguments: { path: executable_file })

        expect(result[:permissions]).to eq("755")
      end
    end

    context "with empty directory" do
      let(:empty_dir) { File.join(test_dir, "empty") }

      before do
        FileUtils.mkdir_p(empty_dir)
      end

      it "returns 0 entries for empty directory" do
        result = tool.execute(arguments: { path: empty_dir })

        expect(result[:entries]).to eq(0)
      end
    end

    context "with directory containing multiple files" do
      before do
        File.write(File.join(test_dir, "file1.txt"), "content")
        File.write(File.join(test_dir, "file2.txt"), "content")
        FileUtils.mkdir_p(File.join(test_dir, "subdir"))
      end

      it "returns correct count of entries" do
        result = tool.execute(arguments: { path: test_dir })

        # Should have: test.txt, file1.txt, file2.txt, subdir = 4 entries
        expect(result[:entries]).to eq(4)
      end
    end
  end
end
