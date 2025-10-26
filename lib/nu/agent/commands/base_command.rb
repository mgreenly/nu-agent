# frozen_string_literal: true

module Nu
  module Agent
    module Commands
      # Base class for all commands in the command pattern
      # Subclasses must implement the #execute method
      class BaseCommand
        def initialize(application)
          @app = application
        end

        # Execute the command
        # @param input [String] the raw command input from the user
        # @return [Symbol] :continue, :exit, or other control flow symbols
        def execute(_input)
          raise NotImplementedError, "#{self.class} must implement #execute"
        end

        protected

        attr_reader :app
      end
    end
  end
end
