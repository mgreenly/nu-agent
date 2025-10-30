# frozen_string_literal: true

require "tempfile"

module Nu
  module Agent
    # Handles editing personas in an external text editor
    class PersonaEditor
      # Custom error for editor failures
      class EditorError < StandardError; end

      # Opens an external editor to edit persona content
      #
      # @param initial_content [String] the starting content to populate the editor
      # @param persona_name [String] the name of the persona being edited
      # @return [String, nil] the edited content, or nil if empty/cancelled
      def edit_in_editor(initial_content: "", persona_name: nil)
        temp_file = create_temp_file(persona_name, initial_content)

        begin
          open_editor(temp_file.path)
          content = read_edited_content(temp_file)
          validate_content(content)
        ensure
          cleanup_temp_file(temp_file)
        end
      end

      private

      def create_temp_file(persona_name, initial_content)
        temp_file = Tempfile.new(["nu-agent-persona-#{persona_name}-", ".txt"])
        temp_file.write(initial_content)
        temp_file.rewind
        temp_file
      end

      def open_editor(file_path)
        editor = ENV["EDITOR"] || "vi"
        result = system("#{editor} #{file_path}")

        raise EditorError, "Editor failed or was cancelled" unless result
      end

      def read_edited_content(temp_file)
        temp_file.rewind
        temp_file.read
      end

      def validate_content(content)
        stripped = content.strip
        return nil if stripped.empty?

        stripped
      end

      def cleanup_temp_file(temp_file)
        temp_file.close
        temp_file.unlink
      end
    end
  end
end
