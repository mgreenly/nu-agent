# frozen_string_literal: true

module Nu
  module Agent
    class OutputBuffer
      def initialize
        @lines = []
      end

      def add(text, type: :normal)
        # IMPORTANT: Never add text with embedded newlines
        # Each call to add() should add exactly ONE line
        text_str = text.to_s

        if text_str.include?("\n")
          # Auto-split on newlines and add each line separately
          # Apply normalize_lines logic: trim leading/trailing blanks, collapse consecutive blanks
          lines = text_str.lines.map(&:chomp)

          # Trim leading and trailing blank lines
          lines = lines.drop_while(&:empty?).reverse.drop_while(&:empty?).reverse

          # Collapse consecutive blank lines
          prev_empty = false
          lines.each do |line|
            if line.empty?
              @lines << { text: line, type: type } unless prev_empty
              prev_empty = true
            else
              @lines << { text: line, type: type }
              prev_empty = false
            end
          end
        else
          # Store line with its type (normal, debug, error)
          @lines << { text: text_str, type: type }
        end
      end

      def debug(text)
        add(text, type: :debug)
      end

      def error(text)
        add(text, type: :error)
      end

      def empty?
        @lines.empty?
      end

      def lines
        @lines
      end

      def clear
        @lines.clear
      end
    end
  end
end
