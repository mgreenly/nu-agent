# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe Nu::Agent::MessageRepository do
  let(:test_db_path) { "db/test_message_repository.db" }
  let(:db) { DuckDB::Database.open(test_db_path) }
  let(:connection) { db.connect }
  let(:schema_manager) { Nu::Agent::SchemaManager.new(connection) }
  let(:message_repo) { described_class.new(connection) }

  before do
    FileUtils.rm_rf(test_db_path)
    FileUtils.mkdir_p("db")
    schema_manager.setup_schema
    # Create a test conversation to satisfy foreign key constraints
    connection.query("INSERT INTO conversations (id, created_at) VALUES (1, '2025-01-01 00:00:00')")
    # Create a test exchange to satisfy foreign key constraints
    connection.query(<<~SQL)
      INSERT INTO exchanges (id, conversation_id, exchange_number, started_at)
      VALUES (1, 1, 1, '2025-01-01 00:00:00')
    SQL
  end

  after do
    connection.close
    db.close
    FileUtils.rm_rf(test_db_path)
  end

  describe "#add_message" do
    let(:conversation_id) { 1 }

    it "adds a message with required fields" do
      message_repo.add_message(
        conversation_id: conversation_id,
        actor: "user",
        role: "user",
        content: "Hello world"
      )

      result = connection.query("SELECT * FROM messages WHERE conversation_id = #{conversation_id}")
      rows = result.to_a
      expect(rows.length).to eq(1)
      expect(rows.first[2]).to eq("user") # actor
      expect(rows.first[3]).to eq("user") # role
      expect(rows.first[4]).to eq("Hello world") # content
    end

    it "adds a message with optional attributes" do
      message_repo.add_message(
        conversation_id: conversation_id,
        actor: "assistant",
        role: "assistant",
        content: "Response",
        model: "claude-3-5-sonnet-20241022",
        tokens_input: 100,
        tokens_output: 50,
        spend: 0.005
      )

      result = connection.query(
        "SELECT model, tokens_input, tokens_output, spend FROM messages WHERE conversation_id = #{conversation_id}"
      )
      row = result.to_a.first
      expect(row[0]).to eq("claude-3-5-sonnet-20241022")
      expect(row[1]).to eq(100)
      expect(row[2]).to eq(50)
      expect(row[3]).to be_within(0.001).of(0.005)
    end

    it "adds a message with tool_calls" do
      tool_calls = [{ "name" => "file_read", "arguments" => { "file" => "test.txt" } }]

      message_repo.add_message(
        conversation_id: conversation_id,
        actor: "assistant",
        role: "assistant",
        content: nil,
        tool_calls: tool_calls
      )

      result = connection.query("SELECT tool_calls FROM messages WHERE conversation_id = #{conversation_id}")
      tool_calls_json = result.to_a.first[0]
      expect(JSON.parse(tool_calls_json)).to eq(tool_calls)
    end

    it "adds a message with tool_result" do
      tool_result = { "status" => "success", "content" => "file contents" }

      message_repo.add_message(
        conversation_id: conversation_id,
        actor: "tool",
        role: "tool",
        content: "result",
        tool_call_id: "call_123",
        tool_result: tool_result
      )

      result = connection.query(
        "SELECT tool_call_id, tool_result FROM messages WHERE conversation_id = #{conversation_id}"
      )
      row = result.to_a.first
      expect(row[0]).to eq("call_123")
      expect(JSON.parse(row[1])).to eq(tool_result)
    end
  end

  describe "#messages" do
    let(:conversation_id) { 1 }

    before do
      message_repo.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "First",
                               include_in_context: true)
      message_repo.add_message(conversation_id: conversation_id, actor: "assistant", role: "assistant",
                               content: "Second", include_in_context: true)
      message_repo.add_message(conversation_id: conversation_id, actor: "tool", role: "tool", content: "Third",
                               include_in_context: false)
    end

    it "retrieves all messages in order" do
      msgs = message_repo.messages(conversation_id: conversation_id, include_in_context_only: false)

      expect(msgs.length).to eq(3)
      expect(msgs[0]["content"]).to eq("First")
      expect(msgs[1]["content"]).to eq("Second")
      expect(msgs[2]["content"]).to eq("Third")
    end

    it "filters by include_in_context" do
      msgs = message_repo.messages(conversation_id: conversation_id, include_in_context_only: true)

      expect(msgs.length).to eq(2)
      expect(msgs[0]["content"]).to eq("First")
      expect(msgs[1]["content"]).to eq("Second")
    end

    it "filters by since timestamp" do
      sleep(0.01) # Small delay to ensure time difference
      since_time = Time.now
      sleep(0.01)

      message_repo.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "Fourth")

      msgs = message_repo.messages(conversation_id: conversation_id, include_in_context_only: false, since: since_time)

      expect(msgs.length).to eq(1)
      expect(msgs[0]["content"]).to eq("Fourth")
    end
  end

  describe "#messages_since" do
    let(:conversation_id) { 1 }

    it "retrieves messages after a specific message_id" do
      message_repo.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "First")
      message_repo.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "Second")

      result = connection.query("SELECT id FROM messages WHERE content = 'First'")
      first_id = result.to_a.first[0]

      msgs = message_repo.messages_since(conversation_id: conversation_id, message_id: first_id)

      expect(msgs.length).to eq(1)
      expect(msgs[0]["content"]).to eq("Second")
    end
  end

  describe "#session_tokens" do
    let(:conversation_id) { 1 }

    it "calculates token statistics" do
      since_time = Time.now
      sleep(0.01) # Ensure messages are after since_time

      message_repo.add_message(
        conversation_id: conversation_id,
        actor: "assistant",
        role: "assistant",
        content: "Response",
        tokens_input: 100,
        tokens_output: 50,
        spend: 0.005
      )

      message_repo.add_message(
        conversation_id: conversation_id,
        actor: "assistant",
        role: "assistant",
        content: "Another",
        tokens_input: 150,
        tokens_output: 75,
        spend: 0.008
      )

      stats = message_repo.session_tokens(conversation_id: conversation_id, since: since_time)

      expect(stats["input"]).to eq(150) # MAX of inputs
      expect(stats["output"]).to eq(125) # SUM of outputs (50 + 75)
      expect(stats["total"]).to eq(275) # 150 + 125
      expect(stats["spend"]).to be_within(0.001).of(0.013) # 0.005 + 0.008
    end
  end

  describe "#current_context_size" do
    let(:conversation_id) { 1 }
    let(:model) { "claude-3-5-sonnet-20241022" }

    it "returns the most recent tokens_input for a model" do
      since_time = Time.now
      sleep(0.01) # Ensure messages are after since_time

      message_repo.add_message(
        conversation_id: conversation_id,
        actor: "assistant",
        role: "assistant",
        content: "First",
        model: model,
        tokens_input: 100
      )

      message_repo.add_message(
        conversation_id: conversation_id,
        actor: "assistant",
        role: "assistant",
        content: "Second",
        model: model,
        tokens_input: 150
      )

      size = message_repo.current_context_size(conversation_id: conversation_id, since: since_time, model: model)

      expect(size).to eq(150)
    end

    it "returns 0 when no matching messages found" do
      since_time = Time.now

      size = message_repo.current_context_size(conversation_id: conversation_id, since: since_time,
                                               model: "nonexistent")

      expect(size).to eq(0)
    end
  end

  describe "#get_message_by_id" do
    let(:conversation_id) { 1 }

    it "retrieves a specific message" do
      message_repo.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "Test message")

      result = connection.query("SELECT id FROM messages WHERE conversation_id = #{conversation_id}")
      message_id = result.to_a.first[0]

      msg = message_repo.get_message_by_id(message_id, conversation_id: conversation_id)

      expect(msg).not_to be_nil
      expect(msg["id"]).to eq(message_id)
      expect(msg["content"]).to eq("Test message")
    end

    it "returns nil for non-existent message" do
      msg = message_repo.get_message_by_id(99_999, conversation_id: conversation_id)

      expect(msg).to be_nil
    end
  end

  describe "#update_message_exchange_id" do
    let(:conversation_id) { 1 }
    let(:exchange_id) { 42 }

    it "updates the exchange_id of a message" do
      # Create the exchange that we'll reference
      connection.query(<<~SQL)
        INSERT INTO exchanges (id, conversation_id, exchange_number, started_at)
        VALUES (#{exchange_id}, #{conversation_id}, 2, '2025-01-01 00:00:00')
      SQL

      message_repo.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "Test")

      result = connection.query("SELECT id FROM messages WHERE conversation_id = #{conversation_id}")
      message_id = result.to_a.first[0]

      message_repo.update_message_exchange_id(message_id: message_id, exchange_id: exchange_id)

      result = connection.query("SELECT exchange_id FROM messages WHERE id = #{message_id}")
      updated_exchange_id = result.to_a.first[0]
      expect(updated_exchange_id).to eq(exchange_id)
    end
  end

  describe "#get_exchange_messages" do
    let(:conversation_id) { 1 }
    let(:exchange_id) { 10 }

    it "retrieves all messages for a specific exchange" do
      # Create the exchanges we'll reference
      connection.query(<<~SQL)
        INSERT INTO exchanges (id, conversation_id, exchange_number, started_at)
        VALUES (#{exchange_id}, #{conversation_id}, 2, '2025-01-01 00:00:00')
      SQL
      connection.query(<<~SQL)
        INSERT INTO exchanges (id, conversation_id, exchange_number, started_at)
        VALUES (99, #{conversation_id}, 3, '2025-01-01 00:00:00')
      SQL

      message_repo.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "First",
                               exchange_id: exchange_id)
      message_repo.add_message(conversation_id: conversation_id, actor: "assistant", role: "assistant",
                               content: "Second", exchange_id: exchange_id)
      # different exchange
      message_repo.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "Third",
                               exchange_id: 99)

      msgs = message_repo.get_exchange_messages(exchange_id: exchange_id)

      expect(msgs.length).to eq(2)
      expect(msgs[0]["content"]).to eq("First")
      expect(msgs[1]["content"]).to eq("Second")
    end
  end
end
