# frozen_string_literal: true

module Nu
  module Agent
    class History
      attr_reader :db_path

      def initialize(db_path: ENV['NUAGENT_DATABASE'] || File.join(Dir.home, '.nuagent', 'memory.db'))
        @db_path = db_path
        @connection_mutex = Mutex.new  # Only for managing connection pool
        ensure_db_directory(db_path)
        @db = DuckDB::Database.open(db_path)
        @connections = {}

        # Setup schema using main thread's connection
        setup_schema
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
      rescue => e
        conn.query("ROLLBACK") rescue nil
        raise e
      end

      def add_message(conversation_id:, actor:, role:, content:, model: nil, include_in_context: true, tokens_input: nil, tokens_output: nil, spend: nil, tool_calls: nil, tool_call_id: nil, tool_result: nil, error: nil, redacted: false, exchange_id: nil)
        tool_calls_json = tool_calls ? "'#{escape_sql(JSON.generate(tool_calls))}'" : 'NULL'
        tool_result_json = tool_result ? "'#{escape_sql(JSON.generate(tool_result))}'" : 'NULL'
        error_json = error ? "'#{escape_sql(JSON.generate(error))}'" : 'NULL'

        connection.query(<<~SQL)
          INSERT INTO messages (
            conversation_id, actor, role, content, model,
            include_in_context, tokens_input, tokens_output, spend,
            tool_calls, tool_call_id, tool_result, error, redacted, exchange_id, created_at
          ) VALUES (
            #{conversation_id}, '#{escape_sql(actor)}', '#{escape_sql(role)}',
            '#{escape_sql(content || '')}', #{model ? "'#{escape_sql(model)}'" : 'NULL'},
            #{include_in_context}, #{tokens_input || 'NULL'}, #{tokens_output || 'NULL'},
            #{spend || 'NULL'}, #{tool_calls_json}, #{tool_call_id ? "'#{escape_sql(tool_call_id)}'" : 'NULL'},
            #{tool_result_json}, #{error_json}, #{redacted}, #{exchange_id || 'NULL'}, CURRENT_TIMESTAMP
          )
        SQL
      end

      def messages(conversation_id:, include_in_context_only: true, since: nil)
        conditions = []
        conditions << "include_in_context = true" if include_in_context_only
        conditions << "created_at >= '#{since.strftime('%Y-%m-%d %H:%M:%S.%6N')}'" if since

        where_clause = conditions.empty? ? "" : "AND #{conditions.join(' AND ')}"

        result = connection.query(<<~SQL)
          SELECT id, actor, role, content, model, tokens_input, tokens_output,
                 tool_calls, tool_call_id, tool_result, error, created_at, redacted, exchange_id
          FROM messages
          WHERE conversation_id = #{conversation_id} #{where_clause}
          ORDER BY id ASC
        SQL

        result.map do |row|
          {
            "id" => row[0],
            "actor" => row[1],
            "role" => row[2],
            "content" => row[3],
            "model" => row[4],
            "tokens_input" => row[5],
            "tokens_output" => row[6],
            "tool_calls" => row[7] ? JSON.parse(row[7]) : nil,
            "tool_call_id" => row[8],
            "tool_result" => row[9] ? JSON.parse(row[9]) : nil,
            "error" => row[10] ? JSON.parse(row[10]) : nil,
            "created_at" => row[11],
            "redacted" => row[12],
            "exchange_id" => row[13]
          }
        end
      end

      def messages_since(conversation_id:, message_id:)
        result = connection.query(<<~SQL)
          SELECT id, actor, role, content, model, tokens_input, tokens_output,
                 tool_calls, tool_call_id, tool_result, error, created_at, redacted, exchange_id
          FROM messages
          WHERE conversation_id = #{conversation_id} AND id > #{message_id}
          ORDER BY id ASC
        SQL

        result.map do |row|
          {
            "id" => row[0],
            "actor" => row[1],
            "role" => row[2],
            "content" => row[3],
            "model" => row[4],
            "tokens_input" => row[5],
            "tokens_output" => row[6],
            "tool_calls" => row[7] ? JSON.parse(row[7]) : nil,
            "tool_call_id" => row[8],
            "tool_result" => row[9] ? JSON.parse(row[9]) : nil,
            "error" => row[10] ? JSON.parse(row[10]) : nil,
            "created_at" => row[11],
            "redacted" => row[12],
            "exchange_id" => row[13]
          }
        end
      end

      def session_tokens(conversation_id:, since:)
        result = connection.query(<<~SQL)
          SELECT
            COALESCE(MAX(tokens_input), 0) as total_input,
            COALESCE(SUM(tokens_output), 0) as total_output,
            COALESCE(SUM(spend), 0.0) as total_spend
          FROM messages
          WHERE conversation_id = #{conversation_id}
            AND created_at >= '#{since.strftime('%Y-%m-%d %H:%M:%S.%6N')}'
        SQL

        row = result.to_a.first
        {
          "input" => row[0],
          "output" => row[1],
          "total" => row[0] + row[1],
          "spend" => row[2]
        }
      end

      def current_context_size(conversation_id:, since:, model:)
        result = connection.query(<<~SQL)
          SELECT tokens_input
          FROM messages
          WHERE conversation_id = #{conversation_id}
            AND created_at >= '#{since.strftime('%Y-%m-%d %H:%M:%S.%6N')}'
            AND model = '#{escape_sql(model)}'
            AND tokens_input IS NOT NULL
          ORDER BY created_at DESC
          LIMIT 1
        SQL

        row = result.to_a.first
        row ? row[0] : 0
      end

      def get_message_by_id(message_id, conversation_id:)
        result = connection.query(<<~SQL)
          SELECT id, actor, role, content, model, tokens_input, tokens_output,
                 tool_calls, tool_call_id, tool_result, error, created_at
          FROM messages
          WHERE id = #{message_id} AND conversation_id = #{conversation_id}
          LIMIT 1
        SQL

        rows = result.to_a
        return nil if rows.empty?

        row = rows.first
        {
          'id' => row[0],
          'actor' => row[1],
          'role' => row[2],
          'content' => row[3],
          'model' => row[4],
          'tokens_input' => row[5],
          'tokens_output' => row[6],
          'tool_calls' => row[7] ? JSON.parse(row[7]) : nil,
          'tool_call_id' => row[8],
          'tool_result' => row[9] ? JSON.parse(row[9]) : nil,
          'error' => row[10] ? JSON.parse(row[10]) : nil,
          'created_at' => row[11]
        }
      end

      def create_conversation
        result = connection.query(<<~SQL)
          INSERT INTO conversations (created_at, title, status)
          VALUES (CURRENT_TIMESTAMP, 'New Conversation', 'active')
          RETURNING id
        SQL
        result.to_a.first.first
      end

      def update_conversation_summary(conversation_id:, summary:, model:, cost: nil)
        connection.query(<<~SQL)
          UPDATE conversations
          SET summary = '#{escape_sql(summary)}',
              summary_model = '#{escape_sql(model)}',
              summary_cost = #{cost || 'NULL'}
          WHERE id = #{conversation_id}
        SQL
      end

      def create_exchange(conversation_id:, user_message:)
        # Get the next exchange number for this conversation
        result = connection.query(<<~SQL)
          SELECT COALESCE(MAX(exchange_number), 0) + 1 as next_number
          FROM exchanges
          WHERE conversation_id = #{conversation_id}
        SQL
        exchange_number = result.to_a.first.first

        # Create the exchange
        result = connection.query(<<~SQL)
          INSERT INTO exchanges (
            conversation_id, exchange_number, started_at, status, user_message
          ) VALUES (
            #{conversation_id}, #{exchange_number}, CURRENT_TIMESTAMP, 'in_progress', '#{escape_sql(user_message)}'
          )
          RETURNING id
        SQL
        result.to_a.first.first
      end

      def update_exchange(exchange_id:, updates: {})
        set_clauses = []

        updates.each do |key, value|
          case key.to_s
          when 'status', 'summary', 'summary_model', 'error', 'assistant_message'
            set_clauses << "#{key} = '#{escape_sql(value)}'"
          when 'completed_at'
            if value.is_a?(Time)
              set_clauses << "#{key} = '#{value.strftime('%Y-%m-%d %H:%M:%S.%6N')}'"
            else
              set_clauses << "#{key} = CURRENT_TIMESTAMP"
            end
          when 'tokens_input', 'tokens_output', 'spend', 'message_count', 'tool_call_count'
            set_clauses << "#{key} = #{value || 'NULL'}"
          end
        end

        return if set_clauses.empty?

        connection.query(<<~SQL)
          UPDATE exchanges
          SET #{set_clauses.join(', ')}
          WHERE id = #{exchange_id}
        SQL
      end

      def complete_exchange(exchange_id:, summary: nil, assistant_message: nil, metrics: {})
        set_clauses = ["status = 'completed'", "completed_at = CURRENT_TIMESTAMP"]

        if summary
          set_clauses << "summary = '#{escape_sql(summary)}'"
        end

        if assistant_message
          set_clauses << "assistant_message = '#{escape_sql(assistant_message)}'"
        end

        # Add metrics
        metrics.each do |key, value|
          case key.to_s
          when 'tokens_input', 'tokens_output', 'spend', 'message_count', 'tool_call_count'
            set_clauses << "#{key} = #{value || 'NULL'}"
          end
        end

        connection.query(<<~SQL)
          UPDATE exchanges
          SET #{set_clauses.join(', ')}
          WHERE id = #{exchange_id}
        SQL
      end

      def get_exchange_messages(exchange_id:)
        result = connection.query(<<~SQL)
          SELECT id, actor, role, content, model, tokens_input, tokens_output,
                 tool_calls, tool_call_id, tool_result, error, created_at, redacted, exchange_id
          FROM messages
          WHERE exchange_id = #{exchange_id}
          ORDER BY id ASC
        SQL

        result.map do |row|
          {
            "id" => row[0],
            "actor" => row[1],
            "role" => row[2],
            "content" => row[3],
            "model" => row[4],
            "tokens_input" => row[5],
            "tokens_output" => row[6],
            "tool_calls" => row[7] ? JSON.parse(row[7]) : nil,
            "tool_call_id" => row[8],
            "tool_result" => row[9] ? JSON.parse(row[9]) : nil,
            "error" => row[10] ? JSON.parse(row[10]) : nil,
            "created_at" => row[11],
            "redacted" => row[12],
            "exchange_id" => row[13]
          }
        end
      end

      def get_conversation_exchanges(conversation_id:)
        result = connection.query(<<~SQL)
          SELECT id, exchange_number, started_at, completed_at, status,
                 user_message, assistant_message, summary,
                 tokens_input, tokens_output, spend,
                 message_count, tool_call_count
          FROM exchanges
          WHERE conversation_id = #{conversation_id}
          ORDER BY exchange_number ASC
        SQL

        result.map do |row|
          {
            "id" => row[0],
            "exchange_number" => row[1],
            "started_at" => row[2],
            "completed_at" => row[3],
            "status" => row[4],
            "user_message" => row[5],
            "assistant_message" => row[6],
            "summary" => row[7],
            "tokens_input" => row[8],
            "tokens_output" => row[9],
            "spend" => row[10],
            "message_count" => row[11],
            "tool_call_count" => row[12]
          }
        end
      end

      def get_all_conversations
        result = connection.query(<<~SQL)
          SELECT id, created_at, title, status
          FROM conversations
          ORDER BY id ASC
        SQL

        result.map do |row|
          {
            "id" => row[0],
            "created_at" => row[1],
            "title" => row[2],
            "status" => row[3]
          }
        end
      end

      def update_message_exchange_id(message_id:, exchange_id:)
        connection.query(<<~SQL)
          UPDATE messages
          SET exchange_id = #{exchange_id}
          WHERE id = #{message_id}
        SQL
      end

      def migrate_exchanges
        stats = {
          conversations: 0,
          exchanges_created: 0,
          messages_updated: 0
        }

        conversations = get_all_conversations

        conversations.each do |conv|
          conv_id = conv['id']

          # Get all messages for this conversation (not just current session)
          result = connection.query(<<~SQL)
            SELECT id, actor, role, content, model, tokens_input, tokens_output,
                   tool_calls, tool_call_id, tool_result, error, created_at, redacted, spend
            FROM messages
            WHERE conversation_id = #{conv_id}
            ORDER BY id ASC
          SQL

          messages = result.map do |row|
            {
              "id" => row[0],
              "actor" => row[1],
              "role" => row[2],
              "content" => row[3],
              "model" => row[4],
              "tokens_input" => row[5],
              "tokens_output" => row[6],
              "tool_calls" => row[7] ? JSON.parse(row[7]) : nil,
              "tool_call_id" => row[8],
              "tool_result" => row[9] ? JSON.parse(row[9]) : nil,
              "error" => row[10] ? JSON.parse(row[10]) : nil,
              "created_at" => row[11],
              "redacted" => row[12],
              "spend" => row[13]
            }
          end

          next if messages.empty?

          current_exchange_id = nil
          exchange_messages = []

          messages.each do |msg|
            # Start new exchange on user messages (excluding spell_checker)
            if msg['role'] == 'user' && msg['actor'] != 'spell_checker'
              # Finalize previous exchange if exists
              if current_exchange_id && !exchange_messages.empty?
                finalize_exchange(current_exchange_id, exchange_messages)
                stats[:messages_updated] += exchange_messages.length
              end

              # Create new exchange
              current_exchange_id = create_exchange(
                conversation_id: conv_id,
                user_message: msg['content'] || ''
              )
              stats[:exchanges_created] += 1
              exchange_messages = [msg]
            else
              # Add to current exchange (if one exists)
              exchange_messages << msg if current_exchange_id
            end
          end

          # Finalize last exchange
          if current_exchange_id && !exchange_messages.empty?
            finalize_exchange(current_exchange_id, exchange_messages)
            stats[:messages_updated] += exchange_messages.length
          end

          stats[:conversations] += 1
        end

        stats
      end

      private

      def finalize_exchange(exchange_id, messages)
        # Calculate metrics from messages
        tokens_input = messages.map { |m| m['tokens_input'] || 0 }.max || 0
        tokens_output = messages.sum { |m| m['tokens_output'] || 0 }
        spend = messages.sum { |m| m['spend'] || 0.0 }
        tool_call_count = messages.count { |m| m['tool_calls'] && !m['tool_calls'].empty? }

        # Find final assistant message (last assistant message with content, no tool_calls)
        assistant_msg = messages.reverse.find do |m|
          m['role'] == 'assistant' && m['content'] && !m['content'].empty? && !m['tool_calls']
        end

        # Get timestamps from messages (they're already Time objects)
        started_at = messages.first['created_at']
        completed_at = messages.last['created_at']

        # Convert to Time if they're strings
        started_at = Time.parse(started_at) if started_at.is_a?(String)
        completed_at = Time.parse(completed_at) if completed_at.is_a?(String)

        # Update exchange with completion info
        set_clauses = [
          "status = 'completed'",
          "completed_at = '#{completed_at.strftime('%Y-%m-%d %H:%M:%S.%6N')}'",
          "started_at = '#{started_at.strftime('%Y-%m-%d %H:%M:%S.%6N')}'",
          "tokens_input = #{tokens_input}",
          "tokens_output = #{tokens_output}",
          "spend = #{spend}",
          "message_count = #{messages.length}",
          "tool_call_count = #{tool_call_count}"
        ]

        if assistant_msg && assistant_msg['content']
          set_clauses << "assistant_message = '#{escape_sql(assistant_msg['content'])}'"
        end

        connection.query(<<~SQL)
          UPDATE exchanges
          SET #{set_clauses.join(', ')}
          WHERE id = #{exchange_id}
        SQL

        # Update all messages with this exchange_id
        messages.each do |msg|
          update_message_exchange_id(message_id: msg['id'], exchange_id: exchange_id)
        end
      end

      public

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
        result = connection.query(<<~SQL)
          SELECT id, created_at
          FROM conversations
          WHERE summary IS NULL
            AND id != #{exclude_id}
          ORDER BY id DESC
        SQL

        result.map do |row|
          {
            'id' => row[0],
            'created_at' => row[1]
          }
        end
      end

      def set_config(key, value)
        connection.query(<<~SQL)
          INSERT OR REPLACE INTO appconfig (key, value, updated_at)
          VALUES ('#{escape_sql(key)}', '#{escape_sql(value.to_s)}', CURRENT_TIMESTAMP)
        SQL
      end

      def get_config(key, default: nil)
        result = connection.query(<<~SQL)
          SELECT value FROM appconfig WHERE key = '#{escape_sql(key)}'
        SQL
        row = result.to_a.first
        row ? row[0] : default
      end

      # Get all indexed sources for a given kind
      def get_indexed_sources(kind:)
        result = connection.query(<<~SQL)
          SELECT source FROM text_embedding_3_small WHERE kind = '#{escape_sql(kind)}'
        SQL
        result.map { |row| row[0] }
      end

      # Store embeddings in the database
      def store_embeddings(kind:, records:)
        records.each do |record|
          source = record[:source]
          content = record[:content]
          embedding = record[:embedding]

          # Convert embedding array to DuckDB array format
          embedding_str = "[#{embedding.join(', ')}]"

          connection.query(<<~SQL)
            INSERT INTO text_embedding_3_small (kind, source, content, embedding)
            VALUES ('#{escape_sql(kind)}', '#{escape_sql(source)}', '#{escape_sql(content)}', #{embedding_str})
            ON CONFLICT (kind, source) DO NOTHING
          SQL
        end
      end

      # Get embedding statistics
      def embedding_stats(kind: nil)
        where_clause = kind ? "WHERE kind = '#{escape_sql(kind)}'" : ""

        result = connection.query(<<~SQL)
          SELECT kind, COUNT(*) as count
          FROM text_embedding_3_small
          #{where_clause}
          GROUP BY kind
        SQL

        result.map do |row|
          { 'kind' => row[0], 'count' => row[1] }
        end
      end

      # Clear all embeddings for a given kind
      def clear_embeddings(kind:)
        connection.query(<<~SQL)
          DELETE FROM text_embedding_3_small WHERE kind = '#{escape_sql(kind)}'
        SQL
      end

      def increment_workers
        result = connection.query("SELECT value FROM appconfig WHERE key = 'active_workers'")
        row = result.to_a.first
        current = row ? row[0].to_i : 0
        new_value = current + 1
        connection.query(<<~SQL)
          INSERT OR REPLACE INTO appconfig (key, value, updated_at)
          VALUES ('active_workers', '#{new_value}', CURRENT_TIMESTAMP)
        SQL
      end

      def decrement_workers
        result = connection.query("SELECT value FROM appconfig WHERE key = 'active_workers'")
        row = result.to_a.first
        current = row ? row[0].to_i : 0
        new_value = [current - 1, 0].max
        connection.query(<<~SQL)
          INSERT OR REPLACE INTO appconfig (key, value, updated_at)
          VALUES ('active_workers', '#{new_value}', CURRENT_TIMESTAMP)
        SQL
      end

      def workers_idle?
        result = connection.query("SELECT value FROM appconfig WHERE key = 'active_workers'")
        row = result.to_a.first
        current = row ? row[0].to_i : 0
        current == 0
      end

      def list_tables
        result = connection.query("SHOW TABLES")
        result.map { |row| row[0] }
      end

      def describe_table(table_name)
        result = connection.query("DESCRIBE #{escape_identifier(table_name)}")
        result.map do |row|
          {
            'column_name' => row[0],
            'column_type' => row[1],
            'null' => row[2],
            'key' => row[3],
            'default' => row[4],
            'extra' => row[5]
          }
        end
      end

      def execute_query(sql)
        # Strip trailing semicolon if present
        sql = sql.strip.chomp(';')

        # Validate it's a read-only query
        normalized_sql = sql.upcase.strip
        readonly_commands = ['SELECT', 'SHOW', 'DESCRIBE', 'EXPLAIN', 'WITH']
        is_readonly = readonly_commands.any? { |cmd| normalized_sql.start_with?(cmd) }

        unless is_readonly
          raise ArgumentError, "Only read-only queries (SELECT, SHOW, DESCRIBE, EXPLAIN, WITH) are allowed"
        end

        # Execute query on read-only connection
        result = connection.query(sql)

        # Convert to array of hashes
        rows = result.to_a
        return [] if rows.empty?

        # Get column names from first row
        column_count = rows.first.length
        columns = (0...column_count).map { |i| "column_#{i}" }

        # Try to get actual column names if available
        begin
          columns = result.columns.map(&:name) if result.respond_to?(:columns)
        rescue
          # Use default column names if we can't get real ones
        end

        # Cap at 500 rows
        rows = rows.take(500)

        # Map to array of hashes
        rows.map do |row|
          hash = {}
          columns.each_with_index do |col, i|
            hash[col] = row[i]
          end
          hash
        end
      end

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
            if tc['arguments'] == { 'redacted' => true }
              corrupted << {
                'id' => id,
                'conversation_id' => conv_id,
                'role' => role,
                'tool_name' => tc['name'],
                'created_at' => created_at
              }
            end
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
        @connection_mutex.synchronize do
          @connections.each_value(&:close)
          @connections.clear
        end
        @db.close
      end

      private

      def ensure_db_directory(db_path)
        dir = File.dirname(db_path)
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      end

      def setup_schema
        connection.query(<<~SQL)
          CREATE SEQUENCE IF NOT EXISTS conversations_id_seq START 1
        SQL

        connection.query(<<~SQL)
          CREATE SEQUENCE IF NOT EXISTS messages_id_seq START 1
        SQL

        connection.query(<<~SQL)
          CREATE SEQUENCE IF NOT EXISTS exchanges_id_seq START 1
        SQL

        connection.query(<<~SQL)
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

        connection.query(<<~SQL)
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

        connection.query(<<~SQL)
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

        # Add tool columns if they don't exist (for existing databases)
        add_column_if_not_exists('messages', 'tool_calls', 'TEXT')
        add_column_if_not_exists('messages', 'tool_call_id', 'TEXT')
        add_column_if_not_exists('messages', 'tool_result', 'TEXT')
        add_column_if_not_exists('messages', 'spend', 'FLOAT')
        add_column_if_not_exists('messages', 'error', 'TEXT')
        add_column_if_not_exists('messages', 'redacted', 'BOOLEAN DEFAULT FALSE')
        add_column_if_not_exists('messages', 'exchange_id', 'INTEGER')

        # Add summary columns to conversations
        add_column_if_not_exists('conversations', 'summary', 'TEXT')
        add_column_if_not_exists('conversations', 'summary_model', 'TEXT')
        add_column_if_not_exists('conversations', 'summary_cost', 'FLOAT')

        # Embeddings table for semantic search
        connection.query(<<~SQL)
          CREATE SEQUENCE IF NOT EXISTS text_embedding_3_small_id_seq START 1
        SQL

        connection.query(<<~SQL)
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

        connection.query(<<~SQL)
          CREATE INDEX IF NOT EXISTS idx_kind ON text_embedding_3_small(kind)
        SQL

        # Install and load VSS extension for vector similarity search
        begin
          connection.query("INSTALL vss")
          connection.query("LOAD vss")

          # Create HNSW index for vector similarity search
          connection.query(<<~SQL)
            CREATE INDEX IF NOT EXISTS idx_embedding_hnsw ON text_embedding_3_small USING HNSW(embedding)
          SQL
        rescue => e
          # VSS extension might not be available or already loaded, that's OK
        end

        connection.query(<<~SQL)
          CREATE TABLE IF NOT EXISTS appconfig (
            key TEXT PRIMARY KEY,
            value TEXT,
            updated_at TIMESTAMP
          )
        SQL

        # Initialize active_workers if not set
        unless get_config('active_workers')
          set_config('active_workers', 0)
        end
      end

      def escape_sql(string)
        string.to_s.gsub("'", "''")
      end

      def escape_identifier(identifier)
        # Remove any characters that aren't alphanumeric or underscore
        identifier.to_s.gsub(/[^a-zA-Z0-9_]/, '')
      end

      def add_column_if_not_exists(table, column, type)
        result = connection.query(<<~SQL)
          SELECT COUNT(*) as count
          FROM information_schema.columns
          WHERE table_name = '#{table}' AND column_name = '#{column}'
        SQL

        count = result.to_a.first[0]
        if count == 0
          connection.query("ALTER TABLE #{table} ADD COLUMN #{column} #{type}")
        end
      rescue => e
        # Column might already exist, ignore error
      end
    end
  end
end
