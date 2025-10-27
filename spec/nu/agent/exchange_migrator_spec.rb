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

    it "skips spell_checker messages when creating exchanges" do
      conv_id = conversation_repo.create_conversation

      message_repo.add_message(conversation_id: conv_id, actor: "user", role: "user", content: "Test")
      message_repo.add_message(conversation_id: conv_id, actor: "spell_checker", role: "user", content: "Correction")
      message_repo.add_message(conversation_id: conv_id, actor: "assistant", role: "assistant", content: "Response")

      stats = migrator.migrate_exchanges

      expect(stats[:exchanges_created]).to eq(1) # Only one real user message
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

      exchange_id_1 = messages[0]["exchange_id"]
      exchange_id_2 = messages[2]["exchange_id"]

      expect(exchange_id_1).not_to eq(exchange_id_2) # Different exchanges
      expect(messages[1]["exchange_id"]).to eq(exchange_id_1) # First answer in first exchange
      expect(messages[3]["exchange_id"]).to eq(exchange_id_2) # Second answer in second exchange
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
end
