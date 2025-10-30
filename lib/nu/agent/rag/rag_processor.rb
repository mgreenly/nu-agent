# frozen_string_literal: true

module Nu
  module Agent
    module RAG
      # Base class for RAG retrieval processors using Chain of Responsibility pattern
      # Each processor receives a context object, processes it, and passes it to the next processor
      class RAGProcessor
        attr_accessor :next_processor

        def initialize
          @next_processor = nil
        end

        # Main entry point for processing
        # Subclasses should override process_internal
        def process(context)
          process_internal(context)
          @next_processor&.process(context)
          context
        end

        protected

        # Override this method in subclasses to implement processing logic
        def process_internal(context)
          raise NotImplementedError, "Subclasses must implement process_internal"
        end
      end
    end
  end
end
