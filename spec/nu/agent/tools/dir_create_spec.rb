# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Nu::Agent::Tools::DirCreate do
  let(:tool) { described_class.new }
  let(:test_dir) { File.join(Dir.pwd, "tmp", "dir_create_test") }
  let(:test_path) { File.join(test_dir, "new_directory") }

  before do
    FileUtils.rm_rf(test_dir)
    FileUtils.mkdir_p(test_dir)
  end

  after do
    FileUtils.rm_rf(test_dir)
  end

  describe "#name" do
    it "returns the tool name" do
      expect(tool.name).to eq("dir_create")
    end
  end

  describe "#description" do
    it "returns a description" do
      expect(tool.description).to include("PREFERRED tool for creating directories")
      expect(tool.description).to include("mkdir -p")
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
  end

  describe "#execute" do
    context "with missing path parameter" do
      it "returns error when path is nil" do
        result = tool.execute(arguments: {}, _context: nil)

        expect(result[:status]).to eq("error")
        expect(result[:error]).to eq("path is required")
      end

      it "returns error when path is empty string" do
        result = tool.execute(arguments: { path: "" }, _context: nil)

        expect(result[:status]).to eq("error")
        expect(result[:error]).to eq("path is required")
      end
    end

    context "with path resolution" do
      it "handles absolute paths" do
        result = tool.execute(arguments: { path: test_path }, _context: nil)

        expect(result[:status]).to eq("success")
        expect(result[:path]).to eq(test_path)
        expect(result[:created]).to be true
        expect(Dir.exist?(test_path)).to be true
      end

      it "handles relative paths" do
        relative_path = File.join("tmp", "dir_create_test", "relative_dir")
        result = tool.execute(arguments: { path: relative_path }, _context: nil)

        expect(result[:status]).to eq("success")
        expect(result[:path]).to eq(relative_path)
        expect(result[:created]).to be true
        expect(Dir.exist?(File.join(Dir.pwd, relative_path))).to be true
      end
    end

    context "with path security validation" do
      it "raises error when path is outside project directory" do
        outside_path = "/tmp/outside_project_dir"

        expect do
          tool.execute(arguments: { path: outside_path }, _context: nil)
        end.to raise_error(ArgumentError, /Access denied: Directory must be within project directory/)
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
      it "accepts string keys for path parameter" do
        result = tool.execute(arguments: { "path" => test_path }, _context: nil)

        expect(result[:status]).to eq("success")
        expect(result[:path]).to eq(test_path)
        expect(Dir.exist?(test_path)).to be true
      end
    end

    context "when directory already exists" do
      before do
        FileUtils.mkdir_p(test_path)
      end

      it "returns success without creating directory" do
        result = tool.execute(arguments: { path: test_path }, _context: nil)

        expect(result[:status]).to eq("success")
        expect(result[:path]).to eq(test_path)
        expect(result[:message]).to eq("Directory already exists")
        expect(result[:created]).to be false
      end

      it "does not raise an error" do
        expect do
          tool.execute(arguments: { path: test_path }, _context: nil)
        end.not_to raise_error
      end
    end

    context "with parent directory creation" do
      it "creates parent directories automatically" do
        nested_path = File.join(test_dir, "deeply", "nested", "directory", "structure")
        expect(Dir.exist?(File.join(test_dir, "deeply"))).to be false

        result = tool.execute(arguments: { path: nested_path }, _context: nil)

        expect(result[:status]).to eq("success")
        expect(result[:created]).to be true
        expect(Dir.exist?(nested_path)).to be true
        expect(Dir.exist?(File.join(test_dir, "deeply", "nested"))).to be true
      end
    end

    context "with creation errors" do
      it "handles StandardError during directory creation" do
        allow(FileUtils).to receive(:mkdir_p).and_raise(StandardError.new("Permission denied"))

        result = tool.execute(arguments: { path: test_path }, _context: nil)

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Failed to create directory: Permission denied")
      end
    end

    context "successful creation" do
      it "creates directory and returns success" do
        expect(Dir.exist?(test_path)).to be false

        result = tool.execute(arguments: { path: test_path }, _context: nil)

        expect(result[:status]).to eq("success")
        expect(result[:path]).to eq(test_path)
        expect(result[:message]).to eq("Directory created successfully")
        expect(result[:created]).to be true
        expect(Dir.exist?(test_path)).to be true
      end
    end
  end
end
