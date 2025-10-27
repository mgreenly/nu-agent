# frozen_string_literal: true

module Nu
  module Agent
    # Manages conversation CRUD operations
    class ConversationRepository
      def initialize(connection)
        @connection = connection
      end

      def create_conversation
        result = @connection.query(<<~SQL)
          INSERT INTO conversations (created_at, title, status)
          VALUES (CURRENT_TIMESTAMP, 'New Conversation', 'active')
          RETURNING id
        SQL
        result.to_a.first.first
      end

      def update_conversation_summary(conversation_id:, summary:, model:, cost: nil)
        @connection.query(<<~SQL)
          UPDATE conversations
          SET summary = '#{escape_sql(summary)}',
              summary_model = '#{escape_sql(model)}',
              summary_cost = #{cost || 'NULL'}
          WHERE id = #{conversation_id}
        SQL
      end

      def all_conversations
        result = @connection.query(<<~SQL)
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

      def get_unsummarized_conversations(exclude_id:)
        result = @connection.query(<<~SQL)
          SELECT id, created_at
          FROM conversations
          WHERE summary IS NULL
            AND id != #{exclude_id}
          ORDER BY id DESC
        SQL

        result.map do |row|
          {
            "id" => row[0],
            "created_at" => row[1]
          }
        end
      end

      private

      def escape_sql(string)
        string.to_s.gsub("'", "''")
      end
    end
  end
end
