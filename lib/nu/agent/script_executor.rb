# frozen_string_literal: true

module Nu
  module Agent
    class ScriptExecutor
      def self.script?(text)
        text.strip.start_with?('```sh') && text.strip.end_with?('```')
      end

      def self.execute(text, debug: false)
        if debug
          puts "[DEBUG] Script detected"
          print_debug_script(text)
        end

        script_content = extract_script(text)
        script_path = create_script_file(script_content)
        puts "[DEBUG] Created script at: #{script_path}" if debug

        begin
          output = run_script(script_path)
          print_debug_output(output) if debug
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

      def self.print_debug_script(text)
        text.strip.lines.each do |line|
          puts "[DEBUG] #{line.chomp}"
        end
      end

      def self.print_debug_output(output)
        puts "[DEBUG] Script output:"
        output.lines.each do |line|
          puts "[DEBUG] #{line.chomp}"
        end
      end
    end
  end
end
