# frozen_string_literal: true

module Nu
  module Agent
    class Application
      def initialize(llm: 'claude')
        @llm_name = llm
        @llm = create_llm(llm)
      end

      def run
        puts "Asking #{@llm_name.capitalize}: What is a Saturn rocket?\n\n"

        response = @llm.chat(prompt: "What is a Saturn rocket")

        puts response
        puts "\nTokens: #{@llm.input_tokens} in / #{@llm.output_tokens} out / #{@llm.total_tokens} total"
      end

      private

      def create_llm(llm_name)
        case llm_name.downcase
        when 'claude'
          ClaudeClient.new
        when 'gemini'
          GeminiClient.new
        else
          raise Error, "Unknown LLM: #{llm_name}. Use 'claude' or 'gemini'."
        end
      end
    end
  end
end
