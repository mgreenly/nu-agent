# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Nu::Agent::Tools::FileTree do
  let(:tool) { described_class.new }
  let(:test_dir) { File.join(Dir.pwd, "tmp", "file_tree_test") }

  before do
    FileUtils.rm_rf(test_dir)
    FileUtils.mkdir_p(test_dir)
  end

  after do
    FileUtils.rm_rf(test_dir)
  end

  describe "#name" do
    it "returns the tool name" do
      expect(tool.name).to eq("file_tree")
    end
  end

  describe "#description" do
    it "returns a description" do
      expect(tool.description).to include("PREFERRED tool for discovering file structure")
    end

    it "mentions it returns a flat list of files" do
      expect(tool.description).to include("flat list of all files")
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
        relative_path = File.join("tmp", "file_tree_test")
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

    context "when listing files" do
      before do
        # Create a simple file structure
        File.write(File.join(test_dir, "file1.txt"), "content1")
        File.write(File.join(test_dir, "file2.rb"), "content2")
        FileUtils.mkdir_p(File.join(test_dir, "subdir"))
        File.write(File.join(test_dir, "subdir", "file3.txt"), "content3")
      end

      it "returns success status" do
        result = tool.execute(arguments: { path: test_dir })

        expect(result[:status]).to eq("success")
      end

      it "returns list of files" do
        result = tool.execute(arguments: { path: test_dir })

        expect(result[:files]).to include("file1.txt")
        expect(result[:files]).to include("file2.rb")
        expect(result[:files]).to include("subdir/file3.txt")
      end

      it "returns count of files returned" do
        result = tool.execute(arguments: { path: test_dir })

        expect(result[:count]).to eq(3)
      end

      it "returns total files found" do
        result = tool.execute(arguments: { path: test_dir })

        expect(result[:total_files]).to eq(3)
      end

      it "returns sorted list of files" do
        result = tool.execute(arguments: { path: test_dir })

        expect(result[:files]).to eq(result[:files].sort)
      end

      it "sets truncated to false when all files are returned" do
        result = tool.execute(arguments: { path: test_dir })

        expect(result[:truncated]).to be false
      end
    end

    context "with empty directory" do
      it "returns empty list of files" do
        result = tool.execute(arguments: { path: test_dir })

        expect(result[:status]).to eq("success")
        expect(result[:files]).to eq([])
        expect(result[:count]).to eq(0)
        expect(result[:total_files]).to eq(0)
      end
    end

    context "with max_depth parameter" do
      before do
        File.write(File.join(test_dir, "level0.txt"), "content")
        FileUtils.mkdir_p(File.join(test_dir, "level1"))
        File.write(File.join(test_dir, "level1", "level1.txt"), "content")
        FileUtils.mkdir_p(File.join(test_dir, "level1", "level2"))
        File.write(File.join(test_dir, "level1", "level2", "level2.txt"), "content")
        FileUtils.mkdir_p(File.join(test_dir, "level1", "level2", "level3"))
        File.write(File.join(test_dir, "level1", "level2", "level3", "level3.txt"), "content")
      end

      it "limits depth when max_depth is specified" do
        result = tool.execute(arguments: { path: test_dir, max_depth: 2 })

        expect(result[:status]).to eq("success")
        expect(result[:files]).to include("level0.txt")
        expect(result[:files]).to include("level1/level1.txt")
        expect(result[:files]).not_to include("level1/level2/level2.txt")
        expect(result[:files]).not_to include("level1/level2/level3/level3.txt")
      end

      it "returns all files when max_depth is not specified" do
        result = tool.execute(arguments: { path: test_dir })

        expect(result[:status]).to eq("success")
        expect(result[:files]).to include("level0.txt")
        expect(result[:files]).to include("level1/level1.txt")
        expect(result[:files]).to include("level1/level2/level2.txt")
        expect(result[:files]).to include("level1/level2/level3/level3.txt")
      end
    end

    context "with show_hidden parameter" do
      before do
        File.write(File.join(test_dir, "visible.txt"), "content")
        File.write(File.join(test_dir, ".hidden"), "content")
        FileUtils.mkdir_p(File.join(test_dir, ".hidden_dir"))
        File.write(File.join(test_dir, ".hidden_dir", "file.txt"), "content")
        FileUtils.mkdir_p(File.join(test_dir, "visible_dir"))
        File.write(File.join(test_dir, "visible_dir", ".hidden_file"), "content")
      end

      it "excludes hidden files by default" do
        result = tool.execute(arguments: { path: test_dir })

        expect(result[:status]).to eq("success")
        expect(result[:files]).to include("visible.txt")
        expect(result[:files]).not_to include(".hidden")
        expect(result[:files]).not_to include(".hidden_dir/file.txt")
        expect(result[:files]).not_to include("visible_dir/.hidden_file")
      end

      it "includes hidden files when show_hidden is true" do
        result = tool.execute(arguments: { path: test_dir, show_hidden: true })

        expect(result[:status]).to eq("success")
        expect(result[:files]).to include("visible.txt")
        expect(result[:files]).to include(".hidden")
        expect(result[:files]).to include(".hidden_dir/file.txt")
        expect(result[:files]).to include("visible_dir/.hidden_file")
      end

      it "excludes hidden files when show_hidden is false" do
        result = tool.execute(arguments: { path: test_dir, show_hidden: false })

        expect(result[:status]).to eq("success")
        expect(result[:files]).to include("visible.txt")
        expect(result[:files]).not_to include(".hidden")
      end
    end

    context "with limit parameter" do
      before do
        # Create 10 files
        10.times do |i|
          File.write(File.join(test_dir, "file#{i}.txt"), "content")
        end
      end

      it "limits results when limit is specified" do
        result = tool.execute(arguments: { path: test_dir, limit: 5 })

        expect(result[:status]).to eq("success")
        expect(result[:count]).to eq(5)
        expect(result[:total_files]).to eq(10)
        expect(result[:files].length).to eq(5)
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
        expect(result[:error]).to include("Failed to list files: Command failed")
      end

      it "handles find command failure status" do
        # Mock Open3.capture3 to return unsuccessful status
        status_double = instance_double(Process::Status, success?: false)
        allow(Open3).to receive(:capture3).and_return(["", "Permission denied", status_double])

        result = tool.execute(arguments: { path: test_dir })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Failed to list files")
        expect(result[:error]).to include("Permission denied")
      end

      it "handles paths that don't match the base path" do
        # Mock Open3.capture3 to return a path that doesn't start with base_path
        # This edge case might occur with symlinks or unusual file system scenarios
        status_double = instance_double(Process::Status, success?: true)
        unusual_output = "/some/other/path/file.txt\n"
        allow(Open3).to receive(:capture3).and_return([unusual_output, "", status_double])

        result = tool.execute(arguments: { path: test_dir })

        expect(result[:status]).to eq("success")
        # Should include the absolute path as-is when it doesn't match base_path
        expect(result[:files]).to include("/some/other/path/file.txt")
      end

      it "strips leading slashes from relative paths correctly" do
        # Create a file to ensure we get real output from find command
        File.write(File.join(test_dir, "test.txt"), "content")

        result = tool.execute(arguments: { path: test_dir })

        expect(result[:status]).to eq("success")
        # Files should not have leading slashes
        result[:files].each do |file|
          expect(file).not_to start_with("/")
        end
      end

      it "handles edge case where path results in empty relative path" do
        # Mock output where removing base_path results in empty string
        # This would return "." as the relative path
        status_double = instance_double(Process::Status, success?: true)
        # Simulate find returning the base path itself (edge case)
        allow(Open3).to receive(:capture3).and_return([test_dir, "", status_double])

        result = tool.execute(arguments: { path: test_dir })

        expect(result[:status]).to eq("success")
        expect(result[:files]).to include(".")
      end

      it "handles path without leading slash after base removal" do
        # Mock output where path doesn't have leading slash after removing base
        # This tests the else branch of the slash-stripping logic
        status_double = instance_double(Process::Status, success?: true)
        # Create a path that matches base_path but doesn't have trailing content with slash
        path_without_slash = "#{test_dir}file.txt"
        allow(Open3).to receive(:capture3).and_return([path_without_slash, "", status_double])

        result = tool.execute(arguments: { path: test_dir })

        expect(result[:status]).to eq("success")
        expect(result[:files]).to include("file.txt")
      end
    end

    context "with complex file structure" do
      before do
        # Create a more complex structure
        FileUtils.mkdir_p(File.join(test_dir, "app", "models"))
        File.write(File.join(test_dir, "app", "models", "user.rb"), "content")
        File.write(File.join(test_dir, "app", "models", "post.rb"), "content")
        FileUtils.mkdir_p(File.join(test_dir, "app", "controllers"))
        File.write(File.join(test_dir, "app", "controllers", "users_controller.rb"), "content")
        FileUtils.mkdir_p(File.join(test_dir, "lib"))
        File.write(File.join(test_dir, "lib", "util.rb"), "content")
        FileUtils.mkdir_p(File.join(test_dir, ".git", "objects"))
        File.write(File.join(test_dir, ".git", "config"), "content")
      end

      it "finds all visible files" do
        result = tool.execute(arguments: { path: test_dir })

        expect(result[:status]).to eq("success")
        expect(result[:files]).to include("app/models/user.rb")
        expect(result[:files]).to include("app/models/post.rb")
        expect(result[:files]).to include("app/controllers/users_controller.rb")
        expect(result[:files]).to include("lib/util.rb")
        expect(result[:files]).not_to include(".git/config")
      end

      it "combines max_depth and show_hidden parameters" do
        result = tool.execute(arguments: { path: test_dir, max_depth: 2, show_hidden: true })

        expect(result[:status]).to eq("success")
        # max_depth=2 means: level 0 (test_dir), level 1 (app, lib, .git), level 2 (models, controllers)
        expect(result[:files]).to include("lib/util.rb")
        expect(result[:files]).not_to include("app/models/user.rb")
        expect(result[:files]).not_to include("app/controllers/users_controller.rb")
        expect(result[:files]).to include(".git/config")
      end
    end
  end
end
