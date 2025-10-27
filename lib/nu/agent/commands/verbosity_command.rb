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
            show_usage
            return :continue
          end

          update_verbosity(parts[1].strip)
          :continue
        end

        private

        def show_usage
          app.console.puts("\e[90mUsage: /verbosity <number>\e[0m")
          app.console.puts("\e[90mCurrent: verbosity=#{app.verbosity}\e[0m")
        end

        def update_verbosity(value)
          if value =~ /^\d+$/
            app.verbosity = value.to_i
            app.history.set_config("verbosity", value)
            app.console.puts("\e[90mverbosity=#{app.verbosity}\e[0m")
          else
            app.console.puts("\e[90mInvalid option. Use: /verbosity <number>\e[0m")
          end
        end
      end
    end
  end
end
