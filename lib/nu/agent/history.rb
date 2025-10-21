# frozen_string_literal: true

module Nu
  module Agent
    class History
      def initialize(db_path: 'db/dev.db')
        @mutex = Mutex.new
        ensure_db_directory(db_path)
        @db = DuckDB::Database.open(db_path)
        @conn = @db.connect
        setup_schema
      end

      def add_message(conversation_id:, actor:, role:, content:, model: nil, include_in_context: true, tokens_input: nil, tokens_output: nil, spend: nil, tool_calls: nil, tool_call_id: nil, tool_result: nil)
        @mutex.synchronize do
          tool_calls_json = tool_calls ? "'#{escape_sql(JSON.generate(tool_calls))}'" : 'NULL'
          tool_result_json = tool_result ? "'#{escape_sql(JSON.generate(tool_result))}'" : 'NULL'

          @conn.query(<<~SQL)
            INSERT INTO messages (
              conversation_id, actor, role, content, model,
              include_in_context, tokens_input, tokens_output, spend,
              tool_calls, tool_call_id, tool_result, created_at
            ) VALUES (
              #{conversation_id}, '#{escape_sql(actor)}', '#{escape_sql(role)}',
              '#{escape_sql(content || '')}', #{model ? "'#{escape_sql(model)}'" : 'NULL'},
              #{include_in_context}, #{tokens_input || 'NULL'}, #{tokens_output || 'NULL'},
              #{spend || 'NULL'}, #{tool_calls_json}, #{tool_call_id ? "'#{escape_sql(tool_call_id)}'" : 'NULL'},
              #{tool_result_json}, CURRENT_TIMESTAMP
            )
          SQL
        end
      end

      def messages(conversation_id:, include_in_context_only: true, since: nil)
        @mutex.synchronize do
          conditions = []
          conditions << "include_in_context = true" if include_in_context_only
          conditions << "created_at >= '#{since.strftime('%Y-%m-%d %H:%M:%S.%6N')}'" if since

          where_clause = conditions.empty? ? "" : "AND #{conditions.join(' AND ')}"

          result = @conn.query(<<~SQL)
            SELECT id, actor, role, content, model, tokens_input, tokens_output,
                   tool_calls, tool_call_id, tool_result, created_at
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
              "created_at" => row[10]
            }
          end
        end
      end

      def messages_since(conversation_id:, message_id:)
        @mutex.synchronize do
          result = @conn.query(<<~SQL)
            SELECT id, actor, role, content, model, tokens_input, tokens_output,
                   tool_calls, tool_call_id, tool_result, created_at
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
              "created_at" => row[10]
            }
          end
        end
      end

      def session_tokens(conversation_id:, since:)
        @mutex.synchronize do
          result = @conn.query(<<~SQL)
            SELECT
              COALESCE(SUM(tokens_input), 0) as total_input,
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
      end

      def create_conversation
        @mutex.synchronize do
          result = @conn.query(<<~SQL)
            INSERT INTO conversations (created_at, title, status)
            VALUES (CURRENT_TIMESTAMP, 'New Conversation', 'active')
            RETURNING id
          SQL
          result.to_a.first.first
        end
      end

      def set_config(key, value)
        @mutex.synchronize do
          @conn.query(<<~SQL)
            INSERT OR REPLACE INTO appconfig (key, value, updated_at)
            VALUES ('#{escape_sql(key)}', '#{escape_sql(value.to_s)}', CURRENT_TIMESTAMP)
          SQL
        end
      end

      def get_config(key, default: nil)
        @mutex.synchronize do
          result = @conn.query(<<~SQL)
            SELECT value FROM appconfig WHERE key = '#{escape_sql(key)}'
          SQL
          row = result.to_a.first
          row ? row[0] : default
        end
      end

      def increment_workers
        @mutex.synchronize do
          result = @conn.query("SELECT value FROM appconfig WHERE key = 'active_workers'")
          row = result.to_a.first
          current = row ? row[0].to_i : 0
          new_value = current + 1
          @conn.query(<<~SQL)
            INSERT OR REPLACE INTO appconfig (key, value, updated_at)
            VALUES ('active_workers', '#{new_value}', CURRENT_TIMESTAMP)
          SQL
        end
      end

      def decrement_workers
        @mutex.synchronize do
          result = @conn.query("SELECT value FROM appconfig WHERE key = 'active_workers'")
          row = result.to_a.first
          current = row ? row[0].to_i : 0
          new_value = [current - 1, 0].max
          @conn.query(<<~SQL)
            INSERT OR REPLACE INTO appconfig (key, value, updated_at)
            VALUES ('active_workers', '#{new_value}', CURRENT_TIMESTAMP)
          SQL
        end
      end

      def workers_idle?
        @mutex.synchronize do
          result = @conn.query("SELECT value FROM appconfig WHERE key = 'active_workers'")
          row = result.to_a.first
          current = row ? row[0].to_i : 0
          current == 0
        end
      end

      def list_tables
        @mutex.synchronize do
          result = @conn.query("SHOW TABLES")
          result.map { |row| row[0] }
        end
      end

      def describe_table(table_name)
        @mutex.synchronize do
          result = @conn.query("DESCRIBE #{escape_identifier(table_name)}")
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
      end

      def execute_readonly_query(sql)
        @mutex.synchronize do
          # Validate it's a read-only query
          normalized_sql = sql.strip.upcase
          unless normalized_sql.start_with?('SELECT') || normalized_sql.start_with?('SHOW') || normalized_sql.start_with?('DESCRIBE')
            raise ArgumentError, "Only SELECT, SHOW, and DESCRIBE queries are allowed"
          end

          # Add LIMIT if not present (only for SELECT queries)
          if normalized_sql.start_with?('SELECT') && !normalized_sql.include?('LIMIT')
            sql = "#{sql.strip} LIMIT 100"
          end

          # Execute query
          result = @conn.query(sql)

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

          # Cap at 1000 rows
          rows = rows.take(1000)

          # Map to array of hashes
          rows.map do |row|
            hash = {}
            columns.each_with_index do |col, i|
              hash[col] = row[i]
            end
            hash
          end
        end
      end

      def close
        @mutex.synchronize do
          @conn.close
          @db.close
        end
      end

      private

      def ensure_db_directory(db_path)
        dir = File.dirname(db_path)
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      end

      def setup_schema
        @conn.query(<<~SQL)
          CREATE SEQUENCE IF NOT EXISTS conversations_id_seq START 1
        SQL

        @conn.query(<<~SQL)
          CREATE SEQUENCE IF NOT EXISTS messages_id_seq START 1
        SQL

        @conn.query(<<~SQL)
          CREATE TABLE IF NOT EXISTS conversations (
            id INTEGER PRIMARY KEY DEFAULT nextval('conversations_id_seq'),
            created_at TIMESTAMP,
            title TEXT,
            status TEXT
          )
        SQL

        @conn.query(<<~SQL)
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

        @conn.query(<<~SQL)
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
        result = @conn.query(<<~SQL)
          SELECT COUNT(*) as count
          FROM information_schema.columns
          WHERE table_name = '#{table}' AND column_name = '#{column}'
        SQL

        count = result.to_a.first[0]
        if count == 0
          @conn.query("ALTER TABLE #{table} ADD COLUMN #{column} #{type}")
        end
      rescue => e
        # Column might already exist, ignore error
      end
    end
  end
end
