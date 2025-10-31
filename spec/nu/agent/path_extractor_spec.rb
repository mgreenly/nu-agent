# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::PathExtractor do
  let(:extractor) { described_class.new }

  describe "#extract" do
    context "with file_read tool" do
      it "extracts file path from arguments" do
        arguments = { file: "/path/to/file.rb" }
        result = extractor.extract("file_read", arguments)

        expect(result).to eq(["/path/to/file.rb"])
      end

      it "handles string keys" do
        arguments = { "file" => "/path/to/file.rb" }
        result = extractor.extract("file_read", arguments)

        expect(result).to eq(["/path/to/file.rb"])
      end
    end

    context "with file_write tool" do
      it "extracts file path from arguments" do
        arguments = { file: "/path/to/file.rb", content: "hello" }
        result = extractor.extract("file_write", arguments)

        expect(result).to eq(["/path/to/file.rb"])
      end
    end

    context "with file_copy tool" do
      it "extracts both source and destination paths" do
        arguments = { source: "/path/to/source.rb", destination: "/path/to/dest.rb" }
        result = extractor.extract("file_copy", arguments)

        expect(result).to contain_exactly("/path/to/source.rb", "/path/to/dest.rb")
      end
    end

    context "with file_move tool" do
      it "extracts both source and destination paths" do
        arguments = { source: "/path/to/source.rb", destination: "/path/to/dest.rb" }
        result = extractor.extract("file_move", arguments)

        expect(result).to contain_exactly("/path/to/source.rb", "/path/to/dest.rb")
      end
    end

    context "with file_edit tool" do
      it "extracts file path from arguments" do
        arguments = { file: "/path/to/file.rb", old_text: "foo", new_text: "bar" }
        result = extractor.extract("file_edit", arguments)

        expect(result).to eq(["/path/to/file.rb"])
      end
    end

    context "with file_delete tool" do
      it "extracts file path from arguments" do
        arguments = { file: "/path/to/file.rb" }
        result = extractor.extract("file_delete", arguments)

        expect(result).to eq(["/path/to/file.rb"])
      end
    end

    context "with dir_list tool" do
      it "extracts directory path from arguments" do
        arguments = { path: "/path/to/dir" }
        result = extractor.extract("dir_list", arguments)

        expect(result).to eq(["/path/to/dir"])
      end
    end

    context "with dir_create tool" do
      it "extracts directory path from arguments" do
        arguments = { path: "/path/to/dir" }
        result = extractor.extract("dir_create", arguments)

        expect(result).to eq(["/path/to/dir"])
      end
    end

    context "with dir_delete tool" do
      it "extracts directory path from arguments" do
        arguments = { path: "/path/to/dir" }
        result = extractor.extract("dir_delete", arguments)

        expect(result).to eq(["/path/to/dir"])
      end
    end

    context "with execute_bash tool (unconfined)" do
      it "returns nil for unconfined tools" do
        arguments = { command: "ls -la" }
        result = extractor.extract("execute_bash", arguments)

        expect(result).to be_nil
      end
    end

    context "with execute_python tool (unconfined)" do
      it "returns nil for unconfined tools" do
        arguments = { code: "print('hello')" }
        result = extractor.extract("execute_python", arguments)

        expect(result).to be_nil
      end
    end

    context "with database_query tool (different resource type)" do
      it "returns nil for non-file resource tools" do
        arguments = { query: "SELECT * FROM users" }
        result = extractor.extract("database_query", arguments)

        expect(result).to be_nil
      end
    end

    context "with missing arguments" do
      it "returns empty array when arguments are nil" do
        result = extractor.extract("file_read", nil)

        expect(result).to eq([])
      end

      it "returns empty array when arguments are empty" do
        result = extractor.extract("file_read", {})

        expect(result).to eq([])
      end

      it "returns empty array when required path parameter is missing" do
        arguments = { content: "hello" }
        result = extractor.extract("file_write", arguments)

        expect(result).to eq([])
      end
    end

    context "with unknown tool" do
      it "returns nil for unknown tools" do
        arguments = { foo: "bar" }
        result = extractor.extract("unknown_tool", arguments)

        expect(result).to be_nil
      end
    end
  end
end
