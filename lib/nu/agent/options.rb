# frozen_string_literal: true

module Nu
  module Agent
    class Options
      attr_reader :model, :debug

      def initialize(args = ARGV)
        @model = 'sonnet'
        @debug = false
        parse(args)
      end

      private

      def parse(args)
        OptionParser.new do |opts|
          opts.banner = "Usage: nu-agent [options]"

          opts.on("--model MODEL", String, "Model to use (see available models below)") do |model|
            @model = model
          end

          opts.on("--debug", "Enable debug logging") do
            @debug = true
          end

          opts.on("-h", "--help", "Prints this help") do
            puts opts
            print_available_models
            exit
          end
        end.parse!(args)
      end

      def print_available_models
        models = ModelFactory.display_models

        puts "\nAvailable Models:"
        puts "  Anthropic: #{models[:anthropic].join(', ')}"
        puts "  Google:    #{models[:google].join(', ')}"
        puts "  OpenAI:    #{models[:openai].join(', ')}"
        puts "  X.AI:      #{models[:xai].join(', ')}"
        puts "\n  Default: sonnet"
      end
    end
  end
end
