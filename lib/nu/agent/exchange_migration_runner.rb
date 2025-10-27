# frozen_string_literal: true

module Nu
  module Agent
    # Runs exchange migration operations
    class ExchangeMigrationRunner
      def self.run(application)
        application.console.puts("")
        application.output_line("This will analyze all messages and group them into exchanges.", type: :debug)
        application.output_line("Existing exchanges will NOT be affected.", type: :debug)

        response = prompt_user(application)

        return unless response == "y"

        application.output_line("Migrating exchanges...", type: :debug)

        start_time = Time.now
        stats = application.history.migrate_exchanges
        elapsed = Time.now - start_time

        application.output_line("Migration complete!", type: :debug)
        application.output_line("  Conversations processed: #{stats[:conversations]}", type: :debug)
        application.output_line("  Exchanges created: #{stats[:exchanges_created]}", type: :debug)
        application.output_line("  Messages updated: #{stats[:messages_updated]}", type: :debug)
        application.output_line("  Time elapsed: #{format('%.2f', elapsed)}s", type: :debug)
      end

      def self.prompt_user(application)
        if application.tui&.active
          application.tui.readline("Continue with migration? [y/N] ").chomp.downcase
        else
          print "Continue with migration? [y/N] "
          gets.chomp.downcase
        end
      end
      private_class_method :prompt_user
    end
  end
end
