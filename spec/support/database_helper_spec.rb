# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require_relative "database_helper"

RSpec.describe DatabaseHelper do
  let(:test_db_path) { "db/test_database_helper.db" }

  before do
    # Clean up any existing test database
    FileUtils.rm_rf(test_db_path)
  end

  after do
    # Clean up test database
    FileUtils.rm_rf(test_db_path)
  end

  describe ".setup_test_database" do
    it "creates a database with schema and migrations" do
      described_class.setup_test_database(db_path: test_db_path)

      # Verify database file exists
      expect(File.exist?(test_db_path)).to be true

      # Verify we can connect to it and query tables
      history = Nu::Agent::History.new(db_path: test_db_path)
      conn = history.connection

      # Verify some core tables exist
      result = conn.query("SHOW TABLES")
      table_names = result.map { |row| row[0] }

      expect(table_names).to include("conversations")
      expect(table_names).to include("messages")
      expect(table_names).to include("schema_version")

      history.close
    end

    it "sets up schema_version table with migrations applied" do
      described_class.setup_test_database(db_path: test_db_path)

      history = Nu::Agent::History.new(db_path: test_db_path)
      conn = history.connection

      # Check that schema_version table has entries
      versions = conn.query("SELECT version FROM schema_version ORDER BY version").to_a
      expect(versions).not_to be_empty

      history.close
    end
  end

  describe ".truncate_all_tables" do
    before do
      # Set up test database with some data
      described_class.setup_test_database(db_path: test_db_path)
      @history = Nu::Agent::History.new(db_path: test_db_path)

      # Add test data
      @conversation_id = @history.create_conversation
      @history.add_message(
        conversation_id: @conversation_id,
        actor: "user",
        role: "user",
        content: "test message"
      )
    end

    after do
      @history&.close
    end

    it "removes all data from tables except schema_version" do
      # Verify data exists
      messages = @history.messages(conversation_id: @conversation_id)
      expect(messages.length).to eq(1)

      # Truncate tables
      described_class.truncate_all_tables(@history.connection)

      # Verify data is gone
      messages_after = @history.messages(conversation_id: @conversation_id)
      expect(messages_after.length).to eq(0)

      # Verify schema_version is preserved
      versions = @history.connection.query("SELECT version FROM schema_version").to_a
      expect(versions).not_to be_empty
    end

    it "allows inserting data after truncation" do
      described_class.truncate_all_tables(@history.connection)

      # Should be able to create new conversation
      new_conversation_id = @history.create_conversation
      expect(new_conversation_id).to be_a(Integer)
      expect(new_conversation_id).to be > 0

      # Should be able to add message
      @history.add_message(
        conversation_id: new_conversation_id,
        actor: "user",
        role: "user",
        content: "new message"
      )

      messages = @history.messages(conversation_id: new_conversation_id)
      expect(messages.length).to eq(1)
    end
  end

  describe ".get_test_history" do
    after do
      described_class.instance_variable_set(:@test_history, nil)
      described_class.instance_variable_set(:@in_memory_history, nil)
    end

    it "returns a History instance configured for testing" do
      history = described_class.get_test_history

      expect(history).to be_a(Nu::Agent::History)
      # Accept either file-based (contains "test") or in-memory (":memory:")
      expect(history.db_path).to match(/test|:memory:/)
    end

    it "returns the same instance on multiple calls (singleton)" do
      history1 = described_class.get_test_history
      history2 = described_class.get_test_history

      expect(history1.object_id).to eq(history2.object_id)
    end

    it "allows custom db_path to be specified" do
      custom_path = "db/custom_test.db"
      FileUtils.rm_rf(custom_path)

      history = described_class.get_test_history(db_path: custom_path)

      expect(history.db_path).to eq(custom_path)

      history.close
      FileUtils.rm_rf(custom_path)
    end
  end

  describe "in-memory database support" do
    after do
      described_class.instance_variable_set(:@in_memory_history, nil)
    end

    describe ".setup_test_database with :memory:" do
      it "creates an in-memory database with schema and migrations" do
        described_class.setup_test_database(db_path: ":memory:")

        # Verify we can get a history instance and query tables
        history = described_class.get_test_history(db_path: ":memory:")
        conn = history.connection

        # Verify some core tables exist
        result = conn.query("SHOW TABLES")
        table_names = result.map { |row| row[0] }

        expect(table_names).to include("conversations")
        expect(table_names).to include("messages")
        expect(table_names).to include("schema_version")
      end

      it "keeps the connection alive for in-memory databases" do
        described_class.setup_test_database(db_path: ":memory:")

        # Get history instance twice
        history1 = described_class.get_test_history(db_path: ":memory:")
        history2 = described_class.get_test_history(db_path: ":memory:")

        # Should be the same instance (singleton)
        expect(history1.object_id).to eq(history2.object_id)
      end
    end

    describe ".get_test_history with :memory:" do
      it "returns an in-memory History instance" do
        history = described_class.get_test_history(db_path: ":memory:")

        expect(history).to be_a(Nu::Agent::History)
        expect(history.db_path).to eq(":memory:")
      end

      it "persists data across calls (same connection)" do
        history = described_class.get_test_history(db_path: ":memory:")

        # Add some data
        conversation_id = history.create_conversation
        history.add_message(
          conversation_id: conversation_id,
          actor: "user",
          role: "user",
          content: "test message"
        )

        # Get history again (should be same instance)
        history2 = described_class.get_test_history(db_path: ":memory:")

        # Data should still be there
        messages = history2.messages(conversation_id: conversation_id)
        expect(messages.length).to eq(1)
        expect(messages[0]["content"]).to eq("test message")
      end
    end

    describe ".truncate_all_tables with in-memory database" do
      it "works with in-memory databases" do
        history = described_class.get_test_history(db_path: ":memory:")

        # Add test data
        conversation_id = history.create_conversation
        history.add_message(
          conversation_id: conversation_id,
          actor: "user",
          role: "user",
          content: "test message"
        )

        # Verify data exists
        messages = history.messages(conversation_id: conversation_id)
        expect(messages.length).to eq(1)

        # Truncate tables
        described_class.truncate_all_tables(history.connection)

        # Verify data is gone
        messages_after = history.messages(conversation_id: conversation_id)
        expect(messages_after.length).to eq(0)

        # Verify schema_version is preserved
        versions = history.connection.query("SELECT version FROM schema_version").to_a
        expect(versions).not_to be_empty
      end
    end
  end
end
