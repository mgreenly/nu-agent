# frozen_string_literal: true

require_relative "base_command"

module Nu
  module Agent
    module Commands
      # Command to set verbosity level
      class VerbosityCommand < BaseCommand
        def execute(input)
          parts = input.split(" ", 2)
          if parts.length < 2 || parts[1].strip.empty?
            app.console.puts("\e[90mUsage: /verbosity <number>\e[0m")
            app.console.puts("\e[90mCurrent: verbosity=#{app.verbosity}\e[0m")
            return :continue
          end

          value = parts[1].strip
          if value =~ /^\d+$/
            app.verbosity = value.to_i
            app.history.set_config("verbosity", value)
            app.console.puts("\e[90mverbosity=#{app.verbosity}\e[0m")
          else
            app.console.puts("\e[90mInvalid option. Use: /verbosity <number>\e[0m")
          end

          :continue
        end
      end
    end
  end
end
