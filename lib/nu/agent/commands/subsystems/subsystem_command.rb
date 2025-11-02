# frozen_string_literal: true

module Nu
  module Agent
    module Commands
      module Subsystems
        # Base class for subsystem-specific commands
        # Provides common verbosity management functionality
        class SubsystemCommand
          def initialize(application, subsystem_name, config_key)
            @app = application
            @subsystem_name = subsystem_name
            @config_key = config_key
          end

          def execute(input)
            # Strip command prefix if present (e.g., "/llm" from "/llm help")
            # Input can be either with prefix ("/llm help") or without ("help")
            parts = input.strip.split(/\s+/)

            # If first part starts with /, it's the command prefix - skip it
            parts.shift if parts.first&.start_with?("/")

            subcommand = parts.shift || ""
            args = parts

            execute_subcommand(subcommand, args)
            :continue
          end

          protected

          attr_reader :app, :subsystem_name, :config_key

          def execute_subcommand(subcommand, args)
            case subcommand
            when "verbosity"
              handle_verbosity(args)
            when "help", ""
              show_help
            else
              show_error(subcommand)
            end
          end

          def handle_verbosity(args)
            if args.empty?
              show_current_verbosity
            else
              update_verbosity(args[0])
            end
          end

          def show_current_verbosity
            level = load_verbosity
            app.console.puts("")
            app.output_line("#{config_key}=#{level}", type: :command)
          end

          def update_verbosity(level_str)
            level = Integer(level_str)
            if level.negative?
              show_verbosity_error("Level must be non-negative")
              return
            end

            app.history.set_config(config_key, level_str)
            app.console.puts("")
            app.output_line("#{config_key}=#{level}", type: :command)
          rescue ArgumentError
            show_verbosity_error("Level must be a number")
          end

          def load_verbosity
            app.history.get_int(config_key, default: 0)
          end

          def show_help
            raise NotImplementedError, "Subclasses must implement show_help"
          end

          def show_error(subcommand)
            app.console.puts("")
            app.output_line("Unknown subcommand: #{subcommand}", type: :command)
            app.output_line("Use: /#{subsystem_name} help", type: :command)
          end

          def show_verbosity_error(message)
            app.console.puts("")
            app.output_line("Error: #{message}", type: :command)
            app.output_line("Usage: /#{subsystem_name} verbosity <level>", type: :command)
          end
        end
      end
    end
  end
end
