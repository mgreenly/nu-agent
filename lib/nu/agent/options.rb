# frozen_string_literal: true

module Nu
  module Agent
    class Options
      attr_reader :reset_model, :debug, :banner_mode

      def initialize(args = ARGV)
        @reset_model = nil
        @debug = false
        @banner_mode = :full
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

          opts.on("--no-banner", "Disable the welcome banner") do
            @banner_mode = :none
          end

          opts.on("--minimal", "Show minimal banner (version only)") do
            @banner_mode = :minimal
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

        puts "\nAvailable Models (* = default):"
        puts "  Anthropic: #{format_model_list(models[:anthropic], anthropic_default)}"
        puts "  Google:    #{format_model_list(models[:google], google_default)}"
        puts "  OpenAI:    #{format_model_list(models[:openai], openai_default)}"
        puts "  X.AI:      #{format_model_list(models[:xai], xai_default)}"
      end

      def format_model_list(models, default)
        models.map { |m| m == default ? "#{m}*" : m }.join(", ")
      end
    end
  end
end
