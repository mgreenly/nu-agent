# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::Tools::DatabaseQuery do
  let(:tool) { described_class.new }
  let(:history) { instance_double(Nu::Agent::History) }

  describe "#name" do
    it "returns the tool name" do
      expect(tool.name).to eq("database_query")
    end
  end

  describe "#description" do
    it "returns a description" do
      expect(tool.description).to include("PREFERRED tool for querying conversation history")
      expect(tool.description).to include("READ-ONLY")
    end
  end

  describe "#parameters" do
    it "defines expected parameters" do
      params = tool.parameters

      expect(params).to have_key(:sql)
    end

    it "marks sql as required" do
      expect(tool.parameters[:sql][:required]).to be true
    end
  end

  describe "#execute" do
    context "with missing sql parameter" do
      it "returns error when sql is nil" do
        result = tool.execute(arguments: {}, history: history)

        expect(result[:error]).to eq("sql query is required")
      end

      it "returns error when sql is empty string" do
        result = tool.execute(arguments: { sql: "" }, history: history)

        expect(result[:error]).to eq("sql query is required")
      end
    end

    context "with valid sql query" do
      let(:rows) do
        [
          { id: 1, content: "Hello", role: "user" },
          { id: 2, content: "Hi there", role: "assistant" }
        ]
      end

      before do
        allow(history).to receive(:execute_query).with("SELECT * FROM messages LIMIT 10").and_return(rows)
      end

      it "executes query with symbol key" do
        result = tool.execute(arguments: { sql: "SELECT * FROM messages LIMIT 10" }, history: history)

        expect(result[:rows]).to eq(rows)
        expect(result[:row_count]).to eq(2)
        expect(result[:query]).to eq("SELECT * FROM messages LIMIT 10")
        expect(result[:error]).to be_nil
      end

      it "executes query with string key" do
        result = tool.execute(arguments: { "sql" => "SELECT * FROM messages LIMIT 10" }, history: history)

        expect(result[:rows]).to eq(rows)
        expect(result[:row_count]).to eq(2)
        expect(result[:query]).to eq("SELECT * FROM messages LIMIT 10")
      end
    end

    context "with empty result set" do
      before do
        allow(history).to receive(:execute_query).with("SELECT * FROM messages WHERE id = 999").and_return([])
      end

      it "returns zero row count" do
        result = tool.execute(arguments: { sql: "SELECT * FROM messages WHERE id = 999" }, history: history)

        expect(result[:rows]).to eq([])
        expect(result[:row_count]).to eq(0)
        expect(result[:query]).to eq("SELECT * FROM messages WHERE id = 999")
      end
    end

    context "when ArgumentError is raised" do
      before do
        allow(history).to receive(:execute_query).and_raise(ArgumentError.new("Write operations not allowed"))
      end

      it "catches ArgumentError and returns error response" do
        result = tool.execute(arguments: { sql: "DELETE FROM messages" }, history: history)

        expect(result[:error]).to eq("Write operations not allowed")
        expect(result[:query]).to eq("DELETE FROM messages")
        expect(result[:rows]).to be_nil
      end
    end

    context "when StandardError is raised" do
      before do
        allow(history).to receive(:execute_query).and_raise(StandardError.new("Syntax error in SQL"))
      end

      it "catches StandardError and returns formatted error response" do
        result = tool.execute(arguments: { sql: "INVALID SQL" }, history: history)

        expect(result[:error]).to eq("Query execution failed: Syntax error in SQL")
        expect(result[:query]).to eq("INVALID SQL")
        expect(result[:rows]).to be_nil
      end
    end
  end
end
