# frozen_string_literal: true

module Nu
  module Agent
    # Loads application configuration from database and options
    class ConfigurationLoader
      # Configuration object that holds all loaded settings
      Configuration = Struct.new(
        :orchestrator,
        :summarizer,
        :debug,
        :redact,
        :summarizer_enabled,
        :embedding_enabled,
        :embedding_client,
        :conversation_summarizer_model,
        :exchange_summarizer_model,
        keyword_init: true
      )

      def self.load(history:, options:)
        models = load_or_reset_models(history, options)
        clients = create_clients(models)
        settings = load_settings(history, options)
        settings[:conversation_summarizer_model] = models[:conversation_summarizer]
        settings[:exchange_summarizer_model] = models[:exchange_summarizer]

        build_configuration(clients, settings)
      end

      def self.load_or_reset_models(history, options)
        orchestrator = history.get_config("model_orchestrator")
        summarizer = history.get_config("model_summarizer")
        conversation_summarizer = history.get_config("conversation_summarizer_model")
        exchange_summarizer = history.get_config("exchange_summarizer_model")

        if options.reset_model
          history.set_config("model_orchestrator", options.reset_model)
          history.set_config("model_summarizer", options.reset_model)
          history.set_config("conversation_summarizer_model", options.reset_model)
          history.set_config("exchange_summarizer_model", options.reset_model)
          {
            orchestrator: options.reset_model,
            summarizer: options.reset_model,
            conversation_summarizer: options.reset_model,
            exchange_summarizer: options.reset_model
          }
        elsif orchestrator.nil? || summarizer.nil?
          raise Error, "Models not configured. Run with --reset-models <model_name> to initialize."
        else
          # Fall back to general summarizer model if worker-specific models not configured
          conversation_summarizer ||= summarizer
          exchange_summarizer ||= summarizer

          {
            orchestrator: orchestrator,
            summarizer: summarizer,
            conversation_summarizer: conversation_summarizer,
            exchange_summarizer: exchange_summarizer
          }
        end
      end

      def self.create_clients(models)
        {
          orchestrator: ClientFactory.create(models[:orchestrator]),
          summarizer: ClientFactory.create(models[:summarizer]),
          embedding_client: Clients::OpenAIEmbeddings.new
        }
      end

      def self.load_settings(history, options)
        debug = history.get_config("debug", default: "false") == "true"
        debug = true if options.debug

        {
          debug: debug,
          redact: history.get_config("redaction", default: "true") == "true",
          summarizer_enabled: history.get_config("summarizer_enabled", default: "true") == "true",
          embedding_enabled: history.get_config("embedding_enabled", default: "true") == "true"
        }
      end

      def self.build_configuration(clients, settings)
        Configuration.new(
          orchestrator: clients[:orchestrator],
          summarizer: clients[:summarizer],
          embedding_client: clients[:embedding_client],
          conversation_summarizer_model: settings[:conversation_summarizer_model],
          exchange_summarizer_model: settings[:exchange_summarizer_model],
          **settings.except(:conversation_summarizer_model, :exchange_summarizer_model)
        )
      end
    end
  end
end
