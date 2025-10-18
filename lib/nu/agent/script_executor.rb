# frozen_string_literal: true

module Nu
  module Agent
    class ScriptExecutor
      def self.script?(text)
        text.strip.start_with?('```script') && text.strip.end_with?('```')
      end

      def self.execute(text, debug: false)
        puts "[DEBUG] Script detected" if debug

        script_content = extract_script(text)
        puts "[DEBUG] Extracted script content:\n#{script_content}" if debug

        tmpfile = create_tmpfile(script_content)
        puts "[DEBUG] Created tmpfile at: #{tmpfile.path}" if debug

        begin
          output = run_script(tmpfile.path)
          puts "[DEBUG] Script output:\n#{output}" if debug
          output
        ensure
          tmpfile.close
          tmpfile.unlink
          puts "[DEBUG] Cleaned up tmpfile" if debug
        end
      end

      private

      def self.extract_script(text)
        lines = text.strip.lines
        lines[1...-1].join
      end

      def self.create_tmpfile(content)
        tmpfile = Tempfile.new(['script', ''])
        tmpfile.write(content)
        tmpfile.flush
        tmpfile.chmod(0755)
        tmpfile
      end

      def self.run_script(path)
        output, status = Open3.capture2e(path)
        output
      rescue => e
        "Error executing script: #{e.message}"
      end
    end
  end
end
