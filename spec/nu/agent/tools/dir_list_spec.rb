# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe Nu::Agent::Tools::DirList do
  let(:tool) { described_class.new }
  let(:test_dir) { File.join(Dir.pwd, "tmp", "dir_list_test") }

  before do
    FileUtils.rm_rf(test_dir)
    FileUtils.mkdir_p(test_dir)

    # Create test structure
    FileUtils.touch(File.join(test_dir, "file1.txt"))
    FileUtils.touch(File.join(test_dir, "file2.rb"))
    FileUtils.touch(File.join(test_dir, ".hidden"))
    FileUtils.mkdir_p(File.join(test_dir, "subdir"))
  end

  after do
    FileUtils.rm_rf(test_dir)
  end

  describe "#name" do
    it "returns the tool name" do
      expect(tool.name).to eq("dir_list")
    end
  end

  describe "#description" do
    it "returns a description" do
      expect(tool.description).to include("listing directory contents")
    end
  end

  describe "#parameters" do
    it "defines expected parameters" do
      params = tool.parameters

      expect(params).to have_key(:path)
      expect(params).to have_key(:show_hidden)
      expect(params).to have_key(:details)
      expect(params).to have_key(:sort_by)
      expect(params).to have_key(:limit)
    end
  end

  describe "#execute" do
    context "with valid directory" do
      it "lists directory entries" do
        result = tool.execute(arguments: { path: test_dir })

        expect(result[:status]).to eq("success")
        expect(result[:entries]).to include("file1.txt", "file2.rb", "subdir")
        expect(result[:entries]).not_to include(".hidden")
      end

      it "shows hidden files when requested" do
        result = tool.execute(arguments: { path: test_dir, show_hidden: true })

        expect(result[:entries]).to include(".hidden")
      end

      it "includes details when requested" do
        result = tool.execute(arguments: { path: test_dir, details: true })

        entry = result[:entries].first
        expect(entry).to have_key(:name)
        expect(entry).to have_key(:type)
        expect(entry).to have_key(:size)
        expect(entry).to have_key(:modified_at)
      end

      it "limits results" do
        result = tool.execute(arguments: { path: test_dir, limit: 2 })

        expect(result[:entries].length).to eq(2)
        expect(result[:truncated]).to be true
      end
    end

    context "with non-existent path" do
      it "returns error" do
        result = tool.execute(arguments: { path: "tmp/nonexistent/path" })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("not found")
      end
    end

    context "with file path" do
      it "returns error" do
        file_path = File.join(test_dir, "file1.txt")
        result = tool.execute(arguments: { path: file_path })

        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Not a directory")
      end
    end

    context "with path outside project" do
      it "raises error" do
        expect do
          tool.execute(arguments: { path: "/etc" })
        end.to raise_error(ArgumentError, /Access denied/)
      end
    end
  end
end
