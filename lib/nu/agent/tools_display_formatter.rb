# frozen_string_literal: true

module Nu
  module Agent
    # Formats available tools for display
    class ToolsDisplayFormatter
      def self.build
        tool_registry = ToolRegistry.new
        lines = []
        lines << ""
        lines << "Available Tools:"

        tool_registry.all.each do |tool|
          # Get first sentence of description
          desc = tool.description.split(/\.\s+/).first || tool.description
          desc = desc.strip
          desc += "." unless desc.end_with?(".")

          # Check if tool has credentials (if applicable)
          desc += " (disabled)" if tool.respond_to?(:available?) && !tool.available?

          lines << "  #{tool.name.ljust(25)} - #{desc}"
        end

        lines.join("\n")
      end
    end
  end
end
