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

    context "with sorting options" do
      before do
        # Create files with different sizes and mtimes
        File.write(File.join(test_dir, "large.txt"), "x" * 1000)
        File.write(File.join(test_dir, "small.txt"), "x")
        sleep(0.01)
        FileUtils.touch(File.join(test_dir, "newer.txt"))
      end

      it "sorts by mtime without details" do
        result = tool.execute(arguments: { path: test_dir, sort_by: "mtime" })
        expect(result[:status]).to eq("success")
        expect(result[:entries]).to be_an(Array)
      end

      it "sorts by mtime with details" do
        result = tool.execute(arguments: { path: test_dir, sort_by: "mtime", details: true })
        expect(result[:status]).to eq("success")
        expect(result[:entries].first).to have_key(:modified_at)
      end

      it "sorts by size without details" do
        result = tool.execute(arguments: { path: test_dir, sort_by: "size" })
        expect(result[:status]).to eq("success")
        expect(result[:entries]).to be_an(Array)
      end

      it "sorts by size with details" do
        result = tool.execute(arguments: { path: test_dir, sort_by: "size", details: true })
        expect(result[:status]).to eq("success")
        entries = result[:entries]
        expect(entries.first[:size]).to be >= entries.last[:size]
      end

      it "does not sort when sort_by is none" do
        result = tool.execute(arguments: { path: test_dir, sort_by: "none" })
        expect(result[:status]).to eq("success")
        expect(result[:entries]).to be_an(Array)
      end
    end

    context "with symlinks" do
      before do
        target_file = File.join(test_dir, "target.txt")
        FileUtils.touch(target_file)
        File.symlink(target_file, File.join(test_dir, "link.txt"))
      end

      it "detects symlink type with details" do
        result = tool.execute(arguments: { path: test_dir, details: true })
        symlink_entry = result[:entries].find { |e| e[:name] == "link.txt" }
        expect(symlink_entry[:type]).to eq("symlink")
      end
    end

    context "with broken symlink" do
      before do
        broken_link = File.join(test_dir, "broken.txt")
        File.symlink("/nonexistent/target", broken_link)
      end

      it "handles broken symlink with unknown type" do
        result = tool.execute(arguments: { path: test_dir, details: true })
        broken_entry = result[:entries].find { |e| e[:name] == "broken.txt" }
        expect(broken_entry[:type]).to eq("unknown")
        expect(broken_entry[:size]).to eq(0)
        expect(broken_entry[:modified_at]).to be_nil
      end
    end

    context "with special file types" do
      it "detects other file type for named pipe" do
        pipe_path = File.join(test_dir, "mypipe")
        begin
          require "fileutils"
          system("mkfifo", pipe_path)
          skip "mkfifo not available" unless File.exist?(pipe_path)

          result = tool.execute(arguments: { path: test_dir, details: true })
          pipe_entry = result[:entries].find { |e| e[:name] == "mypipe" }
          expect(pipe_entry[:type]).to eq("other")
        ensure
          FileUtils.rm_f(pipe_path)
        end
      end
    end

    context "with StandardError during execution" do
      it "catches and returns error" do
        allow(File).to receive(:directory?).and_raise(StandardError.new("Simulated error"))
        result = tool.execute(arguments: { path: test_dir })
        expect(result[:status]).to eq("error")
        expect(result[:error]).to include("Failed to list directory")
      end
    end

    context "with path containing .." do
      it "raises error for path traversal attempt" do
        # Mock resolve_path to return a path with .. to test the validation
        allow(tool).to receive(:resolve_path).and_return("#{Dir.pwd}/tmp/../etc")

        expect do
          tool.execute(arguments: { path: "some_path" })
        end.to raise_error(ArgumentError, /Path cannot contain/)
      end
    end

    context "with sorting when file does not exist" do
      before do
        # Create files with known names
        File.write(File.join(test_dir, "file1.txt"), "content")
        File.write(File.join(test_dir, "file2.txt"), "content")
      end

      it "handles missing file during mtime sort" do
        # Mock File.exist? to return false for one specific file during sorting
        # This simulates a file being deleted between listing and sorting
        file1_path = File.join(test_dir, "file1.txt")
        allow(File).to receive(:exist?).and_wrap_original do |original, path|
          # Return false only for file1.txt to trigger the else branch
          if path == file1_path
            false
          else
            original.call(path)
          end
        end

        result = tool.execute(arguments: { path: test_dir, sort_by: "mtime" })
        expect(result[:status]).to eq("success")
        expect(result[:entries]).to be_an(Array)
      end

      it "handles missing file during size sort" do
        # Mock File.exist? to return false for one specific file during sorting
        # This simulates a file being deleted between listing and sorting
        file1_path = File.join(test_dir, "file1.txt")
        allow(File).to receive(:exist?).and_wrap_original do |original, path|
          # Return false only for file1.txt to trigger the else branch
          if path == file1_path
            false
          else
            original.call(path)
          end
        end

        result = tool.execute(arguments: { path: test_dir, sort_by: "size" })
        expect(result[:status]).to eq("success")
        expect(result[:entries]).to be_an(Array)
      end
    end
  end
end
