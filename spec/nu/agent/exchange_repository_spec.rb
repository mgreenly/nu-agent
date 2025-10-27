# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe Nu::Agent::ExchangeRepository do
  let(:test_db_path) { "db/test_exchange_repository.db" }
  let(:db) { DuckDB::Database.open(test_db_path) }
  let(:connection) { db.connect }
  let(:schema_manager) { Nu::Agent::SchemaManager.new(connection) }
  let(:conversation_repo) { Nu::Agent::ConversationRepository.new(connection) }
  let(:exchange_repo) { described_class.new(connection) }
  let(:conversation_id) { conversation_repo.create_conversation }

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

  describe "#create_exchange" do
    it "creates a new exchange and returns its id" do
      exchange_id = exchange_repo.create_exchange(
        conversation_id: conversation_id,
        user_message: "Hello"
      )

      expect(exchange_id).to be_a(Integer)
      expect(exchange_id).to be > 0
    end

    it "creates exchange with correct exchange_number" do
      ex1 = exchange_repo.create_exchange(conversation_id: conversation_id, user_message: "First")
      ex2 = exchange_repo.create_exchange(conversation_id: conversation_id, user_message: "Second")

      result = connection.query("SELECT exchange_number FROM exchanges WHERE id = #{ex1}")
      expect(result.to_a.first[0]).to eq(1)

      result = connection.query("SELECT exchange_number FROM exchanges WHERE id = #{ex2}")
      expect(result.to_a.first[0]).to eq(2)
    end

    it "creates exchange with status in_progress" do
      exchange_id = exchange_repo.create_exchange(conversation_id: conversation_id, user_message: "Test")

      result = connection.query("SELECT status, user_message FROM exchanges WHERE id = #{exchange_id}")
      row = result.to_a.first

      expect(row[0]).to eq("in_progress")
      expect(row[1]).to eq("Test")
    end
  end

  describe "#update_exchange" do
    let(:exchange_id) { exchange_repo.create_exchange(conversation_id: conversation_id, user_message: "Initial") }

    it "updates string fields" do
      exchange_repo.update_exchange(
        exchange_id: exchange_id,
        updates: {
          status: "completed",
          summary: "Test summary",
          assistant_message: "Response"
        }
      )

      result = connection.query("SELECT status, summary, assistant_message FROM exchanges WHERE id = #{exchange_id}")
      row = result.to_a.first

      expect(row[0]).to eq("completed")
      expect(row[1]).to eq("Test summary")
      expect(row[2]).to eq("Response")
    end

    it "updates numeric fields" do
      exchange_repo.update_exchange(
        exchange_id: exchange_id,
        updates: {
          tokens_input: 100,
          tokens_output: 50,
          spend: 0.05,
          message_count: 3,
          tool_call_count: 1
        }
      )

      result = connection.query("SELECT tokens_input, tokens_output, spend, message_count, tool_call_count FROM exchanges WHERE id = #{exchange_id}")
      row = result.to_a.first

      expect(row[0]).to eq(100)
      expect(row[1]).to eq(50)
      expect(row[2]).to be_within(0.001).of(0.05)
      expect(row[3]).to eq(3)
      expect(row[4]).to eq(1)
    end

    it "updates completed_at with Time" do
      time = Time.now
      exchange_repo.update_exchange(
        exchange_id: exchange_id,
        updates: { completed_at: time }
      )

      result = connection.query("SELECT completed_at FROM exchanges WHERE id = #{exchange_id}")
      completed_at = result.to_a.first[0]

      expect(completed_at).not_to be_nil
      expect(completed_at.to_s).to match(/\d{4}-\d{2}-\d{2}/)
    end

    it "does nothing with empty updates" do
      exchange_repo.update_exchange(exchange_id: exchange_id, updates: {})

      # Should not raise error, just return nil
      expect(true).to be true
    end
  end

  describe "#complete_exchange" do
    let(:exchange_id) { exchange_repo.create_exchange(conversation_id: conversation_id, user_message: "Question") }

    it "marks exchange as completed" do
      exchange_repo.complete_exchange(
        exchange_id: exchange_id,
        summary: "Done",
        assistant_message: "Answer",
        metrics: { tokens_input: 100, tokens_output: 50 }
      )

      result = connection.query("SELECT status, summary, assistant_message, tokens_input, tokens_output FROM exchanges WHERE id = #{exchange_id}")
      row = result.to_a.first

      expect(row[0]).to eq("completed")
      expect(row[1]).to eq("Done")
      expect(row[2]).to eq("Answer")
      expect(row[3]).to eq(100)
      expect(row[4]).to eq(50)
    end

    it "sets completed_at timestamp" do
      exchange_repo.complete_exchange(exchange_id: exchange_id)

      result = connection.query("SELECT completed_at FROM exchanges WHERE id = #{exchange_id}")
      completed_at = result.to_a.first[0]

      expect(completed_at).not_to be_nil
    end
  end

  describe "#get_conversation_exchanges" do
    it "returns all exchanges for a conversation" do
      ex1 = exchange_repo.create_exchange(conversation_id: conversation_id, user_message: "First")
      ex2 = exchange_repo.create_exchange(conversation_id: conversation_id, user_message: "Second")

      exchanges = exchange_repo.get_conversation_exchanges(conversation_id: conversation_id)

      expect(exchanges.length).to eq(2)
      expect(exchanges[0]["id"]).to eq(ex1)
      expect(exchanges[1]["id"]).to eq(ex2)
      expect(exchanges[0]["user_message"]).to eq("First")
      expect(exchanges[1]["user_message"]).to eq("Second")
    end

    it "returns exchanges in order by exchange_number" do
      ex1 = exchange_repo.create_exchange(conversation_id: conversation_id, user_message: "One")
      ex2 = exchange_repo.create_exchange(conversation_id: conversation_id, user_message: "Two")
      ex3 = exchange_repo.create_exchange(conversation_id: conversation_id, user_message: "Three")

      exchanges = exchange_repo.get_conversation_exchanges(conversation_id: conversation_id)

      expect(exchanges[0]["exchange_number"]).to eq(1)
      expect(exchanges[1]["exchange_number"]).to eq(2)
      expect(exchanges[2]["exchange_number"]).to eq(3)
    end
  end
end
