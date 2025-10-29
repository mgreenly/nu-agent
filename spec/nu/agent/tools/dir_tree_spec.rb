# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Nu::Agent::Tools::DirTree do
  let(:tool) { described_class.new }
  let(:test_dir) { File.join(Dir.pwd, "tmp", "dir_tree_test") }

  before do
    FileUtils.rm_rf(test_dir)
    FileUtils.mkdir_p(test_dir)
  end

  after do
    FileUtils.rm_rf(test_dir)
  end

  describe "#name" do
    it "returns the tool name" do
      expect(tool.name).to eq("dir_tree")
    end
  end

  describe "#description" do
    it "returns a description" do
      expect(tool.description).to include("PREFERRED tool for discovering directory structure")
    end

    it "mentions it returns a flat list of subdirectories" do
      expect(tool.description).to include("flat list of all subdirectories")
    end

    it "suggests using it instead of bash commands" do
      expect(tool.description).to include("instead of execute_bash")
    end
  end

  describe "#parameters" do
    it "defines expected parameters" do
      params = tool.parameters

      expect(params).to have_key(:path)
      expect(params).to have_key(:max_depth)
      expect(params).to have_key(:show_hidden)
      expect(params).to have_key(:limit)
    end

    it "marks all parameters as optional" do
      params = tool.parameters

      expect(params[:path][:required]).to be false
      expect(params[:max_depth][:required]).to be false
      expect(params[:show_hidden][:required]).to be false
      expect(params[:limit][:required]).to be false
    end
  end

  describe "#execute" do
    context "with missing path parameter" do
      it "defaults to current directory" do
        result = tool.execute(arguments: {})

        expect(result[:status]).to eq("success")
        expect(result[:path]).to eq(".")
      end
    end

    context "with path validation errors" do
      it "returns error when path is outside project directory" do
        result = tool.execute(arguments: { path: "/etc" })

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

      it "returns error when path does not exist" do
        result = tool.execute(arguments: { path: File.join(test_dir, "nonexistent") })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Directory not found")
      end

      it "returns error when path is not a directory" do
        file_path = File.join(test_dir, "test.txt")
        File.write(file_path, "content")

        result = tool.execute(arguments: { path: file_path })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Not a directory")
      end
    end

    context "with path resolution" do
      it "handles absolute paths" do
        result = tool.execute(arguments: { path: test_dir })

        expect(result[:status]).to eq("success")
        expect(result[:path]).to eq(test_dir)
      end

      it "handles relative paths" do
        relative_path = File.join("tmp", "dir_tree_test")
        result = tool.execute(arguments: { path: relative_path })

        expect(result[:status]).to eq("success")
        expect(result[:path]).to eq(relative_path)
      end
    end

    context "with string keys in arguments" do
      it "accepts string keys for all parameters" do
        result = tool.execute(
          arguments: {
            "path" => test_dir,
            "max_depth" => 2,
            "show_hidden" => true,
            "limit" => 50
          }
        )

        expect(result[:status]).to eq("success")
      end
    end

    context "when listing directories" do
      before do
        # Create a simple directory structure
        FileUtils.mkdir_p(File.join(test_dir, "dir1"))
        FileUtils.mkdir_p(File.join(test_dir, "dir2"))
        FileUtils.mkdir_p(File.join(test_dir, "dir1", "subdir1"))
      end

      it "returns success status" do
        result = tool.execute(arguments: { path: test_dir })

        expect(result[:status]).to eq("success")
      end

      it "returns list of directories" do
        result = tool.execute(arguments: { path: test_dir })

        expect(result[:directories]).to include("dir1")
        expect(result[:directories]).to include("dir2")
        expect(result[:directories]).to include("dir1/subdir1")
      end

      it "returns count of directories returned" do
        result = tool.execute(arguments: { path: test_dir })

        expect(result[:count]).to eq(3)
      end

      it "returns total directories found" do
        result = tool.execute(arguments: { path: test_dir })

        expect(result[:total_directories]).to eq(3)
      end

      it "returns sorted list of directories" do
        result = tool.execute(arguments: { path: test_dir })

        expect(result[:directories]).to eq(result[:directories].sort)
      end

      it "sets truncated to false when all directories are returned" do
        result = tool.execute(arguments: { path: test_dir })

        expect(result[:truncated]).to be false
      end
    end

    context "with empty directory" do
      it "returns empty list of directories" do
        result = tool.execute(arguments: { path: test_dir })

        expect(result[:status]).to eq("success")
        expect(result[:directories]).to eq([])
        expect(result[:count]).to eq(0)
        expect(result[:total_directories]).to eq(0)
      end
    end

    context "with max_depth parameter" do
      before do
        FileUtils.mkdir_p(File.join(test_dir, "level1"))
        FileUtils.mkdir_p(File.join(test_dir, "level1", "level2"))
        FileUtils.mkdir_p(File.join(test_dir, "level1", "level2", "level3"))
      end

      it "limits depth when max_depth is specified" do
        result = tool.execute(arguments: { path: test_dir, max_depth: 2 })

        expect(result[:status]).to eq("success")
        expect(result[:directories]).to include("level1")
        expect(result[:directories]).to include("level1/level2")
        expect(result[:directories]).not_to include("level1/level2/level3")
      end

      it "returns all directories when max_depth is not specified" do
        result = tool.execute(arguments: { path: test_dir })

        expect(result[:status]).to eq("success")
        expect(result[:directories]).to include("level1")
        expect(result[:directories]).to include("level1/level2")
        expect(result[:directories]).to include("level1/level2/level3")
      end
    end

    context "with show_hidden parameter" do
      before do
        FileUtils.mkdir_p(File.join(test_dir, "visible"))
        FileUtils.mkdir_p(File.join(test_dir, ".hidden"))
        FileUtils.mkdir_p(File.join(test_dir, "visible", ".hidden_sub"))
      end

      it "excludes hidden directories by default" do
        result = tool.execute(arguments: { path: test_dir })

        expect(result[:status]).to eq("success")
        expect(result[:directories]).to include("visible")
        expect(result[:directories]).not_to include(".hidden")
        expect(result[:directories]).not_to include("visible/.hidden_sub")
      end

      it "includes hidden directories when show_hidden is true" do
        result = tool.execute(arguments: { path: test_dir, show_hidden: true })

        expect(result[:status]).to eq("success")
        expect(result[:directories]).to include("visible")
        expect(result[:directories]).to include(".hidden")
        expect(result[:directories]).to include("visible/.hidden_sub")
      end

      it "excludes hidden directories when show_hidden is false" do
        result = tool.execute(arguments: { path: test_dir, show_hidden: false })

        expect(result[:status]).to eq("success")
        expect(result[:directories]).to include("visible")
        expect(result[:directories]).not_to include(".hidden")
      end
    end

    context "with limit parameter" do
      before do
        # Create 10 directories
        10.times do |i|
          FileUtils.mkdir_p(File.join(test_dir, "dir#{i}"))
        end
      end

      it "limits results when limit is specified" do
        result = tool.execute(arguments: { path: test_dir, limit: 5 })

        expect(result[:status]).to eq("success")
        expect(result[:count]).to eq(5)
        expect(result[:total_directories]).to eq(10)
        expect(result[:directories].length).to eq(5)
      end

      it "sets truncated to true when results are limited" do
        result = tool.execute(arguments: { path: test_dir, limit: 5 })

        expect(result[:truncated]).to be true
      end

      it "uses default limit of 1000 when not specified" do
        result = tool.execute(arguments: { path: test_dir })

        expect(result[:status]).to eq("success")
        expect(result[:count]).to eq(10)
        expect(result[:truncated]).to be false
      end
    end

    context "with find command errors" do
      it "handles StandardError during find execution" do
        # Mock Open3.capture3 to raise an error
        allow(Open3).to receive(:capture3).and_raise(StandardError.new("Command failed"))

        result = tool.execute(arguments: { path: test_dir })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Failed to list directories: Command failed")
      end

      it "handles find command failure status" do
        # Mock Open3.capture3 to return unsuccessful status
        status_double = instance_double(Process::Status, success?: false)
        allow(Open3).to receive(:capture3).and_return(["", "Permission denied", status_double])

        result = tool.execute(arguments: { path: test_dir })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Failed to list directories")
        expect(result[:error]).to include("Permission denied")
      end

      it "handles paths that don't match the base path" do
        # Mock Open3.capture3 to return a path that doesn't start with base_path
        # This edge case might occur with symlinks or unusual file system scenarios
        status_double = instance_double(Process::Status, success?: true)
        unusual_output = "/some/other/path/subdir\n"
        allow(Open3).to receive(:capture3).and_return([unusual_output, "", status_double])

        result = tool.execute(arguments: { path: test_dir })

        expect(result[:status]).to eq("success")
        # Should include the absolute path as-is when it doesn't match base_path
        expect(result[:directories]).to include("/some/other/path/subdir")
      end
    end

    context "with complex directory structure" do
      before do
        # Create a more complex structure
        FileUtils.mkdir_p(File.join(test_dir, "app", "models"))
        FileUtils.mkdir_p(File.join(test_dir, "app", "controllers"))
        FileUtils.mkdir_p(File.join(test_dir, "app", "views", "users"))
        FileUtils.mkdir_p(File.join(test_dir, "lib", "utils"))
        FileUtils.mkdir_p(File.join(test_dir, ".git", "objects"))
      end

      it "finds all visible directories" do
        result = tool.execute(arguments: { path: test_dir })

        expect(result[:status]).to eq("success")
        expect(result[:directories]).to include("app")
        expect(result[:directories]).to include("app/models")
        expect(result[:directories]).to include("app/controllers")
        expect(result[:directories]).to include("app/views")
        expect(result[:directories]).to include("app/views/users")
        expect(result[:directories]).to include("lib")
        expect(result[:directories]).to include("lib/utils")
        expect(result[:directories]).not_to include(".git")
        expect(result[:directories]).not_to include(".git/objects")
      end

      it "combines max_depth and show_hidden parameters" do
        result = tool.execute(arguments: { path: test_dir, max_depth: 2, show_hidden: true })

        expect(result[:status]).to eq("success")
        # max_depth=2 means: level 0 (test_dir), level 1 (app, lib, .git), level 2 (app/models, etc)
        expect(result[:directories]).to include("app")
        expect(result[:directories]).to include("app/models")
        expect(result[:directories]).to include(".git")
        expect(result[:directories]).to include(".git/objects")
        # level 3 should be excluded
        expect(result[:directories]).not_to include("app/views/users")
      end
    end
  end
end
