# frozen_string_literal: true

require "spec_helper"
require "nu/agent/tools_display_formatter"

RSpec.describe Nu::Agent::ToolsDisplayFormatter do
  describe ".build" do
    let(:tool1) do
      double("tool1",
             name: "file_read",
             description: "Reads the content of a file. Works with relative or absolute paths.")
    end

    let(:tool2) do
      double("tool2",
             name: "execute_bash",
             description: "Executes bash commands in a shell environment",
             available?: true)
    end

    let(:tool3) do
      double("tool3",
             name: "search_internet",
             description: "Searches the internet for information",
             available?: false)
    end

    let(:tool_registry) { double("tool_registry", all: [tool1, tool2, tool3]) }

    before do
      allow(Nu::Agent::ToolRegistry).to receive(:new).and_return(tool_registry)
    end

    it "returns formatted tools list with header" do
      tools_text = described_class.build

      expect(tools_text).to include("Available Tools:")
    end

    it "includes tool names and descriptions" do
      tools_text = described_class.build

      expect(tools_text).to include("file_read")
      expect(tools_text).to include("Reads the content of a file.")
      expect(tools_text).to include("execute_bash")
      expect(tools_text).to include("Executes bash commands")
    end

    it "extracts first sentence from descriptions" do
      tools_text = described_class.build

      expect(tools_text).to include("Reads the content of a file.")
      expect(tools_text).not_to include("Works with relative or absolute paths")
    end

    it "marks unavailable tools as disabled" do
      tools_text = described_class.build

      expect(tools_text).to include("search_internet")
      expect(tools_text).to include("(disabled)")
    end

    it "does not mark available tools as disabled" do
      tools_text = described_class.build

      lines = tools_text.lines
      bash_line = lines.find { |l| l.include?("execute_bash") }
      expect(bash_line).not_to include("(disabled)")
    end

    it "returns multi-line text" do
      tools_text = described_class.build
      lines = tools_text.lines

      expect(lines.size).to be >= 4
    end
  end
end
