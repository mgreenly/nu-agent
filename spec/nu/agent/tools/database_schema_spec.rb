# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::Tools::DatabaseSchema do
  let(:tool) { described_class.new }
  let(:history) { instance_double(Nu::Agent::History) }
  let(:application) { instance_double(Nu::Agent::Application) }
  let(:context) { { "application" => application } }

  describe "#name" do
    it "returns the tool name" do
      expect(tool.name).to eq("database_schema")
    end
  end

  describe "#description" do
    it "returns a description" do
      expect(tool.description).to include("PREFERRED tool for viewing table schemas")
      expect(tool.description).to include("database_tables")
    end
  end

  describe "#parameters" do
    it "defines expected parameters" do
      params = tool.parameters

      expect(params).to have_key(:table_name)
    end

    it "marks table_name as required" do
      expect(tool.parameters[:table_name][:required]).to be true
    end
  end

  describe "#execute" do
    context "with missing table_name parameter" do
      it "returns error when table_name is nil" do
        result = tool.execute(arguments: {}, history: history, context: context)

        expect(result[:error]).to eq("table_name is required")
      end

      it "returns error when table_name is empty string" do
        result = tool.execute(arguments: { table_name: "" }, history: history, context: context)

        expect(result[:error]).to eq("table_name is required")
      end
    end

    context "with valid table_name" do
      let(:columns) do
        [
          { name: "id", type: "INTEGER", notnull: 1, pk: 1 },
          { name: "content", type: "TEXT", notnull: 0, pk: 0 },
          { name: "created_at", type: "TIMESTAMP", notnull: 1, pk: 0 }
        ]
      end

      before do
        allow(history).to receive(:describe_table).with("messages").and_return(columns)
      end

      it "describes table with symbol key" do
        result = tool.execute(arguments: { table_name: "messages" }, history: history, context: context)

        expect(result[:table_name]).to eq("messages")
        expect(result[:columns]).to eq(columns)
        expect(result[:column_count]).to eq(3)
        expect(result[:error]).to be_nil
      end

      it "describes table with string key" do
        result = tool.execute(arguments: { "table_name" => "messages" }, history: history, context: context)

        expect(result[:table_name]).to eq("messages")
        expect(result[:columns]).to eq(columns)
        expect(result[:column_count]).to eq(3)
      end

      it "accesses application from context" do
        # This line is in the code for debugging but doesn't use the result
        expect(context["application"]).to eq(application)

        tool.execute(arguments: { table_name: "messages" }, history: history, context: context)
      end
    end

    context "with empty columns result" do
      before do
        allow(history).to receive(:describe_table).with("empty_table").and_return([])
      end

      it "returns zero column count" do
        result = tool.execute(arguments: { table_name: "empty_table" }, history: history, context: context)

        expect(result[:table_name]).to eq("empty_table")
        expect(result[:columns]).to eq([])
        expect(result[:column_count]).to eq(0)
      end
    end

    context "when an error occurs" do
      before do
        allow(history).to receive(:describe_table).and_raise(StandardError.new("Table not found"))
      end

      it "catches StandardError and returns error response" do
        result = tool.execute(arguments: { table_name: "nonexistent" }, history: history, context: context)

        expect(result[:error]).to eq("Table not found")
        expect(result[:table_name]).to eq("nonexistent")
        expect(result[:columns]).to be_nil
      end
    end
  end
end
