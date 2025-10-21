# frozen_string_literal: true

module Nu
  module Agent
    class Tool
      def name
        raise NotImplementedError, "#{self.class} must implement #name"
      end

      def description
        raise NotImplementedError, "#{self.class} must implement #description"
      end

      def parameters
        raise NotImplementedError, "#{self.class} must implement #parameters"
      end

      def execute(arguments:, history:, context:)
        raise NotImplementedError, "#{self.class} must implement #execute"
      end
    end
  end
end
