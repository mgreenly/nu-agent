# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe Nu::Agent::ConversationRepository do
  let(:test_db_path) { "db/test_conversation_repository.db" }
  let(:db) { DuckDB::Database.open(test_db_path) }
  let(:connection) { db.connect }
  let(:schema_manager) { Nu::Agent::SchemaManager.new(connection) }
  let(:conversation_repo) { described_class.new(connection) }

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

  describe "#create_conversation" do
    it "creates a new conversation and returns its id" do
      conversation_id = conversation_repo.create_conversation

      expect(conversation_id).to be_a(Integer)
      expect(conversation_id).to be > 0
    end

    it "creates conversation with default values" do
      conversation_id = conversation_repo.create_conversation

      result = connection.query("SELECT title, status FROM conversations WHERE id = #{conversation_id}")
      row = result.to_a.first

      expect(row[0]).to eq("New Conversation")
      expect(row[1]).to eq("active")
    end
  end

  describe "#update_conversation_summary" do
    let(:conversation_id) { conversation_repo.create_conversation }

    it "updates conversation summary fields" do
      conversation_repo.update_conversation_summary(
        conversation_id: conversation_id,
        summary: "Test summary",
        model: "claude-3-5-sonnet-20241022",
        cost: 0.05
      )

      result = connection.query("SELECT summary, summary_model, summary_cost FROM conversations WHERE id = #{conversation_id}")
      row = result.to_a.first

      expect(row[0]).to eq("Test summary")
      expect(row[1]).to eq("claude-3-5-sonnet-20241022")
      expect(row[2]).to be_within(0.001).of(0.05)
    end

    it "updates summary without cost" do
      conversation_repo.update_conversation_summary(
        conversation_id: conversation_id,
        summary: "Another summary",
        model: "claude-opus"
      )

      result = connection.query("SELECT summary, summary_model, summary_cost FROM conversations WHERE id = #{conversation_id}")
      row = result.to_a.first

      expect(row[0]).to eq("Another summary")
      expect(row[1]).to eq("claude-opus")
      expect(row[2]).to be_nil
    end
  end

  describe "#all_conversations" do
    it "returns empty array when no conversations exist" do
      conversations = conversation_repo.all_conversations

      expect(conversations).to eq([])
    end

    it "returns all conversations in order" do
      id1 = conversation_repo.create_conversation
      id2 = conversation_repo.create_conversation
      id3 = conversation_repo.create_conversation

      conversations = conversation_repo.all_conversations

      expect(conversations.length).to eq(3)
      expect(conversations[0]["id"]).to eq(id1)
      expect(conversations[1]["id"]).to eq(id2)
      expect(conversations[2]["id"]).to eq(id3)
      expect(conversations[0]["title"]).to eq("New Conversation")
      expect(conversations[0]["status"]).to eq("active")
    end
  end

  describe "#get_unsummarized_conversations" do
    it "returns conversations without summary, excluding current" do
      conv1 = conversation_repo.create_conversation
      conv2 = conversation_repo.create_conversation
      conv3 = conversation_repo.create_conversation

      # Add summary to conv2
      conversation_repo.update_conversation_summary(
        conversation_id: conv2,
        summary: "Has summary",
        model: "claude"
      )

      # Get unsummarized, excluding conv1
      result = conversation_repo.get_unsummarized_conversations(exclude_id: conv1)

      expect(result.length).to eq(1)
      expect(result[0]["id"]).to eq(conv3)
    end

    it "returns conversations in reverse chronological order" do
      conv1 = conversation_repo.create_conversation
      conv2 = conversation_repo.create_conversation
      conv3 = conversation_repo.create_conversation

      result = conversation_repo.get_unsummarized_conversations(exclude_id: 0)

      expect(result.length).to eq(3)
      expect(result[0]["id"]).to eq(conv3) # Most recent first
      expect(result[1]["id"]).to eq(conv2)
      expect(result[2]["id"]).to eq(conv1)
    end
  end
end
