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

      result = connection.query(
        "SELECT tokens_input, tokens_output, spend, message_count, tool_call_count " \
        "FROM exchanges WHERE id = #{exchange_id}"
      )
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

    it "updates completed_at with CURRENT_TIMESTAMP when not given Time" do
      exchange_repo.update_exchange(
        exchange_id: exchange_id,
        updates: { completed_at: true }
      )

      result = connection.query("SELECT completed_at FROM exchanges WHERE id = #{exchange_id}")
      completed_at = result.to_a.first[0]

      expect(completed_at).not_to be_nil
      expect(completed_at.to_s).to match(/\d{4}-\d{2}-\d{2}/)
    end

    it "does nothing with empty updates" do
      # Should not raise error when given empty updates
      expect do
        exchange_repo.update_exchange(exchange_id: exchange_id, updates: {})
      end.not_to raise_error
    end

    it "ignores unknown keys" do
      exchange_repo.update_exchange(
        exchange_id: exchange_id,
        updates: {
          status: "completed",
          unknown_field: "ignored"
        }
      )

      result = connection.query("SELECT status FROM exchanges WHERE id = #{exchange_id}")
      status = result.to_a.first[0]

      expect(status).to eq("completed")
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

      result = connection.query(
        "SELECT status, summary, assistant_message, tokens_input, tokens_output " \
        "FROM exchanges WHERE id = #{exchange_id}"
      )
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

    it "ignores unknown metric keys" do
      exchange_repo.complete_exchange(
        exchange_id: exchange_id,
        metrics: {
          tokens_input: 100,
          unknown_metric: "ignored"
        }
      )

      result = connection.query("SELECT status, tokens_input FROM exchanges WHERE id = #{exchange_id}")
      row = result.to_a.first

      expect(row[0]).to eq("completed")
      expect(row[1]).to eq(100)
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
      exchange_repo.create_exchange(conversation_id: conversation_id, user_message: "One")
      exchange_repo.create_exchange(conversation_id: conversation_id, user_message: "Two")
      exchange_repo.create_exchange(conversation_id: conversation_id, user_message: "Three")

      exchanges = exchange_repo.get_conversation_exchanges(conversation_id: conversation_id)

      expect(exchanges[0]["exchange_number"]).to eq(1)
      expect(exchanges[1]["exchange_number"]).to eq(2)
      expect(exchanges[2]["exchange_number"]).to eq(3)
    end
  end

  describe "#get_unsummarized_exchanges" do
    it "returns unsummarized completed exchanges excluding current conversation" do
      # Create exchanges in different conversations
      other_conversation_id = conversation_repo.create_conversation

      ex1 = exchange_repo.create_exchange(conversation_id: other_conversation_id, user_message: "Question 1")
      ex2 = exchange_repo.create_exchange(conversation_id: other_conversation_id, user_message: "Question 2")
      ex3 = exchange_repo.create_exchange(conversation_id: conversation_id, user_message: "Current")

      # Complete exchanges without summaries
      exchange_repo.complete_exchange(exchange_id: ex1)
      exchange_repo.complete_exchange(exchange_id: ex2)
      exchange_repo.complete_exchange(exchange_id: ex3)

      # Get unsummarized exchanges excluding current conversation
      unsummarized = exchange_repo.get_unsummarized_exchanges(exclude_conversation_id: conversation_id)

      expect(unsummarized.length).to eq(2)
      expect(unsummarized[0]["id"]).to eq(ex1)
      expect(unsummarized[1]["id"]).to eq(ex2)
      expect(unsummarized[0]["conversation_id"]).to eq(other_conversation_id)
    end

    it "excludes exchanges that already have summaries" do
      other_conversation_id = conversation_repo.create_conversation

      ex1 = exchange_repo.create_exchange(conversation_id: other_conversation_id, user_message: "Question 1")
      ex2 = exchange_repo.create_exchange(conversation_id: other_conversation_id, user_message: "Question 2")

      exchange_repo.complete_exchange(exchange_id: ex1, summary: "Already summarized")
      exchange_repo.complete_exchange(exchange_id: ex2)

      unsummarized = exchange_repo.get_unsummarized_exchanges(exclude_conversation_id: conversation_id)

      expect(unsummarized.length).to eq(1)
      expect(unsummarized[0]["id"]).to eq(ex2)
    end

    it "excludes exchanges that are not completed" do
      other_conversation_id = conversation_repo.create_conversation

      exchange_repo.create_exchange(conversation_id: other_conversation_id, user_message: "In progress")

      unsummarized = exchange_repo.get_unsummarized_exchanges(exclude_conversation_id: conversation_id)

      expect(unsummarized).to be_empty
    end
  end

  describe "#update_exchange_summary" do
    let(:exchange_id) do
      ex_id = exchange_repo.create_exchange(conversation_id: conversation_id, user_message: "Question")
      exchange_repo.complete_exchange(exchange_id: ex_id)
      ex_id
    end

    it "updates summary and model" do
      exchange_repo.update_exchange_summary(
        exchange_id: exchange_id,
        summary: "This is a summary",
        model: "gpt-4"
      )

      result = connection.query("SELECT summary, summary_model FROM exchanges WHERE id = #{exchange_id}")
      row = result.to_a.first

      expect(row[0]).to eq("This is a summary")
      expect(row[1]).to eq("gpt-4")
    end

    it "updates cost when provided" do
      exchange_repo.update_exchange_summary(
        exchange_id: exchange_id,
        summary: "Summary with cost",
        model: "gpt-4",
        cost: 0.025
      )

      result = connection.query("SELECT summary, summary_model, spend FROM exchanges WHERE id = #{exchange_id}")
      row = result.to_a.first

      expect(row[0]).to eq("Summary with cost")
      expect(row[1]).to eq("gpt-4")
      expect(row[2]).to be_within(0.001).of(0.025)
    end

    it "does not update cost when nil" do
      exchange_repo.update_exchange_summary(
        exchange_id: exchange_id,
        summary: "Summary without cost",
        model: "gpt-4",
        cost: nil
      )

      result = connection.query("SELECT summary, summary_model, spend FROM exchanges WHERE id = #{exchange_id}")
      row = result.to_a.first

      expect(row[0]).to eq("Summary without cost")
      expect(row[1]).to eq("gpt-4")
      expect(row[2]).to be_nil
    end
  end
end
