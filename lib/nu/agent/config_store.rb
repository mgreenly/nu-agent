# frozen_string_literal: true

module Nu
  module Agent
    # Manages application configuration and command history storage
    class ConfigStore
      def initialize(connection)
        @connection = connection
      end

      def set_config(key, value)
        @connection.query(<<~SQL)
          INSERT OR REPLACE INTO appconfig (key, value, updated_at)
          VALUES ('#{escape_sql(key)}', '#{escape_sql(value.to_s)}', CURRENT_TIMESTAMP)
        SQL
      end

      def get_config(key, default: nil)
        result = @connection.query(<<~SQL)
          SELECT value FROM appconfig WHERE key = '#{escape_sql(key)}'
        SQL
        row = result.to_a.first
        row ? row[0] : default
      end

      # Add command to command history
      def add_command_history(command)
        return if command.nil? || command.strip.empty?

        @connection.query(<<~SQL)
          INSERT INTO command_history (command, created_at)
          VALUES ('#{escape_sql(command)}', CURRENT_TIMESTAMP)
        SQL
      end

      # Get command history (most recent first)
      def get_command_history(limit: 1000)
        result = @connection.query(<<~SQL)
          SELECT command, created_at
          FROM command_history
          ORDER BY created_at DESC
          LIMIT #{limit.to_i}
        SQL

        result.map do |row|
          {
            "command" => row[0],
            "created_at" => row[1]
          }
        end.reverse # Reverse to get chronological order (oldest first)
      end

      private

      def escape_sql(string)
        string.to_s.gsub("'", "''")
      end
    end
  end
end
