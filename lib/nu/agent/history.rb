# frozen_string_literal: true

module Nu
  module Agent
    class History
      attr_reader :db_path

      def initialize(db_path: ENV["NUAGENT_DATABASE"] || File.join(Dir.home, ".nuagent", "memory.db"))
        @db_path = db_path
        @connection_mutex = Mutex.new # Only for managing connection pool
        ensure_db_directory(db_path)

        # Check for leftover WAL file (indicates unclean shutdown)
        wal_path = "#{db_path}.wal"
        wal_existed = File.exist?(wal_path)
        wal_size = wal_existed ? File.size(wal_path) : 0

        if wal_existed && wal_size.positive?
          warn "⚠️  WAL file detected (#{format_bytes(wal_size)}): Previous shutdown may have been unclean"
          warn "   Database will automatically recover on connect..."
        end

        # Open database (triggers automatic WAL replay if needed)
        @db = DuckDB::Database.open(db_path)
        @connections = {}
        @schema_manager = SchemaManager.new(connection)
        @migration_manager = MigrationManager.new(connection)
        @embedding_store = EmbeddingStore.new(connection)
        @config_store = ConfigStore.new(connection)
        @worker_counter = WorkerCounter.new(@config_store)
        @message_repo = MessageRepository.new(connection)
        @conversation_repo = ConversationRepository.new(connection)
        @exchange_repo = ExchangeRepository.new(connection)
        @exchange_migrator = ExchangeMigrator.new(connection, @conversation_repo, @message_repo, @exchange_repo)

        # Setup schema using main thread's connection
        @schema_manager.setup_schema

        # Run any pending migrations
        @migration_manager.run_pending_migrations

        # If WAL was present, confirm recovery (WAL should be truncated/removed now)
        return unless wal_existed && wal_size.positive?

        current_wal_size = File.exist?(wal_path) ? File.size(wal_path) : 0
        if current_wal_size.zero? || !File.exist?(wal_path)
          warn "✅ Database recovery completed successfully"
        else
          warn "⚠️  WAL file still present (#{format_bytes(current_wal_size)}) - this is normal during active use"
        end
      end

      # Get connection for current thread
      def connection
        thread_id = Thread.current.object_id

        @connection_mutex.synchronize do
          @connections[thread_id] ||= begin
            conn = @db.connect
            conn.query("SET default_null_order='nulls_last'")
            conn
          end
        end
      end

      # Execute block within a transaction
      def transaction(&block)
        conn = connection
        conn.query("BEGIN TRANSACTION")
        result = block.call
        conn.query("COMMIT")
        result
      rescue StandardError => e
        begin
          conn.query("ROLLBACK")
        rescue StandardError
          nil
        end
        raise e
      end

      def add_message(conversation_id:, actor:, role:, content:, **attributes)
        @message_repo.add_message(conversation_id: conversation_id, actor: actor, role: role, content: content,
                                  **attributes)
      end

      def messages(conversation_id:, include_in_context_only: true, since: nil)
        @message_repo.messages(conversation_id: conversation_id, include_in_context_only: include_in_context_only,
                               since: since)
      end

      def messages_since(conversation_id:, message_id:)
        @message_repo.messages_since(conversation_id: conversation_id, message_id: message_id)
      end

      def session_tokens(conversation_id:, since:)
        @message_repo.session_tokens(conversation_id: conversation_id, since: since)
      end

      def current_context_size(conversation_id:, since:, model:)
        @message_repo.current_context_size(conversation_id: conversation_id, since: since, model: model)
      end

      def get_message_by_id(message_id, conversation_id:)
        @message_repo.get_message_by_id(message_id, conversation_id: conversation_id)
      end

      def create_conversation
        @conversation_repo.create_conversation
      end

      def update_conversation_summary(conversation_id:, summary:, model:, cost: nil)
        @conversation_repo.update_conversation_summary(conversation_id: conversation_id, summary: summary,
                                                       model: model, cost: cost)
      end

      def create_exchange(conversation_id:, user_message:)
        @exchange_repo.create_exchange(conversation_id: conversation_id, user_message: user_message)
      end

      def update_exchange(exchange_id:, updates: {})
        @exchange_repo.update_exchange(exchange_id: exchange_id, updates: updates)
      end

      def complete_exchange(exchange_id:, summary: nil, assistant_message: nil, metrics: {})
        @exchange_repo.complete_exchange(exchange_id: exchange_id, summary: summary,
                                         assistant_message: assistant_message, metrics: metrics)
      end

      def get_exchange_messages(exchange_id:)
        @message_repo.get_exchange_messages(exchange_id: exchange_id)
      end

      def get_conversation_exchanges(conversation_id:)
        @exchange_repo.get_conversation_exchanges(conversation_id: conversation_id)
      end

      def all_conversations
        @conversation_repo.all_conversations
      end

      def update_message_exchange_id(message_id:, exchange_id:)
        @message_repo.update_message_exchange_id(message_id: message_id, exchange_id: exchange_id)
      end

      def migrate_exchanges
        @exchange_migrator.migrate_exchanges
      end

      # NOTE: This method is no longer used as of the Phase 5 architecture redesign.
      # Messages are now created with redacted=true from the start in tool_calling_loop,
      # rather than being marked as redacted after the fact.
      # Keeping this commented out for reference/backward compatibility.
      #
      # def mark_turn_as_redacted(conversation_id:, since_message_id:)
      #   @mutex.synchronize do
      #     # Mark messages based on their type, not their position
      #     # We want to redact:
      #     # 1. Tool calls (assistant messages with tool_calls)
      #     # 2. Tool responses (role='tool')
      #     # 3. Error messages (error IS NOT NULL)
      #     # 4. Spell checker messages (actor='spell_checker')
      #     connection.query(<<~SQL)
      #       UPDATE messages
      #       SET redacted = TRUE
      #       WHERE conversation_id = #{conversation_id}
      #         AND id > #{since_message_id}
      #         AND redacted = FALSE
      #         AND (
      #           role = 'tool'
      #           OR (role = 'assistant' AND tool_calls IS NOT NULL)
      #           OR error IS NOT NULL
      #           OR actor = 'spell_checker'
      #         )
      #     SQL
      #   end
      # end

      def get_unsummarized_conversations(exclude_id:)
        @conversation_repo.get_unsummarized_conversations(exclude_id: exclude_id)
      end

      def set_config(key, value)
        @config_store.set_config(key, value)
      end

      def get_config(key, default: nil)
        @config_store.get_config(key, default: default)
      end

      # Add command to command history
      def add_command_history(command)
        @config_store.add_command_history(command)
      end

      # Get command history (most recent first)
      def get_command_history(limit: 1000)
        @config_store.get_command_history(limit: limit)
      end

      # Get all indexed sources for a given kind
      def get_indexed_sources(kind:)
        @embedding_store.get_indexed_sources(kind: kind)
      end

      # Store embeddings in the database
      def store_embeddings(kind:, records:)
        @embedding_store.store_embeddings(kind: kind, records: records)
      end

      # Get embedding statistics
      def embedding_stats(kind: nil)
        @embedding_store.embedding_stats(kind: kind)
      end

      # Clear all embeddings for a given kind
      def clear_embeddings(kind:)
        @embedding_store.clear_embeddings(kind: kind)
      end

      def increment_workers
        @worker_counter.increment_workers
      end

      def decrement_workers
        @worker_counter.decrement_workers
      end

      def workers_idle?
        @worker_counter.workers_idle?
      end

      def list_tables
        @schema_manager.list_tables
      end

      def describe_table(table_name)
        @schema_manager.describe_table(table_name)
      end

      def execute_query(sql)
        sql = sql.strip.chomp(";")
        validate_readonly_query(sql)

        result = connection.query(sql)
        rows = result.to_a
        return [] if rows.empty?

        columns = extract_column_names(result, rows)
        rows = rows.take(500)

        convert_rows_to_hashes(rows, columns)
      end

      private

      def validate_readonly_query(sql)
        normalized_sql = sql.upcase.strip
        readonly_commands = %w[SELECT SHOW DESCRIBE EXPLAIN WITH]
        is_readonly = readonly_commands.any? { |cmd| normalized_sql.start_with?(cmd) }

        return if is_readonly

        raise ArgumentError, "Only read-only queries (SELECT, SHOW, DESCRIBE, EXPLAIN, WITH) are allowed"
      end

      def extract_column_names(result, rows)
        column_count = rows.first.length
        columns = (0...column_count).map { |i| "column_#{i}" }

        begin
          columns = result.columns.map(&:name) if result.respond_to?(:columns)
        rescue StandardError
          # Use default column names if we can't get real ones
        end

        columns
      end

      def convert_rows_to_hashes(rows, columns)
        rows.map do |row|
          hash = {}
          columns.each_with_index do |col, i|
            hash[col] = row[i]
          end
          hash
        end
      end

      public

      def find_corrupted_messages
        # Find messages with redacted tool call arguments
        result = connection.query(<<~SQL)
          SELECT id, conversation_id, role, tool_calls, created_at
          FROM messages
          WHERE tool_calls IS NOT NULL
          ORDER BY id DESC
        SQL

        corrupted = []
        result.each do |row|
          id, conv_id, role, tool_calls_json, created_at = row
          next unless tool_calls_json

          tool_calls = JSON.parse(tool_calls_json)
          tool_calls.each do |tc|
            next unless tc["arguments"] == { "redacted" => true }

            corrupted << {
              "id" => id,
              "conversation_id" => conv_id,
              "role" => role,
              "tool_name" => tc["name"],
              "created_at" => created_at
            }
          end
        end

        corrupted
      end

      def fix_corrupted_messages(message_ids)
        message_ids.each do |id|
          connection.query("DELETE FROM messages WHERE id = #{id}")
        end
        message_ids.length
      end

      def close
        # Explicitly checkpoint before closing to ensure WAL is flushed
        # Do this BEFORE synchronizing to avoid deadlock
        begin
          conn = @connection_mutex.synchronize { @connections[Thread.current.object_id] }
          conn&.query("CHECKPOINT")
        rescue StandardError => e
          # Log but don't fail - db.close will checkpoint anyway
          warn "Warning: Checkpoint failed during shutdown: #{e.message}"
        end

        @connection_mutex.synchronize do
          @connections.each_value(&:close)
          @connections.clear
        end
        @db.close
      end

      private

      def ensure_db_directory(db_path)
        dir = File.dirname(db_path)
        FileUtils.mkdir_p(dir)
      end

      def escape_sql(string)
        string.to_s.gsub("'", "''")
      end

      def format_bytes(bytes)
        if bytes < 1024
          "#{bytes}B"
        elsif bytes < 1024 * 1024
          "#{(bytes / 1024.0).round(1)}KB"
        else
          "#{(bytes / (1024.0 * 1024)).round(1)}MB"
        end
      end
    end
  end
end
