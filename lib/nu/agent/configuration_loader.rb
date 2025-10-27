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
        keyword_init: true
      )

      def self.load(history:, options:)
        # Load or initialize model configurations
        orchestrator_model = history.get_config("model_orchestrator")
        spellchecker_model = history.get_config("model_spellchecker")
        summarizer_model = history.get_config("model_summarizer")

        # Handle --reset-model flag
        if options.reset_model
          history.set_config("model_orchestrator", options.reset_model)
          history.set_config("model_spellchecker", options.reset_model)
          history.set_config("model_summarizer", options.reset_model)
          orchestrator_model = options.reset_model
          spellchecker_model = options.reset_model
          summarizer_model = options.reset_model
        elsif orchestrator_model.nil? || spellchecker_model.nil? || summarizer_model.nil?
          # Models not configured and no reset flag provided
          raise Error, "Models not configured. Run with --reset-models <model_name> to initialize."
        end

        # Create client instances with configured models
        orchestrator = ClientFactory.create(orchestrator_model)
        spellchecker = ClientFactory.create(spellchecker_model)
        summarizer = ClientFactory.create(summarizer_model)

        # Load settings from database (default all to true, except debug which defaults to false)
        debug = history.get_config("debug", default: "false") == "true"
        debug = true if options.debug # Command line option overrides database setting

        # Load other settings
        verbosity = history.get_config("verbosity", default: "0").to_i
        redact = history.get_config("redaction", default: "true") == "true"
        summarizer_enabled = history.get_config("summarizer_enabled", default: "true") == "true"
        spell_check_enabled = history.get_config("spell_check_enabled", default: "true") == "true"

        Configuration.new(
          orchestrator: orchestrator,
          spellchecker: spellchecker,
          summarizer: summarizer,
          debug: debug,
          verbosity: verbosity,
          redact: redact,
          summarizer_enabled: summarizer_enabled,
          spell_check_enabled: spell_check_enabled
        )
      end
    end
  end
end
