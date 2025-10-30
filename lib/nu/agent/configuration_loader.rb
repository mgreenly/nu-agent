# frozen_string_literal: true

module Nu
  module Agent
    # Loads application configuration from database and options
    class ConfigurationLoader
      # Configuration object that holds all loaded settings
      Configuration = Struct.new(
        :orchestrator,
        :spellchecker,
        :summarizer,
        :debug,
        :verbosity,
        :redact,
        :summarizer_enabled,
        :spell_check_enabled,
        :embedding_enabled,
        :embedding_client,
        keyword_init: true
      )

      def self.load(history:, options:)
        models = load_or_reset_models(history, options)
        clients = create_clients(models)
        settings = load_settings(history, options)

        build_configuration(clients, settings)
      end

      def self.load_or_reset_models(history, options)
        orchestrator = history.get_config("model_orchestrator")
        spellchecker = history.get_config("model_spellchecker")
        summarizer = history.get_config("model_summarizer")

        if options.reset_model
          history.set_config("model_orchestrator", options.reset_model)
          history.set_config("model_spellchecker", options.reset_model)
          history.set_config("model_summarizer", options.reset_model)
          { orchestrator: options.reset_model, spellchecker: options.reset_model, summarizer: options.reset_model }
        elsif orchestrator.nil? || spellchecker.nil? || summarizer.nil?
          raise Error, "Models not configured. Run with --reset-models <model_name> to initialize."
        else
          { orchestrator: orchestrator, spellchecker: spellchecker, summarizer: summarizer }
        end
      end

      def self.create_clients(models)
        {
          orchestrator: ClientFactory.create(models[:orchestrator]),
          spellchecker: ClientFactory.create(models[:spellchecker]),
          summarizer: ClientFactory.create(models[:summarizer]),
          embedding_client: Clients::OpenAIEmbeddings.new
        }
      end

      def self.load_settings(history, options)
        debug = history.get_config("debug", default: "false") == "true"
        debug = true if options.debug

        {
          debug: debug,
          verbosity: history.get_config("verbosity", default: "0").to_i,
          redact: history.get_config("redaction", default: "true") == "true",
          summarizer_enabled: history.get_config("summarizer_enabled", default: "true") == "true",
          spell_check_enabled: history.get_config("spell_check_enabled", default: "true") == "true",
          embedding_enabled: history.get_config("embedding_enabled", default: "true") == "true"
        }
      end

      def self.build_configuration(clients, settings)
        Configuration.new(
          orchestrator: clients[:orchestrator],
          spellchecker: clients[:spellchecker],
          summarizer: clients[:summarizer],
          embedding_client: clients[:embedding_client],
          **settings
        )
      end
    end
  end
end
