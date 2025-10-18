# frozen_string_literal: true

module Nu
  module Agent
    class Options
      attr_reader :llm, :debug

      def initialize(args = ARGV)
        @llm = 'claude'
        @debug = false
        parse(args)
      end

      private

      def parse(args)
        OptionParser.new do |opts|
          opts.banner = "Usage: nu-agent [options]"

          opts.on("--llm LLM", String, "LLM to use (claude or gemini)") do |llm|
            @llm = llm
          end

          opts.on("--debug", "Enable debug logging") do
            @debug = true
          end

          opts.on("-h", "--help", "Prints this help") do
            puts opts
            exit
          end
        end.parse!(args)
      end
    end
  end
end
