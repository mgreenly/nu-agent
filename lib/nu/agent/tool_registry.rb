# frozen_string_literal: true

module Nu
  module Agent
    class ToolRegistry
      def initialize
        @tools = {}
        register_default_tools
      end

      def register(tool)
        @tools[tool.name] = tool
      end

      def find(name)
        @tools[name]
      end

      def all
        @tools.values
      end

      def available
        @tools.values.select do |tool|
          # Include tools that don't have available? method, or have it and return true
          !tool.respond_to?(:available?) || tool.available?
        end
      end

      def execute(name:, arguments:, history:, context:)
        tool = find(name)
        raise Error, "Unknown tool: #{name}" unless tool

        tool.execute(arguments: arguments, history: history, context: context)
      end

      # Format tools for Anthropic API
      def for_anthropic
        available.map do |tool|
          {
            name: tool.name,
            description: tool.description,
            input_schema: parameters_to_schema(tool.parameters)
          }
        end
      end

      # Format tools for Google API
      def for_google
        available.map do |tool|
          {
            name: tool.name,
            description: tool.description,
            parameters: parameters_to_schema(tool.parameters)
          }
        end
      end

      # Format tools for OpenAI API
      def for_openai
        available.map do |tool|
          {
            type: "function",
            function: {
              name: tool.name,
              description: tool.description,
              parameters: parameters_to_schema(tool.parameters)
            }
          }
        end
      end

      private

      def register_default_tools
        default_tool_classes.each { |tool_class| register(tool_class.new) }
      end

      def default_tool_classes
        [
          Tools::AgentSummarizer,
          Tools::DatabaseMessage,
          Tools::DatabaseQuery,
          Tools::DatabaseSchema,
          Tools::DatabaseTables,
          Tools::DirCreate,
          Tools::DirDelete,
          Tools::DirList,
          Tools::DirTree,
          Tools::ExecuteBash,
          Tools::ExecutePython,
          Tools::FileCopy,
          Tools::FileDelete,
          Tools::FileEdit,
          Tools::FileGlob,
          Tools::FileGrep,
          Tools::FileMove,
          Tools::FileRead,
          Tools::FileStat,
          Tools::FileTree,
          Tools::FileWrite,
          Tools::SearchInternet
        ]
      end

      def parameters_to_schema(parameters)
        properties = {}
        required = []

        parameters.each do |name, config|
          properties[name] = {
            type: config[:type],
            description: config[:description]
          }
          required << name.to_s if config[:required]
        end

        {
          type: "object",
          properties: properties,
          required: required
        }
      end
    end
  end
end
