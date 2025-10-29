# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Nu::Agent::Tools::FileGlob do
  let(:tool) { described_class.new }
  let(:test_dir) { File.join(Dir.pwd, "tmp", "file_glob_test") }

  before do
    FileUtils.rm_rf(test_dir)
    FileUtils.mkdir_p(test_dir)

    # Create test files with different timestamps
    file1 = File.join(test_dir, "file1.rb")
    file2 = File.join(test_dir, "file2.txt")
    file3 = File.join(test_dir, "file3.rb")

    File.write(file1, "content1")
    File.write(file2, "content2")
    File.write(file3, "content3")

    # Ensure file3 has the most recent mtime
    FileUtils.touch(file3, mtime: Time.now)
    FileUtils.touch(file1, mtime: Time.now - 2)

    # Create nested directory structure
    FileUtils.mkdir_p(File.join(test_dir, "subdir"))
    File.write(File.join(test_dir, "subdir", "nested.rb"), "nested content")
  end

  after do
    FileUtils.rm_rf(test_dir)
  end

  describe "#name" do
    it "returns the tool name" do
      expect(tool.name).to eq("file_glob")
    end
  end

  describe "#description" do
    it "returns a description" do
      expect(tool.description).to include("PREFERRED tool for finding files")
      expect(tool.description).to include("Pattern examples")
    end
  end

  describe "#parameters" do
    it "defines expected parameters" do
      params = tool.parameters

      expect(params).to have_key(:pattern)
      expect(params).to have_key(:path)
      expect(params).to have_key(:limit)
      expect(params).to have_key(:sort_by)
    end

    it "marks pattern as required" do
      expect(tool.parameters[:pattern][:required]).to be true
    end

    it "marks other parameters as not required" do
      expect(tool.parameters[:path][:required]).to be false
      expect(tool.parameters[:limit][:required]).to be false
      expect(tool.parameters[:sort_by][:required]).to be false
    end
  end

  describe "#execute" do
    context "with missing pattern parameter" do
      it "returns error when pattern is nil" do
        result = tool.execute(arguments: {})

        expect(result[:error]).to eq("pattern is required")
        expect(result[:files]).to eq([])
      end

      it "returns error when pattern is empty string" do
        result = tool.execute(arguments: { pattern: "" })

        expect(result[:error]).to eq("pattern is required")
        expect(result[:files]).to eq([])
      end
    end

    context "with basic glob patterns" do
      it "finds files matching pattern" do
        result = tool.execute(arguments: { pattern: "*.rb", path: test_dir })

        expect(result[:files].length).to eq(2)
        expect(result[:files]).to include(match(/file1\.rb$/))
        expect(result[:files]).to include(match(/file3\.rb$/))
        expect(result[:count]).to eq(2)
        expect(result[:total_matches]).to eq(2)
        expect(result[:truncated]).to be false
      end

      it "finds files with recursive pattern" do
        result = tool.execute(arguments: { pattern: "**/*.rb", path: test_dir })

        expect(result[:files].length).to eq(3)
        expect(result[:files]).to include(match(/file1\.rb$/))
        expect(result[:files]).to include(match(/file3\.rb$/))
        expect(result[:files]).to include(match(/nested\.rb$/))
      end

      it "finds files with specific extension" do
        result = tool.execute(arguments: { pattern: "*.txt", path: test_dir })

        expect(result[:files].length).to eq(1)
        expect(result[:files].first).to match(/file2\.txt$/)
      end
    end

    context "with default parameters" do
      it "uses current directory as default path" do
        # Create test file in current directory
        test_file = "test_glob_file.rb"
        File.write(test_file, "test")

        result = tool.execute(arguments: { pattern: "test_glob_file.rb" })

        expect(result[:files].first).to match(/test_glob_file\.rb$/)

        # Clean up
        FileUtils.rm_f(test_file)
      end

      it "uses 100 as default limit" do
        result = tool.execute(arguments: { pattern: "*.rb", path: test_dir })

        # The result should not be truncated with only 2 files
        expect(result[:truncated]).to be false
      end

      it "uses mtime as default sort" do
        result = tool.execute(arguments: { pattern: "*.rb", path: test_dir })

        # file3.rb should be first (most recent)
        expect(result[:files].first).to match(/file3\.rb$/)
      end
    end

    context "with sorting options" do
      it "sorts by mtime (newest first) when sort_by is mtime" do
        result = tool.execute(arguments: { pattern: "*.rb", path: test_dir, sort_by: "mtime" })

        expect(result[:files].first).to match(/file3\.rb$/)
        expect(result[:files].last).to match(/file1\.rb$/)
      end

      it "sorts by name alphabetically when sort_by is name" do
        result = tool.execute(arguments: { pattern: "*.rb", path: test_dir, sort_by: "name" })

        expect(result[:files].first).to match(/file1\.rb$/)
        expect(result[:files].last).to match(/file3\.rb$/)
      end

      it "does not sort when sort_by is none" do
        result = tool.execute(arguments: { pattern: "*.rb", path: test_dir, sort_by: "none" })

        # Just verify we get results, order depends on filesystem
        expect(result[:files].length).to eq(2)
      end

      it "defaults to mtime for unknown sort_by values" do
        result = tool.execute(arguments: { pattern: "*.rb", path: test_dir, sort_by: "invalid" })

        # Should sort by mtime (most recent first)
        expect(result[:files].first).to match(/file3\.rb$/)
      end
    end

    context "with limit parameter" do
      it "limits results to specified number" do
        result = tool.execute(arguments: { pattern: "**/*.rb", path: test_dir, limit: 2 })

        expect(result[:files].length).to eq(2)
        expect(result[:count]).to eq(2)
        expect(result[:total_matches]).to eq(3)
        expect(result[:truncated]).to be true
      end

      it "does not truncate when results are within limit" do
        result = tool.execute(arguments: { pattern: "*.rb", path: test_dir, limit: 10 })

        expect(result[:files].length).to eq(2)
        expect(result[:truncated]).to be false
      end
    end

    context "with string keys in arguments" do
      it "accepts string keys for all parameters" do
        result = tool.execute(
          arguments: {
            "pattern" => "*.rb",
            "path" => test_dir,
            "limit" => 5,
            "sort_by" => "name"
          }
        )

        expect(result[:files].length).to eq(2)
        expect(result[:files].first).to match(/file1\.rb$/)
      end
    end

    context "with error conditions" do
      it "returns empty results for nonexistent path" do
        # Dir.glob doesn't raise an error for nonexistent paths, it just returns empty
        result = tool.execute(arguments: { pattern: "*.rb", path: "/nonexistent/path" })

        # Should return empty results without error
        expect(result[:files]).to eq([])
        expect(result[:count]).to eq(0)
      end

      it "handles StandardError during glob" do
        allow(Dir).to receive(:glob).and_raise(StandardError.new("Some glob error"))

        result = tool.execute(arguments: { pattern: "*.rb", path: test_dir })

        expect(result[:error]).to include("Glob failed: Some glob error")
        expect(result[:files]).to eq([])
      end

      it "handles Errno::ENOENT when accessing file stats" do
        # Mock File.mtime to raise Errno::ENOENT
        allow(Dir).to receive(:glob).and_raise(Errno::ENOENT.new("No such file"))

        result = tool.execute(arguments: { pattern: "*.rb", path: test_dir })

        expect(result[:error]).to include("Path not found")
        expect(result[:files]).to eq([])
      end
    end

    context "when glob matches directories" do
      it "filters out directories and returns only files" do
        # Create a directory that might match the pattern
        FileUtils.mkdir_p(File.join(test_dir, "subdir.rb"))

        result = tool.execute(arguments: { pattern: "**/*.rb", path: test_dir })

        # Should only include actual files, not directories
        result[:files].each do |file|
          expect(File.file?(file)).to be true
        end
      end
    end
  end
end
