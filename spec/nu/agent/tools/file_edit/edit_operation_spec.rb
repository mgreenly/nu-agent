# frozen_string_literal: true

require "spec_helper"
require "nu/agent/tools/file_edit/edit_operation"

RSpec.describe Nu::Agent::Tools::FileEdit::EditOperation do
  describe "#execute" do
    it "raises NotImplementedError when not overridden" do
      operation = described_class.new
      expect { operation.execute("/some/path", {}) }.to raise_error(NotImplementedError)
    end
  end

  describe "#validate_path" do
    let(:operation) { described_class.new }
    let(:project_root) { "/home/claude/projects/nu-agent" }

    before do
      allow(Dir).to receive(:pwd).and_return(project_root)
    end

    it "accepts paths within project directory" do
      valid_path = "#{project_root}/test.txt"
      expect { operation.validate_path(valid_path) }.not_to raise_error
    end

    it "rejects paths outside project directory" do
      invalid_path = "/etc/passwd"
      expect { operation.validate_path(invalid_path) }.to raise_error(
        ArgumentError,
        /Access denied: File must be within project directory/
      )
    end

    it "rejects paths with directory traversal" do
      traversal_path = "#{project_root}/../other-project/file.txt"
      expect { operation.validate_path(traversal_path) }.to raise_error(
        ArgumentError,
        /Access denied: Path cannot contain '\.\.'/
      )
    end
  end

  describe "#resolve_path" do
    let(:operation) { described_class.new }

    before do
      allow(Dir).to receive(:pwd).and_return("/home/claude/projects/nu-agent")
    end

    it "expands absolute paths" do
      result = operation.resolve_path("/tmp/test.txt")
      expect(result).to eq("/tmp/test.txt")
    end

    it "expands relative paths from current directory" do
      result = operation.resolve_path("test.txt")
      expect(result).to eq("/home/claude/projects/nu-agent/test.txt")
    end
  end
end
