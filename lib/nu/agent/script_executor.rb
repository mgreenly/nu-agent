# frozen_string_literal: true

require_relative "debug"

module Nu
  module Agent
    class ScriptExecutor
      def self.script?(text)
        text.strip.start_with?('```sh') && text.strip.end_with?('```')
      end

      def self.execute(text, debug: false)
        Debug.log("Script detected")
        Debug.log_multiline("Script content:", text)

        script_content = extract_script(text)
        script_path = create_script_file(script_content)
        Debug.log("Created script at: #{script_path}")

        begin
          output = run_script(script_path)
          Debug.log_multiline("Script output:", output)
          output
        ensure
          File.unlink(script_path) if File.exist?(script_path)
          Debug.log("Cleaned up script file")
        end
      end

      private

      def self.extract_script(text)
        lines = text.strip.lines
        lines[1...-1].join
      end

      def self.create_script_file(content)
        script_path = File.join(Dir.pwd, "script#{Process.pid}-#{Time.now.to_i}")
        File.write(script_path, content)
        File.chmod(0755, script_path)
        script_path
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
