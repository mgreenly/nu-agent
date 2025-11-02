# frozen_string_literal: true

module Nu
  module Agent
    # Builder for constructing LLM requests in a standardized internal format.
    #
    # This class implements the Builder pattern to create LLM request objects
    # that are provider-agnostic. The internal format can be translated to
    # specific LLM provider APIs (Anthropic, OpenAI, Google, XAI) by client
    # classes.
    #
    # The builder ensures consistent debug output, eliminates duplication
    # (e.g., tool names), and cleanly separates orchestration from
    # API-specific formatting.
    #
    # @example Building a simple request
    #   request = LlmRequestBuilder.new
    #     .with_system_prompt("You are a helpful assistant")
    #     .with_user_query("What is the weather?")
    #     .build
    #
    # @example Building a request with tools and history
    #   request = LlmRequestBuilder.new
    #     .with_system_prompt("You are a helpful assistant")
    #     .with_history([{ "role" => "user", "content" => "Hello" }])
    #     .with_user_query("What can you do?")
    #     .with_tools(tool_registry)
    #     .with_metadata({ conversation_id: 123 })
    #     .build
    #
    # @see Nu::Agent::ChatLoopOrchestrator#prepare_llm_request
    class LlmRequestBuilder
      # @return [String, nil] The system prompt with instructions
      # @return [Array<Hash>, nil] The message history
      # @return [Hash, nil] RAG content (redactions, spell check, etc.)
      # @return [String, nil] The current user query
      # @return [Array<Hash>, nil] Tool definitions with schemas
      # @return [Hash, nil] Additional metadata for debugging
      attr_reader :system_prompt, :history, :rag_content, :user_query, :tools, :metadata

      # Initializes a new LlmRequestBuilder with all fields set to nil.
      def initialize
        @system_prompt = nil
        @history = nil
        @rag_content = nil
        @user_query = nil
        @tools = nil
        @metadata = nil
      end

      # Sets the system prompt.
      #
      # @param prompt [String] The system instructions/prompt
      # @return [LlmRequestBuilder] self for method chaining
      def with_system_prompt(prompt)
        @system_prompt = prompt
        self
      end

      # Sets the message history.
      #
      # @param messages [Array<Hash>] Array of message hashes with 'role' and 'content' keys
      # @return [LlmRequestBuilder] self for method chaining
      def with_history(messages)
        @history = messages
        self
      end

      # Sets the RAG (Retrieval-Augmented Generation) content.
      #
      # @param content [Hash] RAG content including redactions, spell check, etc.
      # @return [LlmRequestBuilder] self for method chaining
      def with_rag_content(content)
        @rag_content = content
        self
      end

      # Sets the current user query.
      #
      # @param query [String] The user's current message
      # @return [LlmRequestBuilder] self for method chaining
      def with_user_query(query)
        @user_query = query
        self
      end

      # Sets the available tools.
      #
      # @param tools [Array<Hash>] Array of tool definitions with schemas
      # @return [LlmRequestBuilder] self for method chaining
      def with_tools(tools)
        @tools = tools
        self
      end

      # Sets additional metadata.
      #
      # @param metadata [Hash] Additional metadata for debugging (conversation_id, exchange_id, etc.)
      # @return [LlmRequestBuilder] self for method chaining
      def with_metadata(metadata)
        @metadata = metadata
        self
      end

      # Builds and returns the internal request format.
      #
      # The returned hash contains:
      # - system_prompt: System instructions
      # - messages: Complete message array including history and current query
      # - tools: Tool definitions (if provided)
      # - metadata: Combined metadata including RAG content and custom metadata
      #
      # @return [Hash] The complete request in internal format
      # @raise [ArgumentError] if neither user_query nor history is provided
      def build
        validate_required_fields

        {
          system_prompt: @system_prompt,
          messages: construct_messages,
          tools: @tools,
          metadata: construct_metadata
        }.compact
      end

      private

      # Validates that at least one message source is provided.
      #
      # @raise [ArgumentError] if both user_query and history are nil
      # @return [void]
      def validate_required_fields
        return unless @user_query.nil? && @history.nil?

        raise ArgumentError,
              "messages are required (provide user_query and/or history)"
      end

      # Constructs the messages array by combining history and user query.
      #
      # @return [Array<Hash>] The complete messages array
      def construct_messages
        messages = @history ? @history.dup : []
        messages << { "role" => "user", "content" => @user_query } if @user_query
        messages
      end

      # Constructs the metadata hash by combining RAG content and custom metadata.
      #
      # @return [Hash, nil] The combined metadata or nil if both sources are nil
      def construct_metadata
        return nil if @rag_content.nil? && @metadata.nil?

        meta = {}
        meta[:rag_content] = @rag_content if @rag_content
        meta[:user_query] = @user_query if @user_query
        meta.merge!(@metadata) if @metadata
        meta
      end
    end
  end
end
