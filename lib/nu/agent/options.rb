# frozen_string_literal: true

require 'optparse'

module Nu
  module Agent
    class Options
      attr_reader :llm

      def initialize(args = ARGV)
        @llm = 'claude' # default
        parse(args)
      end

      private

      def parse(args)
        OptionParser.new do |opts|
          opts.banner = "Usage: nu-agent [options]"

          opts.on("--llm LLM", String, "LLM to use (claude or gemini)") do |llm|
            @llm = llm
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
