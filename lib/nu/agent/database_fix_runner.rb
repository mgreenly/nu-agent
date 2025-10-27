# frozen_string_literal: true

module Nu
  module Agent
    # Runs database corruption detection and fix operations
    class DatabaseFixRunner
      def self.run(application)
        application.console.puts("")
        application.output_line("Scanning database for corruption...", type: :debug)

        corrupted = application.history.find_corrupted_messages

        if corrupted.empty?
          application.output_line("✓ No corruption found", type: :debug)
          return
        end

        application.output_line("Found #{corrupted.length} corrupted message(s):", type: :debug)
        corrupted.each do |msg|
          application.output_line("  • Message #{msg['id']}: #{msg['tool_name']} with redacted arguments " \
                                  "(#{msg['created_at']})", type: :debug)
        end

        response = prompt_user(application)

        if response == "y"
          ids = corrupted.map { |m| m["id"] }
          count = application.history.fix_corrupted_messages(ids)
          application.output_line("✓ Deleted #{count} corrupted message(s)", type: :debug)
        else
          application.output_line("Skipped", type: :debug)
        end
      end

      def self.prompt_user(application)
        if application.tui&.active
          application.tui.readline("Delete these messages? [y/N] ").chomp.downcase
        else
          print "\nDelete these messages? [y/N] "
          gets.chomp.downcase
        end
      end
      private_class_method :prompt_user
    end
  end
end
