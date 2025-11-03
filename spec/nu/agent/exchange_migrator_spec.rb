# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe Nu::Agent::ExchangeMigrator do
  let(:test_db_path) { "db/test_exchange_migrator.db" }
  let(:db) { DuckDB::Database.open(test_db_path) }
  let(:connection) { db.connect }
  let(:schema_manager) { Nu::Agent::SchemaManager.new(connection) }
  let(:conversation_repo) { Nu::Agent::ConversationRepository.new(connection) }
  let(:message_repo) { Nu::Agent::MessageRepository.new(connection) }
  let(:exchange_repo) { Nu::Agent::ExchangeRepository.new(connection) }
  let(:migrator) { described_class.new(connection, conversation_repo, message_repo, exchange_repo) }

  before do
    FileUtils.rm_rf(test_db_path)
    FileUtils.mkdir_p("db")
    schema_manager.setup_schema
  end

  after do
    connection.close
    db.close
    FileUtils.rm_rf(test_db_path)
  end

  describe "#migrate_exchanges" do
    it "returns empty stats when no conversations exist" do
      stats = migrator.migrate_exchanges

      expect(stats[:conversations]).to eq(0)
      expect(stats[:exchanges_created]).to eq(0)
      expect(stats[:messages_updated]).to eq(0)
    end

    it "creates exchanges from existing messages" do
      conv_id = conversation_repo.create_conversation

      # Add some messages (simulating a conversation)
      message_repo.add_message(conversation_id: conv_id, actor: "user", role: "user", content: "Hello")
      message_repo.add_message(conversation_id: conv_id, actor: "assistant", role: "assistant", content: "Hi there")
      message_repo.add_message(conversation_id: conv_id, actor: "user", role: "user", content: "How are you?")
      message_repo.add_message(conversation_id: conv_id, actor: "assistant", role: "assistant",
                               content: "I'm doing well")

      stats = migrator.migrate_exchanges

      expect(stats[:conversations]).to eq(1)
      expect(stats[:exchanges_created]).to eq(2) # Two user messages = 2 exchanges
      expect(stats[:messages_updated]).to eq(4)
    end

    it "updates message exchange_ids" do
      conv_id = conversation_repo.create_conversation

      message_repo.add_message(conversation_id: conv_id, actor: "user", role: "user", content: "Question")
      message_repo.add_message(conversation_id: conv_id, actor: "assistant", role: "assistant", content: "Answer")

      migrator.migrate_exchanges

      # Check that messages were assigned to an exchange
      messages = message_repo.messages(conversation_id: conv_id, include_in_context_only: false)

      expect(messages[0]["exchange_id"]).not_to be_nil
      expect(messages[1]["exchange_id"]).not_to be_nil
      expect(messages[0]["exchange_id"]).to eq(messages[1]["exchange_id"]) # Same exchange
    end

    it "creates separate exchanges for multiple user messages" do
      conv_id = conversation_repo.create_conversation

      message_repo.add_message(conversation_id: conv_id, actor: "user", role: "user", content: "First question")
      message_repo.add_message(conversation_id: conv_id, actor: "assistant", role: "assistant", content: "First answer")
      message_repo.add_message(conversation_id: conv_id, actor: "user", role: "user", content: "Second question")
      message_repo.add_message(conversation_id: conv_id, actor: "assistant", role: "assistant",
                               content: "Second answer")

      migrator.migrate_exchanges

      messages = message_repo.messages(conversation_id: conv_id, include_in_context_only: false)

      first_exchange_id = messages[0]["exchange_id"]
      second_exchange_id = messages[2]["exchange_id"]

      expect(first_exchange_id).not_to eq(second_exchange_id) # Different exchanges
      expect(messages[1]["exchange_id"]).to eq(first_exchange_id) # First answer in first exchange
      expect(messages[3]["exchange_id"]).to eq(second_exchange_id) # Second answer in second exchange
    end

    it "sets exchange metrics from messages" do
      conv_id = conversation_repo.create_conversation

      message_repo.add_message(
        conversation_id: conv_id,
        actor: "user",
        role: "user",
        content: "Question",
        tokens_input: 100,
        spend: 0.01
      )
      message_repo.add_message(
        conversation_id: conv_id,
        actor: "assistant",
        role: "assistant",
        content: "Answer",
        tokens_output: 50,
        spend: 0.02
      )

      migrator.migrate_exchanges

      exchanges = exchange_repo.get_conversation_exchanges(conversation_id: conv_id)

      expect(exchanges.length).to eq(1)
      expect(exchanges[0]["tokens_input"]).to eq(100)
      expect(exchanges[0]["tokens_output"]).to eq(50)
      expect(exchanges[0]["spend"]).to be_within(0.001).of(0.03)
      expect(exchanges[0]["message_count"]).to eq(2)
    end
  end

  describe "#calculate_exchange_metrics" do
    it "calculates metrics from message list" do
      messages = [
        { "tokens_input" => 100, "tokens_output" => 20, "spend" => 0.01, "tool_calls" => [{ "id" => "1" }] },
        { "tokens_input" => 50, "tokens_output" => 30, "spend" => 0.02, "tool_calls" => nil },
        { "tokens_input" => nil, "tokens_output" => nil, "spend" => nil, "tool_calls" => [] }
      ]

      metrics = migrator.send(:calculate_exchange_metrics, messages)

      expect(metrics[:tokens_input]).to eq(100) # max
      expect(metrics[:tokens_output]).to eq(50) # sum
      expect(metrics[:spend]).to be_within(0.001).of(0.03) # sum
      expect(metrics[:tool_call_count]).to eq(1) # count with tool_calls
    end
  end

  describe "#find_final_assistant_message" do
    it "finds last assistant message with content, no tool_calls" do
      messages = [
        { "role" => "user", "content" => "Question" },
        { "role" => "assistant", "content" => "Thinking", "tool_calls" => [{ "id" => "1" }] },
        { "role" => "assistant", "content" => "Final answer", "tool_calls" => nil }
      ]

      result = migrator.send(:find_final_assistant_message, messages)

      expect(result["content"]).to eq("Final answer")
    end

    it "returns nil when no qualifying message exists" do
      messages = [
        { "role" => "user", "content" => "Question" },
        { "role" => "assistant", "content" => "", "tool_calls" => nil }
      ]

      result = migrator.send(:find_final_assistant_message, messages)

      expect(result).to be_nil
    end
  end

  describe "#process_conversation with edge cases" do
    it "handles conversation with no messages" do
      conversation_repo.create_conversation

      stats = migrator.migrate_exchanges

      expect(stats[:conversations]).to eq(1)
      expect(stats[:exchanges_created]).to eq(0)
      expect(stats[:messages_updated]).to eq(0)
    end

    it "handles assistant messages without user message first" do
      conv_id = conversation_repo.create_conversation

      # Add assistant message first (orphaned)
      message_repo.add_message(conversation_id: conv_id, actor: "assistant", role: "assistant",
                               content: "Orphaned message")

      stats = migrator.migrate_exchanges

      expect(stats[:conversations]).to eq(1)
      expect(stats[:exchanges_created]).to eq(0) # No exchanges created for orphaned messages
      expect(stats[:messages_updated]).to eq(0)
    end
  end

  describe "#escape_sql" do
    it "escapes single quotes in SQL strings" do
      result = migrator.send(:escape_sql, "It's a test")
      expect(result).to eq("It''s a test")
    end

    it "handles strings with multiple single quotes" do
      result = migrator.send(:escape_sql, "I'm saying 'hello'")
      expect(result).to eq("I''m saying ''hello''")
    end

    it "handles strings without single quotes" do
      result = migrator.send(:escape_sql, "Hello world")
      expect(result).to eq("Hello world")
    end
  end

  describe "#finalize_current_exchange" do
    it "returns early when messages array is empty" do
      stats = { messages_updated: 0 }

      # Should not raise error and should not update stats
      migrator.send(:finalize_current_exchange, 1, [], stats)

      expect(stats[:messages_updated]).to eq(0)
    end
  end

  describe "#fetch_conversation_messages" do
    it "handles nil tool_calls, tool_result, and error fields" do
      conv_id = conversation_repo.create_conversation

      # Insert a message with NULL values for JSON fields
      connection.query(<<~SQL)
        INSERT INTO messages (conversation_id, actor, role, content, tool_calls, tool_result, error)
        VALUES (#{conv_id}, 'user', 'user', 'Test message', NULL, NULL, NULL)
      SQL

      messages = migrator.send(:fetch_conversation_messages, conv_id)

      expect(messages.length).to eq(1)
      expect(messages[0]["tool_calls"]).to be_nil
      expect(messages[0]["tool_result"]).to be_nil
      expect(messages[0]["error"]).to be_nil
    end

    it "parses JSON fields when present" do
      conv_id = conversation_repo.create_conversation

      # Insert a message with JSON values
      connection.query(<<~SQL)
        INSERT INTO messages (conversation_id, actor, role, content, tool_calls, tool_result, error)
        VALUES (#{conv_id}, 'assistant', 'assistant', 'Test',
                '[{"id": "call_1", "name": "test"}]',
                '{"output": "result"}',
                '{"message": "error occurred"}')
      SQL

      messages = migrator.send(:fetch_conversation_messages, conv_id)

      expect(messages.length).to eq(1)
      expect(messages[0]["tool_calls"]).to eq([{ "id" => "call_1", "name" => "test" }])
      expect(messages[0]["tool_result"]).to eq({ "output" => "result" })
      expect(messages[0]["error"]).to eq({ "message" => "error occurred" })
    end
  end

  describe "#finalize_exchange with string timestamps" do
    it "converts string timestamps to Time objects" do
      conv_id = conversation_repo.create_conversation
      exchange_id = exchange_repo.create_exchange(conversation_id: conv_id, user_message: "Test")

      # Create messages with string timestamps
      time_str = "2024-01-15 10:30:45"
      messages = [
        {
          "id" => 1,
          "actor" => "user",
          "role" => "user",
          "content" => "Question",
          "model" => nil,
          "tokens_input" => 100,
          "tokens_output" => 0,
          "tool_calls" => nil,
          "tool_call_id" => nil,
          "tool_result" => nil,
          "error" => nil,
          "created_at" => time_str,  # String timestamp
          "redacted" => false,
          "spend" => 0.01
        },
        {
          "id" => 2,
          "actor" => "assistant",
          "role" => "assistant",
          "content" => "Answer",
          "model" => "test-model",
          "tokens_input" => 100,
          "tokens_output" => 50,
          "tool_calls" => nil,
          "tool_call_id" => nil,
          "tool_result" => nil,
          "error" => nil,
          "created_at" => time_str,  # String timestamp
          "redacted" => false,
          "spend" => 0.02
        }
      ]

      # Stub message_repo to avoid issues with message IDs
      allow(message_repo).to receive(:update_message_exchange_id)

      # Finalize the exchange (should handle string timestamps)
      migrator.send(:finalize_exchange, exchange_id, messages)

      # Verify the exchange was updated
      exchanges = exchange_repo.get_conversation_exchanges(conversation_id: conv_id)
      expect(exchanges.length).to eq(1)
      expect(exchanges[0]["status"]).to eq("completed")
    end
  end

  describe "#build_exchange_updates without assistant message" do
    it "does not include assistant_message when no qualifying message exists" do
      metrics = { tokens_input: 100, tokens_output: 50, spend: 0.01, tool_call_count: 0 }
      started_at = Time.now - 60
      completed_at = Time.now

      # No assistant message
      set_clauses = migrator.send(:build_exchange_updates, metrics, nil, started_at, completed_at, 2)

      # Should not include assistant_message clause
      assistant_clause = set_clauses.find { |c| c.include?("assistant_message") }
      expect(assistant_clause).to be_nil

      # Should still include other clauses
      expect(set_clauses).to include("status = 'completed'")
      expect(set_clauses.any? { |c| c.include?("tokens_input") }).to be true
    end
  end
end
