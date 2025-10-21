# frozen_string_literal: true

require 'duckdb'
require 'fileutils'
require 'json'

module Nu
  module Agent
    class History
      def initialize(db_path: 'db/dev.db')
        ensure_db_directory(db_path)
        @db = DuckDB::Database.open(db_path)
        @conn = @db.connect
        setup_schema
      end

      def add_message(conversation_id:, actor:, role:, content:, model: nil, include_in_context: true, tokens_input: nil, tokens_output: nil, tool_calls: nil, tool_call_id: nil, tool_result: nil)
        tool_calls_json = tool_calls ? "'#{escape_sql(JSON.generate(tool_calls))}'" : 'NULL'
        tool_result_json = tool_result ? "'#{escape_sql(JSON.generate(tool_result))}'" : 'NULL'

        @conn.query(<<~SQL)
          INSERT INTO messages (
            conversation_id, actor, role, content, model,
            include_in_context, tokens_input, tokens_output,
            tool_calls, tool_call_id, tool_result, created_at
          ) VALUES (
            #{conversation_id}, '#{escape_sql(actor)}', '#{escape_sql(role)}',
            '#{escape_sql(content || '')}', #{model ? "'#{escape_sql(model)}'" : 'NULL'},
            #{include_in_context}, #{tokens_input || 'NULL'}, #{tokens_output || 'NULL'},
            #{tool_calls_json}, #{tool_call_id ? "'#{escape_sql(tool_call_id)}'" : 'NULL'},
            #{tool_result_json}, CURRENT_TIMESTAMP
          )
        SQL
      end

      def messages(conversation_id:, include_in_context_only: true)
        condition = include_in_context_only ? "AND include_in_context = true" : ""
        result = @conn.query(<<~SQL)
          SELECT id, actor, role, content, model, tokens_input, tokens_output,
                 tool_calls, tool_call_id, tool_result, created_at
          FROM messages
          WHERE conversation_id = #{conversation_id} #{condition}
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

      def messages_since(conversation_id:, message_id:)
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

      def create_conversation
        result = @conn.query(<<~SQL)
          INSERT INTO conversations (created_at, title, status)
          VALUES (CURRENT_TIMESTAMP, 'New Conversation', 'active')
          RETURNING id
        SQL
        result.to_a.first.first
      end

      def set_config(key, value)
        @conn.query(<<~SQL)
          INSERT OR REPLACE INTO appconfig (key, value, updated_at)
          VALUES ('#{escape_sql(key)}', '#{escape_sql(value.to_s)}', CURRENT_TIMESTAMP)
        SQL
      end

      def get_config(key, default: nil)
        result = @conn.query(<<~SQL)
          SELECT value FROM appconfig WHERE key = '#{escape_sql(key)}'
        SQL
        row = result.to_a.first
        row ? row[0] : default
      end

      def increment_workers
        current = get_config('active_workers', default: '0').to_i
        set_config('active_workers', current + 1)
      end

      def decrement_workers
        current = get_config('active_workers', default: '0').to_i
        set_config('active_workers', [current - 1, 0].max)
      end

      def workers_idle?
        get_config('active_workers', default: '0').to_i == 0
      end

      def close
        @conn.close
        @db.close
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
