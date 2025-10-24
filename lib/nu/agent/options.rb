# frozen_string_literal: true

module Nu
  module Agent
    class Options
      attr_reader :reset_model, :debug

      def initialize(args = ARGV)
        @reset_model = nil
        @debug = false
        parse(args)
      end

      private

      def parse(args)
        OptionParser.new do |opts|
          opts.banner = "Usage: nu-agent [options]"

          opts.on("--reset-models MODEL", String, "Reset all model configs to MODEL") do |model|
            @reset_model = model
          end

          opts.on("--debug", "Enable debug logging") do
            @debug = true
          end

          opts.on("-v", "--version", "Show version") do
            puts "nu-agent version #{Nu::Agent::VERSION}"
            exit
          end

          opts.on("-h", "--help", "Prints this help") do
            puts opts
            print_available_models
            exit
          end
        end.parse!(args)
      end

      def print_available_models
        models = ClientFactory.display_models

        # Get defaults from each client
        anthropic_default = Nu::Agent::Clients::Anthropic::DEFAULT_MODEL
        google_default = Nu::Agent::Clients::Google::DEFAULT_MODEL
        openai_default = Nu::Agent::Clients::OpenAI::DEFAULT_MODEL
        xai_default = Nu::Agent::Clients::XAI::DEFAULT_MODEL

        # Mark defaults with asterisk
        anthropic_list = models[:anthropic].map { |m| m == anthropic_default ? "#{m}*" : m }.join(', ')
        google_list = models[:google].map { |m| m == google_default ? "#{m}*" : m }.join(', ')
        openai_list = models[:openai].map { |m| m == openai_default ? "#{m}*" : m }.join(', ')
        xai_list = models[:xai].map { |m| m == xai_default ? "#{m}*" : m }.join(', ')

        puts "\nAvailable Models (* = default):"
        puts "  Anthropic: #{anthropic_list}"
        puts "  Google:    #{google_list}"
        puts "  OpenAI:    #{openai_list}"
        puts "  X.AI:      #{xai_list}"
      end
    end
  end
end
