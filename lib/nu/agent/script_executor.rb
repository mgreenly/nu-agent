# frozen_string_literal: true

module Nu
  module Agent
    class ScriptExecutor
      def self.script?(text)
        text.strip.start_with?('```sh') && text.strip.end_with?('```')
      end

      def self.execute(text, debug: false)
        puts "[DEBUG] Script detected" if debug

        script_content = extract_script(text)
        puts "[DEBUG] Extracted script content:\n#{script_content}" if debug

        script_path = create_script_file(script_content)
        puts "[DEBUG] Created script at: #{script_path}" if debug

        begin
          output = run_script(script_path)
          puts "[DEBUG] Script output:\n#{output}" if debug
          output
        ensure
          File.unlink(script_path) if File.exist?(script_path)
          puts "[DEBUG] Cleaned up script file" if debug
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
