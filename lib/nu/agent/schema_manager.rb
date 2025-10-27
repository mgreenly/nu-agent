# frozen_string_literal: true

module Nu
  module Agent
    # Manages database schema setup, migrations, and introspection
    class SchemaManager
      def initialize(connection)
        @connection = connection
      end

      def setup_schema
        create_sequences
        create_tables
        add_missing_columns
        setup_vector_search
        initialize_config
      end

      def list_tables
        result = @connection.query("SHOW TABLES")
        result.map { |row| row[0] }
      end

      def describe_table(table_name)
        result = @connection.query("DESCRIBE #{escape_identifier(table_name)}")
        result.map do |row|
          {
            "column_name" => row[0],
            "column_type" => row[1],
            "null" => row[2],
            "key" => row[3],
            "default" => row[4],
            "extra" => row[5]
          }
        end
      end

      def add_column_if_not_exists(table, column, type)
        result = @connection.query(<<~SQL)
          SELECT COUNT(*) as count
          FROM information_schema.columns
          WHERE table_name = '#{table}' AND column_name = '#{column}'
        SQL

        count = result.to_a.first[0]
        @connection.query("ALTER TABLE #{table} ADD COLUMN #{column} #{type}") if count.zero?
      rescue StandardError
        # Column might already exist, ignore error
      end

      def escape_identifier(identifier)
        # Remove any characters that aren't alphanumeric or underscore
        identifier.to_s.gsub(/[^a-zA-Z0-9_]/, "")
      end

      private

      def create_sequences
        @connection.query("CREATE SEQUENCE IF NOT EXISTS conversations_id_seq START 1")
        @connection.query("CREATE SEQUENCE IF NOT EXISTS messages_id_seq START 1")
        @connection.query("CREATE SEQUENCE IF NOT EXISTS exchanges_id_seq START 1")
        @connection.query("CREATE SEQUENCE IF NOT EXISTS text_embedding_3_small_id_seq START 1")
        @connection.query("CREATE SEQUENCE IF NOT EXISTS command_history_id_seq START 1")
      end

      def create_tables
        create_conversations_table
        create_exchanges_table
        create_messages_table
        create_embeddings_table
        create_appconfig_table
        create_command_history_table
      end

      def create_conversations_table
        @connection.query(<<~SQL)
          CREATE TABLE IF NOT EXISTS conversations (
            id INTEGER PRIMARY KEY DEFAULT nextval('conversations_id_seq'),
            created_at TIMESTAMP,
            title TEXT,
            status TEXT,
            summary TEXT,
            summary_model TEXT,
            summary_cost FLOAT
          )
        SQL
      end

      def create_exchanges_table
        @connection.query(<<~SQL)
          CREATE TABLE IF NOT EXISTS exchanges (
            id INTEGER PRIMARY KEY DEFAULT nextval('exchanges_id_seq'),
            conversation_id INTEGER NOT NULL,
            exchange_number INTEGER NOT NULL,
            started_at TIMESTAMP NOT NULL,
            completed_at TIMESTAMP,
            summary TEXT,
            summary_model TEXT,
            status TEXT,
            error TEXT,
            user_message TEXT,
            assistant_message TEXT,
            tokens_input INTEGER,
            tokens_output INTEGER,
            spend FLOAT,
            message_count INTEGER,
            tool_call_count INTEGER
          )
        SQL
      end

      def create_messages_table
        @connection.query(<<~SQL)
          CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY DEFAULT nextval('messages_id_seq'),
            conversation_id INTEGER,
            actor TEXT,
            role TEXT,
            content TEXT,
            model TEXT,
            include_in_context BOOLEAN DEFAULT true,
            tokens_input INTEGER,
            tokens_output INTEGER,
            spend FLOAT,
            tool_calls TEXT,
            tool_call_id TEXT,
            tool_result TEXT,
            created_at TIMESTAMP
          )
        SQL
      end

      def create_embeddings_table
        @connection.query(<<~SQL)
          CREATE TABLE IF NOT EXISTS text_embedding_3_small (
            id INTEGER PRIMARY KEY DEFAULT nextval('text_embedding_3_small_id_seq'),
            kind TEXT NOT NULL,
            source TEXT NOT NULL,
            content TEXT NOT NULL,
            embedding FLOAT[1536],
            indexed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(kind, source)
          )
        SQL

        @connection.query(<<~SQL)
          CREATE INDEX IF NOT EXISTS idx_kind ON text_embedding_3_small(kind)
        SQL
      end

      def create_appconfig_table
        @connection.query(<<~SQL)
          CREATE TABLE IF NOT EXISTS appconfig (
            key TEXT PRIMARY KEY,
            value TEXT,
            updated_at TIMESTAMP
          )
        SQL
      end

      def create_command_history_table
        @connection.query(<<~SQL)
          CREATE TABLE IF NOT EXISTS command_history (
            id INTEGER PRIMARY KEY DEFAULT nextval('command_history_id_seq'),
            command TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          )
        SQL

        @connection.query(<<~SQL)
          CREATE INDEX IF NOT EXISTS idx_command_history_created_at ON command_history(created_at DESC)
        SQL
      end

      def add_missing_columns
        # Add tool columns if they don't exist (for existing databases)
        add_column_if_not_exists("messages", "tool_calls", "TEXT")
        add_column_if_not_exists("messages", "tool_call_id", "TEXT")
        add_column_if_not_exists("messages", "tool_result", "TEXT")
        add_column_if_not_exists("messages", "spend", "FLOAT")
        add_column_if_not_exists("messages", "error", "TEXT")
        add_column_if_not_exists("messages", "redacted", "BOOLEAN DEFAULT FALSE")
        add_column_if_not_exists("messages", "exchange_id", "INTEGER")

        # Add summary columns to conversations
        add_column_if_not_exists("conversations", "summary", "TEXT")
        add_column_if_not_exists("conversations", "summary_model", "TEXT")
        add_column_if_not_exists("conversations", "summary_cost", "FLOAT")
      end

      def setup_vector_search
        # Install and load VSS extension for vector similarity search
        @connection.query("INSTALL vss")
        @connection.query("LOAD vss")

        # Create HNSW index for vector similarity search
        @connection.query(<<~SQL)
          CREATE INDEX IF NOT EXISTS idx_embedding_hnsw ON text_embedding_3_small USING HNSW(embedding)
        SQL
      rescue StandardError
        # VSS extension might not be available or already loaded, that's OK
      end

      def initialize_config
        # Initialize active_workers if not set
        result = @connection.query("SELECT value FROM appconfig WHERE key = 'active_workers'")
        row = result.to_a.first
        return if row

        @connection.query(<<~SQL)
          INSERT OR REPLACE INTO appconfig (key, value, updated_at)
          VALUES ('active_workers', '0', CURRENT_TIMESTAMP)
        SQL
      end
    end
  end
end
