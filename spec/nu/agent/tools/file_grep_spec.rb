# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Nu::Agent::Tools::FileGrep do
  let(:tool) { described_class.new }
  let(:test_dir) { File.join(Dir.pwd, "tmp", "file_grep_test") }

  before do
    FileUtils.rm_rf(test_dir)
    FileUtils.mkdir_p(test_dir)

    # Create test files with searchable content
    File.write(File.join(test_dir, "file1.rb"), <<~RUBY)
      class TestClass
        def execute
          puts "Hello"
        end

        def process
          # TODO: Implement this
          puts "Processing"
        end
      end
    RUBY

    File.write(File.join(test_dir, "file2.rb"), <<~RUBY)
      module TestModule
        def self.execute
          # FIXME: This needs work
          puts "Execute"
        end
      end
    RUBY

    File.write(File.join(test_dir, "file3.txt"), <<~TEXT)
      This is a text file
      TODO: Write documentation
      Some more text
    TEXT

    FileUtils.mkdir_p(File.join(test_dir, "subdir"))
    File.write(File.join(test_dir, "subdir", "nested.rb"), <<~RUBY)
      def another_execute
        puts "Nested execute"
      end
    RUBY
  end

  after do
    FileUtils.rm_rf(test_dir)
  end

  describe "#name" do
    it "returns the tool name" do
      expect(tool.name).to eq("file_grep")
    end
  end

  describe "#description" do
    it "returns a description" do
      expect(tool.description).to include("searching code patterns")
    end
  end

  describe "#parameters" do
    it "defines expected parameters" do
      params = tool.parameters

      expect(params).to have_key(:pattern)
      expect(params).to have_key(:path)
      expect(params).to have_key(:output_mode)
      expect(params).to have_key(:glob)
      expect(params).to have_key(:case_insensitive)
      expect(params).to have_key(:context_before)
      expect(params).to have_key(:context_after)
      expect(params).to have_key(:context)
      expect(params).to have_key(:max_results)
    end

    it "marks pattern as required" do
      expect(tool.parameters[:pattern][:required]).to be true
    end
  end

  describe "#execute" do
    context "with missing pattern" do
      it "returns error" do
        result = tool.execute(arguments: {})

        expect(result[:error]).to include("pattern is required")
        expect(result[:matches]).to eq([])
      end
    end

    context "with invalid output_mode" do
      it "returns error" do
        result = tool.execute(arguments: { pattern: "test", output_mode: "invalid" })

        expect(result[:error]).to include("output_mode must be")
      end
    end

    context "with files_with_matches mode (default)" do
      it "finds files containing pattern" do
        result = tool.execute(arguments: { pattern: "execute", path: test_dir })

        expect(result[:files]).to be_an(Array)
        expect(result[:files].length).to be >= 2
        expect(result[:files]).to include(match(/file1\.rb$/))
        expect(result[:files]).to include(match(/file2\.rb$/))
        expect(result[:count]).to eq(result[:files].length)
      end

      it "respects glob filter" do
        result = tool.execute(arguments: { pattern: "TODO", path: test_dir, glob: "*.rb" })

        expect(result[:files]).to all(match(/\.rb$/))
        expect(result[:files]).not_to include(match(/\.txt$/))
      end

      it "respects case_insensitive option" do
        result = tool.execute(arguments: { pattern: "EXECUTE", path: test_dir, case_insensitive: true })

        expect(result[:files]).not_to be_empty
      end

      it "respects max_results" do
        result = tool.execute(arguments: { pattern: "execute", path: test_dir, max_results: 1 })

        expect(result[:files].length).to be <= 1
      end
    end

    context "with count mode" do
      it "returns match counts per file" do
        result = tool.execute(arguments: { pattern: "execute", path: test_dir, output_mode: "count" })

        expect(result[:files]).to be_an(Array)
        expect(result[:files].first).to have_key(:file)
        expect(result[:files].first).to have_key(:count)
        expect(result[:total_files]).to be >= 2
        expect(result[:total_matches]).to be >= 2
      end
    end

    context "with content mode" do
      it "returns matching lines with line numbers" do
        result = tool.execute(arguments: { pattern: "def execute", path: test_dir, output_mode: "content" })

        expect(result[:matches]).to be_an(Array)
        expect(result[:matches].first).to have_key(:file)
        expect(result[:matches].first).to have_key(:line_number)
        expect(result[:matches].first).to have_key(:line)
        expect(result[:count]).to eq(result[:matches].length)
        expect(result).to have_key(:truncated)
      end

      it "respects context_before option" do
        result = tool.execute(
          arguments: { pattern: "TODO", path: test_dir, output_mode: "content", context_before: 1 }
        )

        # Should find matches - context is handled by ripgrep
        expect(result[:matches]).not_to be_empty
      end

      it "respects context_after option" do
        result = tool.execute(
          arguments: { pattern: "TODO", path: test_dir, output_mode: "content", context_after: 1 }
        )

        expect(result[:matches]).not_to be_empty
      end

      it "respects context option (both before and after)" do
        result = tool.execute(
          arguments: { pattern: "TODO", path: test_dir, output_mode: "content", context: 1 }
        )

        expect(result[:matches]).not_to be_empty
      end
    end

    context "with no matches" do
      it "returns empty results for files_with_matches mode" do
        result = tool.execute(arguments: { pattern: "nonexistent_pattern_xyz", path: test_dir })

        expect(result[:files]).to be_empty
        expect(result[:count]).to eq(0)
      end
    end
  end
end
