# frozen_string_literal: true

module Nu
  module Agent
    # Builder for constructing LLM requests in an internal format
    # that can be translated to specific LLM provider APIs
    class LlmRequestBuilder
      attr_reader :system_prompt, :history, :rag_content, :user_query, :tools, :metadata

      def initialize
        @system_prompt = nil
        @history = nil
        @rag_content = nil
        @user_query = nil
        @tools = nil
        @metadata = nil
      end

      def with_system_prompt(prompt)
        @system_prompt = prompt
        self
      end

      def with_history(messages)
        @history = messages
        self
      end

      def with_rag_content(content)
        @rag_content = content
        self
      end

      def with_user_query(query)
        @user_query = query
        self
      end

      def with_tools(tools)
        @tools = tools
        self
      end

      def with_metadata(metadata)
        @metadata = metadata
        self
      end
    end
  end
end
