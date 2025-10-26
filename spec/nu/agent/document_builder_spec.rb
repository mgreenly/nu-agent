# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::DocumentBuilder do
  describe "#initialize" do
    it "creates a new DocumentBuilder instance" do
      builder = described_class.new
      expect(builder).to be_a(Nu::Agent::DocumentBuilder)
    end
  end

  describe "#add_section" do
    it "adds a section with title and content" do
      builder = described_class.new
      builder.add_section("Context", "This is context information")

      result = builder.build
      expect(result).to include("# Context")
      expect(result).to include("This is context information")
    end

    it "adds multiple sections in order" do
      builder = described_class.new
      builder.add_section("Section 1", "Content 1")
      builder.add_section("Section 2", "Content 2")
      builder.add_section("Section 3", "Content 3")

      result = builder.build

      # Check sections appear in order
      section1_pos = result.index("# Section 1")
      section2_pos = result.index("# Section 2")
      section3_pos = result.index("# Section 3")

      expect(section1_pos).to be < section2_pos
      expect(section2_pos).to be < section3_pos
    end

    it "handles empty content gracefully" do
      builder = described_class.new
      builder.add_section("Empty Section", "")

      result = builder.build
      expect(result).to include("# Empty Section")
    end

    it "handles nil content gracefully" do
      builder = described_class.new
      builder.add_section("Nil Section", nil)

      result = builder.build
      expect(result).to include("# Nil Section")
    end

    it "preserves multiline content" do
      builder = described_class.new
      content = "Line 1\nLine 2\nLine 3"
      builder.add_section("Multiline", content)

      result = builder.build
      expect(result).to include(content)
    end
  end

  describe "#build" do
    it "returns an empty string when no sections added" do
      builder = described_class.new
      expect(builder.build).to eq("")
    end

    it "separates sections with blank lines" do
      builder = described_class.new
      builder.add_section("First", "Content 1")
      builder.add_section("Second", "Content 2")

      result = builder.build

      # Should have double newlines between sections
      expect(result).to match(/Content 1\n\n# Second/)
    end

    it "returns the same result when called multiple times" do
      builder = described_class.new
      builder.add_section("Test", "Content")

      result1 = builder.build
      result2 = builder.build

      expect(result1).to eq(result2)
    end
  end

  describe "complete document structure" do
    it "builds a document with RAG, tools, and user query sections" do
      builder = described_class.new

      builder.add_section("Context", "Previous conversation summary")
      builder.add_section("Available Tools", "file_read, file_write, execute_bash")
      builder.add_section("User Request", "Please help me with this task")

      result = builder.build

      # Check structure
      expect(result).to include("# Context")
      expect(result).to include("Previous conversation summary")
      expect(result).to include("# Available Tools")
      expect(result).to include("file_read, file_write, execute_bash")
      expect(result).to include("# User Request")
      expect(result).to include("Please help me with this task")
    end

    it "produces valid markdown" do
      builder = described_class.new

      builder.add_section("Header 1", "Some **bold** text\n\nAnd a list:\n- Item 1\n- Item 2")
      builder.add_section("Header 2", "`code block`")

      result = builder.build

      # Should contain valid markdown elements
      expect(result).to include("# Header 1")
      expect(result).to include("**bold**")
      expect(result).to include("- Item 1")
      expect(result).to include("`code block`")
    end
  end

  describe "edge cases" do
    it "handles special characters in titles" do
      builder = described_class.new
      builder.add_section('Title with "quotes" and <brackets>', "Content")

      result = builder.build
      expect(result).to include('Title with "quotes" and <brackets>')
    end

    it "handles special characters in content" do
      builder = described_class.new
      content = "SQL: SELECT * FROM table WHERE id = 'test'"
      builder.add_section("Database", content)

      result = builder.build
      expect(result).to include(content)
    end

    it "handles very long content" do
      builder = described_class.new
      long_content = "a" * 10_000
      builder.add_section("Long Section", long_content)

      result = builder.build
      expect(result).to include(long_content)
    end
  end
end
