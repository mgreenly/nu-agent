# frozen_string_literal: true

require_relative "base_command"

module Nu
  module Agent
    module Commands
      # Registry for managing and dispatching commands
      class CommandRegistry
        def initialize
          @commands = {}
        end

        # Register a command class with a command name
        # @param name [String] the command name (e.g., "/help")
        # @param command_class [Class] the command class to register
        def register(name, command_class)
          @commands[name] = command_class
        end

        # Check if a command is registered
        # @param name [String] the command name
        # @return [Boolean] true if registered, false otherwise
        def registered?(name)
          @commands.key?(name)
        end

        # Find a registered command class
        # @param name [String] the command name
        # @return [Class, nil] the command class or nil if not found
        def find(name)
          @commands[name]
        end

        # Execute a command
        # @param name [String] the command name
        # @param input [String] the full input string
        # @param application [Nu::Agent::Application] the application instance
        # @return [Symbol] the result of command execution or :unknown
        def execute(name, input, application)
          command_class = find(name)
          return :unknown if command_class.nil?

          command = command_class.new(application)
          command.execute(input)
        end

        # Get all registered commands
        # @return [Hash] a copy of the registered commands hash
        def registered_commands
          @commands.dup
        end
      end
    end
  end
end
