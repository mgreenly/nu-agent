# frozen_string_literal: true

module Nu
  module Agent
    class ScriptExecutor
      def self.script?(text)
        text.strip.start_with?('```script') && text.strip.end_with?('```')
      end

      def self.execute(text)
        script_content = extract_script(text)
        tmpfile = create_tmpfile(script_content)

        begin
          run_script(tmpfile.path)
        ensure
          tmpfile.close
          tmpfile.unlink
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
