# frozen_string_literal: true

require 'open3'

module Nu
  module Agent
    module Tools
      class ExecuteBash
        def name
          "execute_bash"
        end

        def available?
          system('which bwrap > /dev/null 2>&1')
        end

        def description
          "PREFERRED tool for executing bash commands in a secure sandbox. " \
          "Commands run isolated with bubblewrap (bwrap) - restricted to current working directory only. " \
          "Perfect for: system operations, running CLI tools, file operations, data processing, testing commands. " \
          "IMPORTANT: Network access is DISABLED by default (set allow_network: true to enable). " \
          "Cannot access files outside current working directory. " \
          "Has access to standard system utilities (/bin, /usr/bin, etc.)."
        end

        def parameters
          {
            command: {
              type: "string",
              description: "The bash command to execute",
              required: true
            },
            allow_network: {
              type: "boolean",
              description: "Allow network access (default: false)",
              required: false
            },
            timeout: {
              type: "integer",
              description: "Command timeout in seconds (default: 30, max: 300)",
              required: false
            }
          }
        end

        def execute(arguments:, history:, context:)
          command = arguments[:command] || arguments["command"]
          allow_network = arguments[:allow_network] || arguments["allow_network"] || false
          timeout_seconds = arguments[:timeout] || arguments["timeout"] || 30

          raise ArgumentError, "command is required" if command.nil? || command.empty?

          # Clamp timeout to reasonable range
          timeout_seconds = [[timeout_seconds.to_i, 1].max, 300].min

          # Debug output
          if application = context['application']
            application.output.debug("[execute_bash] command: #{command}")
            application.output.debug("[execute_bash] allow_network: #{allow_network}")
            application.output.debug("[execute_bash] timeout: #{timeout_seconds}s")
            application.output.debug("[execute_bash] cwd: #{Dir.pwd}")
          end

          stdout = ""
          stderr = ""
          exit_code = nil

          begin
            # Build bubblewrap command
            bwrap_args = build_bwrap_args(allow_network)

            # Use 'timeout' command to handle timeouts cleanly
            bwrap_args += ['--', 'timeout', "#{timeout_seconds}s", 'bash', '-c', command]

            # Execute command
            stdout, stderr, status = Open3.capture3(*bwrap_args, chdir: Dir.pwd)
            exit_code = status.exitstatus

          rescue StandardError => e
            stderr = "Execution failed: #{e.message}"
            exit_code = 1
          end

          # Check if command timed out (exit code 124 from timeout command)
          timed_out = (exit_code == 124)
          if timed_out
            stderr = "Command timed out after #{timeout_seconds} seconds"
          end

          {
            stdout: stdout,
            stderr: stderr,
            exit_code: exit_code,
            success: exit_code == 0,
            timed_out: timed_out
          }
        end

        private

        def build_bwrap_args(allow_network)
          args = ['bwrap']

          # Mount standard system directories as read-only
          ['/usr', '/lib', '/lib64', '/bin', '/sbin', '/etc'].each do |dir|
            if Dir.exist?(dir)
              args += ['--ro-bind', dir, dir]
            end
          end

          # Bind current working directory as read-write
          cwd = Dir.pwd
          args += ['--bind', cwd, cwd]
          args += ['--chdir', cwd]

          # Mount proc, dev, tmp
          args += ['--proc', '/proc']
          args += ['--dev', '/dev']
          args += ['--tmpfs', '/tmp']

          # Unshare specific namespaces (not --unshare-all to preserve network control)
          args += ['--unshare-user']
          args += ['--unshare-ipc']
          args += ['--unshare-pid']
          args += ['--unshare-uts']
          args += ['--unshare-cgroup']

          # Disable network unless explicitly allowed
          unless allow_network
            args += ['--unshare-net']
          end

          # Pass through essential environment variables
          if ENV['PATH']
            args += ['--setenv', 'PATH', ENV['PATH']]
          end
          if ENV['HOME']
            args += ['--setenv', 'HOME', ENV['HOME']]
          end
          if ENV['USER']
            args += ['--setenv', 'USER', ENV['USER']]
          end

          args
        end
      end
    end
  end
end
