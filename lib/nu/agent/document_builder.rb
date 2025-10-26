# frozen_string_literal: true

module Nu
  module Agent
    class DocumentBuilder
      def initialize
        @sections = []
      end

      def add_section(title, content)
        @sections << { title: title, content: content }
      end

      def build
        return "" if @sections.empty?

        @sections.map.with_index do |section, index|
          section_text = "# #{section[:title]}\n"

          # Add content if present
          section_text += section[:content].to_s if section[:content] && !section[:content].to_s.empty?

          # Add blank line after section (except for the last one)
          section_text += "\n" unless index == @sections.length - 1

          section_text
        end.join("\n")
      end
    end
  end
end
