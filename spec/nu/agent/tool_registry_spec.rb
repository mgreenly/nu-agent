# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::ToolRegistry do
  let(:registry) { described_class.new }

  # Mock tool classes
  let(:mock_tool) do
    double("MockTool",
           name: "mock_tool",
           description: "A mock tool",
           parameters: {
             arg1: { type: "string", description: "First argument", required: true },
             arg2: { type: "integer", description: "Second argument", required: false }
           })
  end

  let(:unavailable_tool) do
    double("UnavailableTool",
           name: "unavailable_tool",
           description: "An unavailable tool",
           parameters: {},
           available?: false)
  end

  let(:available_tool) do
    double("AvailableTool",
           name: "available_tool",
           description: "An available tool",
           parameters: {},
           available?: true)
  end

  describe "#initialize" do
    it "initializes with an empty tools hash" do
      expect(registry.instance_variable_get(:@tools)).to be_a(Hash)
    end

    it "registers default tools" do
      # Should have all the default tools
      expect(registry.all.length).to be > 0
    end
  end

  describe "#register" do
    it "registers a tool by name" do
      registry.register(mock_tool)

      expect(registry.find("mock_tool")).to eq(mock_tool)
    end

    it "allows registering multiple tools" do
      tool1 = double("Tool1", name: "tool1")
      tool2 = double("Tool2", name: "tool2")

      registry.register(tool1)
      registry.register(tool2)

      expect(registry.find("tool1")).to eq(tool1)
      expect(registry.find("tool2")).to eq(tool2)
    end
  end

  describe "#find" do
    before do
      registry.register(mock_tool)
    end

    it "finds a registered tool by name" do
      expect(registry.find("mock_tool")).to eq(mock_tool)
    end

    it "returns nil for unknown tools" do
      expect(registry.find("unknown_tool")).to be_nil
    end
  end

  describe "#all" do
    it "returns all registered tools" do
      # Clear default tools for this test
      registry.instance_variable_set(:@tools, {})

      tool1 = double("Tool1", name: "tool1")
      tool2 = double("Tool2", name: "tool2")

      registry.register(tool1)
      registry.register(tool2)

      expect(registry.all).to contain_exactly(tool1, tool2)
    end
  end

  describe "#available" do
    before do
      # Clear default tools
      registry.instance_variable_set(:@tools, {})
    end

    it "includes tools without available? method" do
      registry.register(mock_tool)

      expect(registry.available).to include(mock_tool)
    end

    it "includes tools with available? returning true" do
      registry.register(available_tool)

      expect(registry.available).to include(available_tool)
    end

    it "excludes tools with available? returning false" do
      registry.register(unavailable_tool)

      expect(registry.available).not_to include(unavailable_tool)
    end

    it "filters mixed availability correctly" do
      registry.register(mock_tool)
      registry.register(available_tool)
      registry.register(unavailable_tool)

      available = registry.available

      expect(available).to include(mock_tool)
      expect(available).to include(available_tool)
      expect(available).not_to include(unavailable_tool)
    end
  end

  describe "#execute" do
    let(:history) { double("History") }
    let(:context) { { "key" => "value" } }
    let(:arguments) { { arg: "value" } }
    let(:result) { { status: "success" } }

    before do
      allow(mock_tool).to receive(:execute).and_return(result)
      registry.register(mock_tool)
    end

    it "executes a registered tool" do
      expect(mock_tool).to receive(:execute).with(
        arguments: arguments,
        history: history,
        context: context
      )

      registry.execute(name: "mock_tool", arguments: arguments, history: history, context: context)
    end

    it "returns the tool's execution result" do
      result = registry.execute(name: "mock_tool", arguments: arguments, history: history, context: context)

      expect(result).to eq({ status: "success" })
    end

    it "raises error for unknown tool" do
      expect do
        registry.execute(name: "unknown_tool", arguments: arguments, history: history, context: context)
      end.to raise_error(Nu::Agent::Error, "Unknown tool: unknown_tool")
    end
  end

  describe "#for_anthropic" do
    before do
      registry.instance_variable_set(:@tools, {})
      registry.register(mock_tool)
    end

    it "formats tools for Anthropic API" do
      result = registry.for_anthropic

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)

      tool_def = result.first
      expect(tool_def[:name]).to eq("mock_tool")
      expect(tool_def[:description]).to eq("A mock tool")
      expect(tool_def[:input_schema]).to be_a(Hash)
      expect(tool_def[:input_schema][:type]).to eq("object")
      expect(tool_def[:input_schema][:properties]).to have_key(:arg1)
      expect(tool_def[:input_schema][:required]).to eq(["arg1"])
    end

    it "only includes available tools" do
      registry.register(unavailable_tool)

      result = registry.for_anthropic

      expect(result.length).to eq(1)
      expect(result.first[:name]).to eq("mock_tool")
    end
  end

  describe "#for_google" do
    before do
      registry.instance_variable_set(:@tools, {})
      registry.register(mock_tool)
    end

    it "formats tools for Google API" do
      result = registry.for_google

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)

      tool_def = result.first
      expect(tool_def[:name]).to eq("mock_tool")
      expect(tool_def[:description]).to eq("A mock tool")
      expect(tool_def[:parameters]).to be_a(Hash)
      expect(tool_def[:parameters][:type]).to eq("object")
      expect(tool_def[:parameters][:properties]).to have_key(:arg1)
      expect(tool_def[:parameters][:required]).to eq(["arg1"])
    end

    it "only includes available tools" do
      registry.register(unavailable_tool)

      result = registry.for_google

      expect(result.length).to eq(1)
      expect(result.first[:name]).to eq("mock_tool")
    end
  end

  describe "#for_openai" do
    before do
      registry.instance_variable_set(:@tools, {})
      registry.register(mock_tool)
    end

    it "formats tools for OpenAI API" do
      result = registry.for_openai

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)

      tool_def = result.first
      expect(tool_def[:type]).to eq("function")
      expect(tool_def[:function][:name]).to eq("mock_tool")
      expect(tool_def[:function][:description]).to eq("A mock tool")
      expect(tool_def[:function][:parameters]).to be_a(Hash)
      expect(tool_def[:function][:parameters][:type]).to eq("object")
      expect(tool_def[:function][:parameters][:properties]).to have_key(:arg1)
      expect(tool_def[:function][:parameters][:required]).to eq(["arg1"])
    end

    it "only includes available tools" do
      registry.register(unavailable_tool)

      result = registry.for_openai

      expect(result.length).to eq(1)
      expect(result.first[:function][:name]).to eq("mock_tool")
    end
  end

  describe "#parameters_to_schema" do
    it "converts parameters to JSON schema format" do
      parameters = {
        name: { type: "string", description: "Name parameter", required: true },
        count: { type: "integer", description: "Count parameter", required: false },
        enabled: { type: "boolean", description: "Enabled flag", required: true }
      }

      schema = registry.send(:parameters_to_schema, parameters)

      expect(schema[:type]).to eq("object")
      expect(schema[:properties][:name][:type]).to eq("string")
      expect(schema[:properties][:name][:description]).to eq("Name parameter")
      expect(schema[:properties][:count][:type]).to eq("integer")
      expect(schema[:properties][:count][:description]).to eq("Count parameter")
      expect(schema[:properties][:enabled][:type]).to eq("boolean")
      expect(schema[:required]).to contain_exactly("name", "enabled")
    end

    it "handles empty parameters" do
      schema = registry.send(:parameters_to_schema, {})

      expect(schema[:type]).to eq("object")
      expect(schema[:properties]).to eq({})
      expect(schema[:required]).to eq([])
    end

    it "converts symbol keys to strings for required array" do
      parameters = {
        test: { type: "string", description: "Test", required: true }
      }

      schema = registry.send(:parameters_to_schema, parameters)

      expect(schema[:required]).to eq(["test"])
    end
  end
end
