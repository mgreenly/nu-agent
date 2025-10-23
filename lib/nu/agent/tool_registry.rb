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

      def execute(name:, arguments:, history:, context:)
        tool = find(name)
        raise Error, "Unknown tool: #{name}" unless tool

        tool.execute(arguments: arguments, history: history, context: context)
      end

      # Format tools for Anthropic API
      def for_anthropic
        all.map do |tool|
          {
            name: tool.name,
            description: tool.description,
            input_schema: parameters_to_schema(tool.parameters)
          }
        end
      end

      # Format tools for Google API
      def for_google
        all.map do |tool|
          {
            name: tool.name,
            description: tool.description,
            parameters: parameters_to_schema(tool.parameters)
          }
        end
      end

      # Format tools for OpenAI API
      def for_openai
        all.map do |tool|
          {
            type: 'function',
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
        register(Tools::AgentSummarizer.new)
        register(Tools::DatabaseMessage.new)
        register(Tools::DatabaseQuery.new)
        register(Tools::DatabaseSchema.new)
        register(Tools::DatabaseTables.new)
        register(Tools::DirCreate.new)
        register(Tools::DirDelete.new)
        register(Tools::DirList.new)
        register(Tools::ExecuteBash.new)
        register(Tools::ExecutePython.new)
        register(Tools::FileCopy.new)
        register(Tools::FileDelete.new)
        register(Tools::FileEdit.new)
        register(Tools::FileGlob.new)
        register(Tools::FileGrep.new)
        register(Tools::FileMove.new)
        register(Tools::FileRead.new)
        register(Tools::FileStat.new)
        register(Tools::FileWrite.new)
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
