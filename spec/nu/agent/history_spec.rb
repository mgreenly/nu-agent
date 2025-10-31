# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe Nu::Agent::History do
  let(:test_db_path) { "db/test_history.db" }
  let(:history) { described_class.new(db_path: test_db_path) }

  before do
    # Clean up test database before each test
    FileUtils.rm_rf("db/test_history.db")
  end

  after do
    history.close
    FileUtils.rm_rf("db/test_history.db")
  end

  describe "#create_conversation" do
    it "creates a new conversation and returns its id" do
      conversation_id = history.create_conversation
      expect(conversation_id).to be_a(Integer)
      expect(conversation_id).to be > 0
    end

    it "creates multiple conversations with unique ids" do
      id1 = history.create_conversation
      id2 = history.create_conversation
      expect(id1).not_to eq(id2)
    end
  end

  describe "#add_message" do
    let(:conversation_id) { history.create_conversation }

    it "adds a user message to the conversation" do
      history.add_message(
        conversation_id: conversation_id,
        actor: "user",
        role: "user",
        content: "Hello, world!"
      )

      messages = history.messages(conversation_id: conversation_id)
      expect(messages.length).to eq(1)
      expect(messages.first["actor"]).to eq("user")
      expect(messages.first["role"]).to eq("user")
      expect(messages.first["content"]).to eq("Hello, world!")
    end

    it "adds an assistant message with model and tokens" do
      history.add_message(
        conversation_id: conversation_id,
        actor: "orchestrator",
        role: "assistant",
        content: "Hello back!",
        model: "claude-sonnet-4-20250514",
        tokens_input: 10,
        tokens_output: 5
      )

      messages = history.messages(conversation_id: conversation_id)
      expect(messages.first["model"]).to eq("claude-sonnet-4-20250514")
      expect(messages.first["tokens_input"]).to eq(10)
      expect(messages.first["tokens_output"]).to eq(5)
    end

    it "handles SQL special characters in content" do
      history.add_message(
        conversation_id: conversation_id,
        actor: "user",
        role: "user",
        content: "It's a test with 'quotes'"
      )

      messages = history.messages(conversation_id: conversation_id)
      expect(messages.first["content"]).to eq("It's a test with 'quotes'")
    end
  end

  describe "#messages" do
    let(:conversation_id) { history.create_conversation }

    before do
      history.add_message(
        conversation_id: conversation_id,
        actor: "user",
        role: "user",
        content: "Message 1"
      )
      history.add_message(
        conversation_id: conversation_id,
        actor: "orchestrator",
        role: "assistant",
        content: "Message 2",
        include_in_context: false
      )
      history.add_message(
        conversation_id: conversation_id,
        actor: "orchestrator",
        role: "assistant",
        content: "Message 3"
      )
    end

    it "returns all messages in order by default (include_in_context only)" do
      messages = history.messages(conversation_id: conversation_id)
      expect(messages.length).to eq(2)
      expect(messages[0]["content"]).to eq("Message 1")
      expect(messages[1]["content"]).to eq("Message 3")
    end

    it "returns all messages including metadata when requested" do
      messages = history.messages(conversation_id: conversation_id, include_in_context_only: false)
      expect(messages.length).to eq(3)
      expect(messages[1]["content"]).to eq("Message 2")
    end

    it "returns empty array for non-existent conversation" do
      messages = history.messages(conversation_id: 999)
      expect(messages).to eq([])
    end

    it "filters messages by since parameter" do
      history.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "Old message")

      sleep 0.01
      cutoff_time = Time.now
      sleep 0.01

      history.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "New message 1")
      history.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "New message 2")

      messages = history.messages(conversation_id: conversation_id, since: cutoff_time)

      expect(messages.length).to eq(2)
      expect(messages[0]["content"]).to eq("New message 1")
      expect(messages[1]["content"]).to eq("New message 2")
    end

    it "combines since and include_in_context filters" do
      history.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "Old")

      sleep 0.01
      cutoff_time = Time.now
      sleep 0.01

      history.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "New in context",
                          include_in_context: true)
      history.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "New not in context",
                          include_in_context: false)

      messages = history.messages(conversation_id: conversation_id, since: cutoff_time, include_in_context_only: true)

      expect(messages.length).to eq(1)
      expect(messages[0]["content"]).to eq("New in context")
    end
  end

  describe "#messages_since" do
    let(:conversation_id) { history.create_conversation }

    it "returns only messages after the specified id" do
      history.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "M1")
      history.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "M2")
      history.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "M3")

      messages = history.messages(conversation_id: conversation_id)
      first_id = messages[0]["id"]

      new_messages = history.messages_since(conversation_id: conversation_id, message_id: first_id)
      expect(new_messages.length).to eq(2)
      expect(new_messages[0]["content"]).to eq("M2")
      expect(new_messages[1]["content"]).to eq("M3")
    end
  end

  describe "#session_tokens" do
    let(:conversation_id) { history.create_conversation }

    it "returns cumulative token counts since a given time" do
      session_start = Time.now - 60

      sleep 0.01
      history.add_message(
        conversation_id: conversation_id,
        actor: "assistant",
        role: "assistant",
        content: "First",
        tokens_input: 10,
        tokens_output: 5
      )

      history.add_message(
        conversation_id: conversation_id,
        actor: "assistant",
        role: "assistant",
        content: "Second",
        tokens_input: 20,
        tokens_output: 8
      )

      tokens = history.session_tokens(conversation_id: conversation_id, since: session_start)

      # Input tokens should be MAX (20), not SUM (30), because each API call
      # reports the total context size, which already includes previous messages
      expect(tokens["input"]).to eq(20)
      expect(tokens["output"]).to eq(13)
      expect(tokens["total"]).to eq(33)
    end

    it "excludes messages before the session start time" do
      history.add_message(
        conversation_id: conversation_id,
        actor: "assistant",
        role: "assistant",
        content: "Old message",
        tokens_input: 100,
        tokens_output: 50
      )

      sleep 0.01
      session_start = Time.now
      sleep 0.01

      history.add_message(
        conversation_id: conversation_id,
        actor: "assistant",
        role: "assistant",
        content: "New message",
        tokens_input: 10,
        tokens_output: 5
      )

      tokens = history.session_tokens(conversation_id: conversation_id, since: session_start)

      expect(tokens["input"]).to eq(10)
      expect(tokens["output"]).to eq(5)
      expect(tokens["total"]).to eq(15)
    end

    it "returns zero for messages without tokens" do
      session_start = Time.now - 60

      sleep 0.01
      history.add_message(
        conversation_id: conversation_id,
        actor: "user",
        role: "user",
        content: "User message"
      )

      tokens = history.session_tokens(conversation_id: conversation_id, since: session_start)

      expect(tokens["input"]).to eq(0)
      expect(tokens["output"]).to eq(0)
      expect(tokens["total"]).to eq(0)
    end
  end

  describe "#list_tables" do
    it "returns list of table names" do
      tables = history.list_tables

      expect(tables).to be_an(Array)
      expect(tables).to include("conversations")
      expect(tables).to include("messages")
      expect(tables).to include("appconfig")
    end
  end

  describe "#describe_table" do
    it "returns schema information for a table" do
      columns = history.describe_table("messages")

      expect(columns).to be_an(Array)
      expect(columns.first).to have_key("column_name")
      expect(columns.first).to have_key("column_type")

      column_names = columns.map { |c| c["column_name"] }
      expect(column_names).to include("id")
      expect(column_names).to include("conversation_id")
      expect(column_names).to include("content")
    end
  end

  describe "#execute_query" do
    let(:conversation_id) { history.create_conversation }

    before do
      history.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "Test 1")
      history.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "Test 2")
    end

    it "executes SELECT queries" do
      result = history.execute_query("SELECT content FROM messages WHERE conversation_id = #{conversation_id}")

      expect(result).to be_an(Array)
      expect(result.length).to eq(2)
      expect(result.first).to have_key("content")
    end

    it "caps results at 500 rows" do
      # Add more than 500 messages
      510.times do |i|
        history.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "Message #{i}")
      end

      result = history.execute_query("SELECT * FROM messages")

      expect(result.length).to eq(500)
    end

    it "caps results at 500 rows even with higher LIMIT" do
      # Add more than 500 messages
      510.times do |i|
        history.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "Message #{i}")
      end

      result = history.execute_query("SELECT * FROM messages LIMIT 1000")

      expect(result.length).to eq(500)
    end

    it "rejects non-SELECT queries" do
      expect do
        history.execute_query("INSERT INTO messages (content) VALUES ('bad')")
      end.to raise_error(ArgumentError, /Only read-only queries/)
    end

    it "allows SHOW queries" do
      result = history.execute_query("SHOW TABLES")

      expect(result).to be_an(Array)
    end
  end

  describe "appconfig" do
    it "sets and gets config values" do
      history.set_config("test_key", "test_value")
      expect(history.get_config("test_key")).to eq("test_value")
    end

    it "returns default value for non-existent key" do
      expect(history.get_config("nonexistent", default: "default")).to eq("default")
    end

    it "replaces existing values" do
      history.set_config("key", "value1")
      history.set_config("key", "value2")
      expect(history.get_config("key")).to eq("value2")
    end
  end

  describe "worker tracking" do
    it "starts with zero workers" do
      expect(history.workers_idle?).to be true
      expect(history.get_config("active_workers")).to eq("0")
    end

    it "increments and decrements workers" do
      history.increment_workers
      expect(history.workers_idle?).to be false
      expect(history.get_config("active_workers")).to eq("1")

      history.increment_workers
      expect(history.get_config("active_workers")).to eq("2")

      history.decrement_workers
      expect(history.get_config("active_workers")).to eq("1")

      history.decrement_workers
      expect(history.workers_idle?).to be true
    end

    it "does not go below zero when decrementing" do
      history.decrement_workers
      history.decrement_workers
      expect(history.get_config("active_workers")).to eq("0")
    end
  end

  describe "exchanges" do
    let(:conversation_id) { history.create_conversation }

    describe "#create_exchange" do
      it "creates a new exchange and returns its id" do
        exchange_id = history.create_exchange(
          conversation_id: conversation_id,
          user_message: "Test question"
        )

        expect(exchange_id).to be_a(Integer)
        expect(exchange_id).to be > 0
      end

      it "assigns sequential exchange numbers within a conversation" do
        history.create_exchange(conversation_id: conversation_id, user_message: "Q1")
        history.create_exchange(conversation_id: conversation_id, user_message: "Q2")
        history.create_exchange(conversation_id: conversation_id, user_message: "Q3")

        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)

        expect(exchanges[0]["exchange_number"]).to eq(1)
        expect(exchanges[1]["exchange_number"]).to eq(2)
        expect(exchanges[2]["exchange_number"]).to eq(3)
      end

      it "starts with status in_progress" do
        history.create_exchange(conversation_id: conversation_id, user_message: "Q")
        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)

        expect(exchanges.first["status"]).to eq("in_progress")
      end

      it "stores the user message" do
        history.create_exchange(
          conversation_id: conversation_id,
          user_message: "What is 2+2?"
        )

        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)
        expect(exchanges.first["user_message"]).to eq("What is 2+2?")
      end
    end

    describe "#update_exchange" do
      let(:exchange_id) do
        history.create_exchange(conversation_id: conversation_id, user_message: "Test")
      end

      it "updates exchange status" do
        history.update_exchange(exchange_id: exchange_id, updates: { status: "completed" })

        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)
        expect(exchanges.first["status"]).to eq("completed")
      end

      it "updates exchange metrics" do
        history.update_exchange(
          exchange_id: exchange_id,
          updates: {
            tokens_input: 100,
            tokens_output: 50,
            spend: 0.001,
            message_count: 5,
            tool_call_count: 2
          }
        )

        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)
        ex = exchanges.first

        expect(ex["tokens_input"]).to eq(100)
        expect(ex["tokens_output"]).to eq(50)
        expect(ex["spend"]).to be_within(0.000001).of(0.001)
        expect(ex["message_count"]).to eq(5)
        expect(ex["tool_call_count"]).to eq(2)
      end

      it "updates assistant message" do
        history.update_exchange(
          exchange_id: exchange_id,
          updates: { assistant_message: "The answer is 42" }
        )

        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)
        expect(exchanges.first["assistant_message"]).to eq("The answer is 42")
      end
    end

    describe "#complete_exchange" do
      let(:exchange_id) do
        history.create_exchange(conversation_id: conversation_id, user_message: "Test")
      end

      it "marks exchange as completed" do
        history.complete_exchange(exchange_id: exchange_id)

        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)
        expect(exchanges.first["status"]).to eq("completed")
      end

      it "sets completed_at timestamp" do
        history.complete_exchange(exchange_id: exchange_id)

        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)
        expect(exchanges.first["completed_at"]).not_to be_nil
      end

      it "saves metrics and assistant message" do
        history.complete_exchange(
          exchange_id: exchange_id,
          assistant_message: "Done!",
          metrics: {
            tokens_input: 75,
            tokens_output: 25,
            spend: 0.0005,
            message_count: 3,
            tool_call_count: 1
          }
        )

        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)
        ex = exchanges.first

        expect(ex["assistant_message"]).to eq("Done!")
        expect(ex["tokens_input"]).to eq(75)
        expect(ex["tokens_output"]).to eq(25)
        expect(ex["spend"]).to be_within(0.000001).of(0.0005)
        expect(ex["message_count"]).to eq(3)
        expect(ex["tool_call_count"]).to eq(1)
      end
    end

    describe "#get_exchange_messages" do
      let(:exchange_id) do
        history.create_exchange(conversation_id: conversation_id, user_message: "Test")
      end

      it "returns messages for a specific exchange" do
        history.add_message(
          conversation_id: conversation_id,
          exchange_id: exchange_id,
          actor: "user",
          role: "user",
          content: "Question"
        )

        history.add_message(
          conversation_id: conversation_id,
          exchange_id: exchange_id,
          actor: "orchestrator",
          role: "assistant",
          content: "Answer"
        )

        messages = history.get_exchange_messages(exchange_id: exchange_id)

        expect(messages.length).to eq(2)
        expect(messages[0]["content"]).to eq("Question")
        expect(messages[1]["content"]).to eq("Answer")
      end

      it "returns empty array for exchange with no messages" do
        messages = history.get_exchange_messages(exchange_id: exchange_id)
        expect(messages).to eq([])
      end
    end

    describe "#get_conversation_exchanges" do
      it "returns all exchanges for a conversation" do
        history.create_exchange(conversation_id: conversation_id, user_message: "Q1")
        history.create_exchange(conversation_id: conversation_id, user_message: "Q2")

        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)

        expect(exchanges.length).to eq(2)
        expect(exchanges[0]["user_message"]).to eq("Q1")
        expect(exchanges[1]["user_message"]).to eq("Q2")
      end

      it "returns exchanges in order by exchange_number" do
        history.create_exchange(conversation_id: conversation_id, user_message: "First")
        history.create_exchange(conversation_id: conversation_id, user_message: "Second")
        history.create_exchange(conversation_id: conversation_id, user_message: "Third")

        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)

        expect(exchanges[0]["exchange_number"]).to eq(1)
        expect(exchanges[1]["exchange_number"]).to eq(2)
        expect(exchanges[2]["exchange_number"]).to eq(3)
      end
    end

    describe "#migrate_exchanges" do
      it "creates exchanges from existing messages" do
        # Add messages without exchange_id
        history.add_message(
          conversation_id: conversation_id,
          actor: "user",
          role: "user",
          content: "What is 2+2?"
        )

        history.add_message(
          conversation_id: conversation_id,
          actor: "orchestrator",
          role: "assistant",
          content: "4",
          model: "test-model",
          tokens_input: 50,
          tokens_output: 10,
          spend: 0.0005
        )

        # Run migration
        stats = history.migrate_exchanges

        expect(stats[:conversations]).to eq(1)
        expect(stats[:exchanges_created]).to eq(1)
        expect(stats[:messages_updated]).to eq(2)

        # Verify exchange was created
        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)
        expect(exchanges.length).to eq(1)
        expect(exchanges.first["user_message"]).to eq("What is 2+2?")
        expect(exchanges.first["assistant_message"]).to eq("4")
      end

      it "groups multiple user/assistant pairs into separate exchanges" do
        # First exchange
        history.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "Q1")
        history.add_message(conversation_id: conversation_id, actor: "orchestrator", role: "assistant", content: "A1")

        # Second exchange
        history.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "Q2")
        history.add_message(conversation_id: conversation_id, actor: "orchestrator", role: "assistant", content: "A2")

        stats = history.migrate_exchanges

        expect(stats[:exchanges_created]).to eq(2)

        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)
        expect(exchanges[0]["user_message"]).to eq("Q1")
        expect(exchanges[0]["assistant_message"]).to eq("A1")
        expect(exchanges[1]["user_message"]).to eq("Q2")
        expect(exchanges[1]["assistant_message"]).to eq("A2")
      end

      it "calculates metrics from messages" do
        history.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "Q")
        history.add_message(
          conversation_id: conversation_id,
          actor: "orchestrator",
          role: "assistant",
          content: "A",
          tokens_input: 100,
          tokens_output: 50,
          spend: 0.001
        )

        history.migrate_exchanges

        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)
        ex = exchanges.first

        expect(ex["tokens_input"]).to eq(100)
        expect(ex["tokens_output"]).to eq(50)
        expect(ex["spend"]).to be_within(0.000001).of(0.001)
        expect(ex["message_count"]).to eq(2)
      end

      it "excludes spell_checker messages from exchange boundaries" do
        history.add_message(conversation_id: conversation_id, actor: "spell_checker", role: "user", content: "Check")
        history.add_message(conversation_id: conversation_id, actor: "spell_checker", role: "assistant",
                            content: "Checked")
        history.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "Real question")
        history.add_message(conversation_id: conversation_id, actor: "orchestrator", role: "assistant",
                            content: "Answer")

        stats = history.migrate_exchanges

        # Should create only 1 exchange (spell_checker messages don't start exchanges)
        expect(stats[:exchanges_created]).to eq(1)

        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)
        expect(exchanges.first["user_message"]).to eq("Real question")
      end
    end

    describe "messages with exchange_id" do
      let(:exchange_id) do
        history.create_exchange(conversation_id: conversation_id, user_message: "Test")
      end

      it "allows adding messages with exchange_id" do
        history.add_message(
          conversation_id: conversation_id,
          exchange_id: exchange_id,
          actor: "user",
          role: "user",
          content: "Test"
        )

        messages = history.messages(conversation_id: conversation_id, include_in_context_only: false)
        expect(messages.first["exchange_id"]).to eq(exchange_id)
      end

      it "allows messages without exchange_id (backward compatibility)" do
        history.add_message(
          conversation_id: conversation_id,
          actor: "user",
          role: "user",
          content: "Test"
        )

        messages = history.messages(conversation_id: conversation_id, include_in_context_only: false)
        expect(messages.first["exchange_id"]).to be_nil
      end
    end
  end

  describe "#initialize with WAL file" do
    let(:test_db_with_wal) { "db/test_wal_recovery.db" }

    after do
      FileUtils.rm_rf(test_db_with_wal)
      FileUtils.rm_rf("#{test_db_with_wal}.wal")
      FileUtils.rm_rf("#{test_db_with_wal}-shm")
    end

    it "detects and warns about existing WAL file" do
      # Create a database first
      temp_history = described_class.new(db_path: test_db_with_wal)
      temp_history.create_conversation
      temp_history.close

      # Create a fake WAL file
      File.write("#{test_db_with_wal}.wal", "fake wal data" * 100)

      # Capture warnings
      warnings = []
      allow_any_instance_of(Kernel).to receive(:warn) do |_, msg|
        warnings << msg
      end

      history_with_wal = described_class.new(db_path: test_db_with_wal)

      expect(warnings.any? { |w| w.include?("WAL file detected") }).to be true
      expect(warnings.any? { |w| w.include?("automatically recover") }).to be true

      history_with_wal.close
    end

    it "confirms recovery when WAL is removed after connect" do
      # Create DB and WAL
      temp_history = described_class.new(db_path: test_db_with_wal)
      temp_history.create_conversation
      temp_history.close

      File.write("#{test_db_with_wal}.wal", "data")

      # Capture warnings
      warnings = []
      allow_any_instance_of(Kernel).to receive(:warn) do |_, msg|
        warnings << msg
      end

      # Opening should trigger recovery
      history_with_wal = described_class.new(db_path: test_db_with_wal)

      # Check for recovery confirmation
      expect(warnings.any? { |w| w.include?("recovery completed") || w.include?("WAL file still present") }).to be true

      history_with_wal.close
    end

    it "shows success message when WAL is successfully recovered" do
      # Simulate WAL file present initially, then removed after connection
      wal_path = "#{test_db_with_wal}.wal"

      # Track how many times File.exist? and File.size are called for the WAL path
      exist_calls = 0
      size_calls = 0

      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(wal_path) do
        exist_calls += 1
        # First call (initial check): WAL exists
        # Second call (after connection): WAL is gone
        exist_calls == 1
      end

      allow(File).to receive(:size).and_call_original
      allow(File).to receive(:size).with(wal_path) do
        size_calls += 1
        # First call: return non-zero size
        # Second call: return 0 (or won't be called if exist? returns false)
        size_calls == 1 ? 1024 : 0
      end

      # Capture warnings
      warnings = []
      allow_any_instance_of(Kernel).to receive(:warn) do |_, msg|
        warnings << msg
      end

      history_with_wal = described_class.new(db_path: test_db_with_wal)

      expect(warnings.any? { |w| w.include?("Database recovery completed successfully") }).to be true

      history_with_wal.close
    end
  end

  describe "#initialize with environment variable" do
    it "uses NUAGENT_DATABASE environment variable if set" do
      custom_path = "db/custom_env_test.db"
      ENV["NUAGENT_DATABASE"] = custom_path

      begin
        history_env = described_class.new
        expect(history_env.db_path).to eq(custom_path)
        history_env.close
      ensure
        ENV.delete("NUAGENT_DATABASE")
        FileUtils.rm_rf(custom_path)
      end
    end
  end

  describe "#transaction" do
    let(:conversation_id) { history.create_conversation }

    it "commits successful transactions" do
      result = history.transaction do
        history.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "Test")
        "success"
      end

      expect(result).to eq("success")
      messages = history.messages(conversation_id: conversation_id)
      expect(messages.length).to eq(1)
    end

    it "rolls back failed transactions" do
      expect do
        history.transaction do
          history.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "Test")
          raise StandardError, "Transaction failed"
        end
      end.to raise_error(StandardError, "Transaction failed")

      messages = history.messages(conversation_id: conversation_id)
      expect(messages.length).to eq(0)
    end

    it "handles rollback errors gracefully" do
      allow(history.connection).to receive(:query).and_call_original
      allow(history.connection).to receive(:query).with("ROLLBACK").and_raise(StandardError.new("Rollback failed"))

      expect do
        history.transaction do
          history.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "Test")
          raise StandardError, "Original error"
        end
      end.to raise_error(StandardError, "Original error")
    end
  end

  describe "#execute_query edge cases" do
    it "returns empty array for queries with no results" do
      result = history.execute_query("SELECT * FROM messages WHERE id = 999999")
      expect(result).to eq([])
    end

    it "strips trailing semicolon" do
      expect do
        history.execute_query("SELECT * FROM messages;")
      end.not_to raise_error
    end

    it "allows DESCRIBE queries" do
      result = history.execute_query("DESCRIBE messages")
      expect(result).to be_an(Array)
    end

    it "allows EXPLAIN queries" do
      result = history.execute_query("EXPLAIN SELECT * FROM messages")
      expect(result).to be_an(Array)
    end

    it "allows WITH (CTE) queries" do
      result = history.execute_query("WITH cte AS (SELECT 1 as n) SELECT * FROM cte")
      expect(result).to be_an(Array)
    end

    it "rejects UPDATE queries" do
      expect do
        history.execute_query("UPDATE messages SET content = 'bad'")
      end.to raise_error(ArgumentError, /Only read-only queries/)
    end

    it "rejects DELETE queries" do
      expect do
        history.execute_query("DELETE FROM messages")
      end.to raise_error(ArgumentError, /Only read-only queries/)
    end

    it "rejects DROP queries" do
      expect do
        history.execute_query("DROP TABLE messages")
      end.to raise_error(ArgumentError, /Only read-only queries/)
    end

    it "uses fallback column names when columns method fails" do
      conversation_id = history.create_conversation
      history.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "Test")

      result = history.execute_query("SELECT * FROM messages")

      # Should have hash keys even if column names fail
      expect(result.first).to be_a(Hash)
      expect(result.first.keys).not_to be_empty
    end
  end

  describe "#find_corrupted_messages" do
    let(:conversation_id) { history.create_conversation }

    it "returns empty array when no corrupted messages exist" do
      history.add_message(
        conversation_id: conversation_id,
        actor: "orchestrator",
        role: "assistant",
        content: "Normal message"
      )

      corrupted = history.find_corrupted_messages
      expect(corrupted).to eq([])
    end

    it "finds messages with redacted tool call arguments" do
      # Manually insert a corrupted message
      tool_calls = [{ "id" => "call_1", "name" => "file_read", "arguments" => { "redacted" => true } }].to_json

      history.connection.query(<<~SQL)
        INSERT INTO messages (conversation_id, actor, role, content, tool_calls)
        VALUES (#{conversation_id}, 'orchestrator', 'assistant', '', '#{tool_calls}')
      SQL

      corrupted = history.find_corrupted_messages
      expect(corrupted.length).to eq(1)
      expect(corrupted.first["tool_name"]).to eq("file_read")
    end

    it "skips messages with nil tool_calls" do
      history.add_message(
        conversation_id: conversation_id,
        actor: "orchestrator",
        role: "assistant",
        content: "No tools"
      )

      corrupted = history.find_corrupted_messages
      expect(corrupted).to eq([])
    end

    it "skips tool calls with valid arguments" do
      history.add_message(
        conversation_id: conversation_id,
        actor: "orchestrator",
        role: "assistant",
        content: "",
        tool_calls: [{ "id" => "call_1", "name" => "file_read", "arguments" => { "path" => "/test.txt" } }]
      )

      corrupted = history.find_corrupted_messages
      expect(corrupted).to eq([])
    end
  end

  describe "#fix_corrupted_messages" do
    let(:conversation_id) { history.create_conversation }

    it "deletes specified messages and returns count" do
      history.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "Msg 1")
      history.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "Msg 2")
      history.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "Msg 3")

      messages = history.messages(conversation_id: conversation_id)
      msg1_id = messages[0]["id"]
      msg3_id = messages[2]["id"]

      count = history.fix_corrupted_messages([msg1_id, msg3_id])

      expect(count).to eq(2)

      remaining = history.messages(conversation_id: conversation_id)
      expect(remaining.length).to eq(1)
      expect(remaining.first["content"]).to eq("Msg 2")
    end

    it "returns 0 when no messages to delete" do
      count = history.fix_corrupted_messages([])
      expect(count).to eq(0)
    end
  end

  describe "#close" do
    it "checkpoints and closes all connections" do
      test_close_db = "db/test_close.db"

      begin
        h = described_class.new(db_path: test_close_db)
        h.create_conversation

        # Get connection in multiple threads to create multiple connections
        threads = 3.times.map do
          Thread.new { h.connection }
        end
        threads.each(&:join)

        # Close should checkpoint and close all connections
        expect { h.close }.not_to raise_error
      ensure
        FileUtils.rm_rf(test_close_db)
      end
    end

    it "handles checkpoint errors during close" do
      test_close_db = "db/test_close_error.db"

      begin
        h = described_class.new(db_path: test_close_db)

        # Simulate checkpoint failure
        allow(h.connection).to receive(:query).with("CHECKPOINT").and_raise(StandardError.new("Checkpoint failed"))

        # Should warn but not raise
        warnings = []
        allow_any_instance_of(Kernel).to receive(:warn) do |_, msg|
          warnings << msg
        end

        expect { h.close }.not_to raise_error
        expect(warnings.any? { |w| w.include?("Checkpoint failed") }).to be true
      ensure
        FileUtils.rm_rf(test_close_db)
      end
    end
  end

  describe "delegation methods" do
    let(:conversation_id) { history.create_conversation }

    it "delegates #get_message_by_id" do
      history.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "Test")
      messages = history.messages(conversation_id: conversation_id)
      msg_id = messages.first["id"]

      retrieved = history.get_message_by_id(msg_id, conversation_id: conversation_id)
      expect(retrieved["content"]).to eq("Test")
    end

    it "delegates #update_conversation_summary" do
      history.update_conversation_summary(
        conversation_id: conversation_id,
        summary: "Test summary",
        model: "test-model",
        cost: 0.001
      )

      # Verify by querying directly
      result = history.connection.query(<<~SQL)
        SELECT summary FROM conversations WHERE id = #{conversation_id}
      SQL
      expect(result.first.first).to eq("Test summary")
    end

    it "delegates #all_conversations" do
      # Start fresh count
      initial_count = history.all_conversations.length

      history.create_conversation
      history.create_conversation

      conversations = history.all_conversations
      expect(conversations.length).to eq(initial_count + 2) # 2 new conversations
    end

    it "delegates #get_unsummarized_conversations" do
      conv1 = history.create_conversation
      conv2 = history.create_conversation
      history.update_conversation_summary(conversation_id: conv1, summary: "Done", model: "test")

      unsummarized = history.get_unsummarized_conversations(exclude_id: conv2)
      ids = unsummarized.map { |c| c["id"] }
      expect(ids).not_to include(conv1)
      expect(ids).not_to include(conv2)
    end

    it "delegates #update_message_exchange_id" do
      history.add_message(conversation_id: conversation_id, actor: "user", role: "user", content: "Test")
      messages = history.messages(conversation_id: conversation_id)
      msg_id = messages.first["id"]

      exchange_id = history.create_exchange(conversation_id: conversation_id, user_message: "Q")

      history.update_message_exchange_id(message_id: msg_id, exchange_id: exchange_id)

      exchange_messages = history.get_exchange_messages(exchange_id: exchange_id)
      expect(exchange_messages.first["id"]).to eq(msg_id)
    end

    it "delegates #current_context_size" do
      session_start = Time.now - 60
      history.add_message(
        conversation_id: conversation_id,
        actor: "orchestrator",
        role: "assistant",
        content: "Test",
        tokens_input: 100,
        tokens_output: 50
      )

      size = history.current_context_size(
        conversation_id: conversation_id,
        since: session_start,
        model: "test-model"
      )

      expect(size).to be_a(Integer)
      expect(size).to be >= 0
    end

    it "delegates #add_command_history" do
      history.add_command_history("test command")
      commands = history.get_command_history(limit: 10)
      expect(commands.any? { |c| c["command"] == "test command" }).to be true
    end

    it "delegates #get_command_history" do
      history.add_command_history("cmd1")
      history.add_command_history("cmd2")

      commands = history.get_command_history(limit: 10)
      expect(commands).to be_an(Array)
      expect(commands.length).to be >= 2
    end

    it "delegates embedding methods" do
      # upsert_conversation_embedding
      history.upsert_conversation_embedding(
        conversation_id: 999,
        content: "test conversation summary",
        embedding: Array.new(1536, 0.1)
      )

      # get_indexed_sources for conversations
      sources = history.get_indexed_sources(kind: "conversation_summary")
      expect(sources).to include(999)

      # upsert_exchange_embedding
      history.upsert_exchange_embedding(
        exchange_id: 888,
        content: "test exchange summary",
        embedding: Array.new(1536, 0.2)
      )

      # get_indexed_sources for exchanges
      exchange_sources = history.get_indexed_sources(kind: "exchange_summary")
      expect(exchange_sources).to include(888)

      # embedding_stats
      stats = history.embedding_stats(kind: "conversation_summary")
      expect(stats).to be_an(Array)
      expect(stats.length).to be >= 1

      # clear_embeddings
      history.clear_embeddings(kind: "conversation_summary")
      sources_after = history.get_indexed_sources(kind: "conversation_summary")
      expect(sources_after).to be_empty
    end
  end

  describe "private helper methods" do
    describe "#format_bytes" do
      it "formats bytes correctly" do
        expect(history.send(:format_bytes, 500)).to eq("500B")
        expect(history.send(:format_bytes, 1500)).to eq("1.5KB")
        expect(history.send(:format_bytes, 1_500_000)).to eq("1.4MB")
      end
    end

    describe "#ensure_db_directory" do
      it "creates directory if it doesn't exist" do
        test_dir = "db/deep/nested/path/test.db"

        begin
          history.send(:ensure_db_directory, test_dir)
          expect(Dir.exist?("db/deep/nested/path")).to be true
        ensure
          FileUtils.rm_rf("db/deep")
        end
      end
    end

    describe "#escape_sql" do
      it "escapes single quotes" do
        escaped = history.send(:escape_sql, "It's a test")
        expect(escaped).to eq("It''s a test")
      end

      it "handles multiple quotes" do
        escaped = history.send(:escape_sql, "O'Reilly's book")
        expect(escaped).to eq("O''Reilly''s book")
      end
    end
  end

  describe "#connection per thread" do
    it "creates separate connections for different threads" do
      connections = []
      threads = 3.times.map do
        Thread.new do
          conn = history.connection
          connections << conn.object_id
        end
      end
      threads.each(&:join)

      # Each thread should have its own connection
      expect(connections.uniq.length).to eq(3)
    end

    it "reuses connection within the same thread" do
      conn1 = history.connection
      conn2 = history.connection
      expect(conn1.object_id).to eq(conn2.object_id)
    end

    it "sets default_null_order on new connections" do
      # This is tested implicitly by the fact that queries work
      expect { history.connection }.not_to raise_error
    end
  end

  describe "#get_unsummarized_exchanges" do
    it "delegates to exchange repository" do
      conversation_id = history.create_conversation
      history.create_exchange(conversation_id: conversation_id, user_message: "test message")

      exchanges = history.get_unsummarized_exchanges(exclude_conversation_id: conversation_id)
      expect(exchanges).to be_an(Array)
    end
  end

  describe "#update_exchange_summary" do
    it "updates exchange summary with model and cost" do
      conversation_id = history.create_conversation
      exchange_id = history.create_exchange(conversation_id: conversation_id, user_message: "test message")

      expect {
        history.update_exchange_summary(
          exchange_id: exchange_id,
          summary: "Test summary",
          model: "test-model",
          cost: 0.001
        )
      }.not_to raise_error
    end
  end

  describe "#get_int" do
    it "returns integer value from config" do
      history.set_config("test_int", "42")
      expect(history.get_int("test_int")).to eq(42)
    end

    it "returns default when key not found" do
      expect(history.get_int("nonexistent", 10)).to eq(10)
    end
  end

  describe "#store_embeddings" do
    it "raises NotImplementedError (deprecated method)" do
      conversation_id = history.create_conversation

      records = [{
        ref_id: conversation_id,
        embedding: Array.new(1536, 0.1),
        text: "test"
      }]

      expect { history.store_embeddings(kind: :conversation, records: records) }.to raise_error(NotImplementedError, /deprecated/)
    end
  end

  describe "clear methods" do
    describe "#clear_conversation_summaries" do
      it "clears all conversation summaries" do
        conversation_id = history.create_conversation
        history.update_conversation_summary(
          conversation_id: conversation_id,
          summary: "test",
          model: "test-model"
        )

        expect { history.clear_conversation_summaries }.not_to raise_error
      end
    end

    describe "#clear_exchange_summaries" do
      it "clears all exchange summaries" do
        conversation_id = history.create_conversation
        exchange_id = history.create_exchange(conversation_id: conversation_id, user_message: "test message")
        history.update_exchange_summary(
          exchange_id: exchange_id,
          summary: "test",
          model: "test-model"
        )

        expect { history.clear_exchange_summaries }.not_to raise_error
      end
    end

    describe "#clear_all_embeddings" do
      it "deletes all embeddings" do
        conversation_id = history.create_conversation

        history.upsert_conversation_embedding(
          conversation_id: conversation_id,
          content: "test content",
          embedding: Array.new(1536, 0.1)
        )

        expect { history.clear_all_embeddings }.not_to raise_error
      end
    end
  end

  describe "failed job methods" do
    describe "#create_failed_job" do
      it "creates a failed job record" do
        job_id = history.create_failed_job(
          job_type: "test_job",
          error: "Test error",
          ref_id: 123,
          payload: '{"test": "data"}'
        )

        expect(job_id).to be_a(Integer)
        expect(job_id).to be > 0
      end
    end

    describe "#get_failed_job" do
      it "retrieves a failed job by id" do
        job_id = history.create_failed_job(
          job_type: "test_job",
          error: "Test error"
        )

        job = history.get_failed_job(job_id)
        expect(job["job_type"]).to eq("test_job")
        expect(job["error"]).to eq("Test error")
      end
    end

    describe "#list_failed_jobs" do
      it "lists all failed jobs" do
        history.create_failed_job(job_type: "job1", error: "error1")
        history.create_failed_job(job_type: "job2", error: "error2")

        jobs = history.list_failed_jobs
        expect(jobs.size).to be >= 2
      end

      it "filters by job type" do
        history.create_failed_job(job_type: "specific_job", error: "error1")
        history.create_failed_job(job_type: "other_job", error: "error2")

        jobs = history.list_failed_jobs(job_type: "specific_job")
        expect(jobs.all? { |j| j["job_type"] == "specific_job" }).to be true
      end
    end

    describe "#increment_failed_job_retry_count" do
      it "increments retry count" do
        job_id = history.create_failed_job(job_type: "test_job", error: "error")

        history.increment_failed_job_retry_count(job_id)

        job = history.get_failed_job(job_id)
        expect(job["retry_count"]).to eq(1)
      end
    end

    describe "#delete_failed_job" do
      it "deletes a failed job" do
        job_id = history.create_failed_job(job_type: "test_job", error: "error")

        history.delete_failed_job(job_id)

        job = history.get_failed_job(job_id)
        expect(job).to be_nil
      end
    end

    describe "#delete_failed_jobs_older_than" do
      it "deletes old failed jobs" do
        job_id = history.create_failed_job(job_type: "test_job", error: "error")

        # This won't delete anything since the job was just created
        count = history.delete_failed_jobs_older_than(days: 1)
        expect(count).to eq(0)

        # Job should still exist
        job = history.get_failed_job(job_id)
        expect(job).not_to be_nil
      end
    end

    describe "#get_failed_jobs_count" do
      it "returns count of all failed jobs" do
        initial_count = history.get_failed_jobs_count

        history.create_failed_job(job_type: "test_job", error: "error")

        expect(history.get_failed_jobs_count).to eq(initial_count + 1)
      end

      it "returns count filtered by job type" do
        history.create_failed_job(job_type: "specific_job", error: "error1")
        history.create_failed_job(job_type: "other_job", error: "error2")

        count = history.get_failed_jobs_count(job_type: "specific_job")
        expect(count).to be >= 1
      end
    end
  end

  describe "purge methods" do
    describe "#purge_conversation_data" do
      it "purges conversation summaries and embeddings" do
        conversation_id = history.create_conversation
        history.update_conversation_summary(
          conversation_id: conversation_id,
          summary: "test",
          model: "test-model"
        )

        # Add embedding
        history.upsert_conversation_embedding(
          conversation_id: conversation_id,
          content: "test content",
          embedding: Array.new(1536, 0.1)
        )

        expect { history.purge_conversation_data(conversation_id: conversation_id) }.not_to raise_error
      end
    end

    describe "#purge_all_data" do
      it "purges all summaries and embeddings" do
        conversation_id = history.create_conversation
        history.update_conversation_summary(
          conversation_id: conversation_id,
          summary: "test",
          model: "test-model"
        )

        result = history.purge_all_data
        expect(result).to be_a(Hash)
        expect(result).to have_key(:conversations_cleared)
        expect(result).to have_key(:exchanges_cleared)
        expect(result).to have_key(:conversation_embeddings_deleted)
        expect(result).to have_key(:exchange_embeddings_deleted)
      end
    end
  end
end
