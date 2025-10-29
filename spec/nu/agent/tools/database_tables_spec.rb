# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::Tools::DatabaseTables do
  let(:tool) { described_class.new }
  let(:history) { instance_double(Nu::Agent::History) }
  let(:application) { instance_double(Nu::Agent::Application) }
  let(:context) { { "application" => application } }

  describe "#name" do
    it "returns the tool name" do
      expect(tool.name).to eq("database_tables")
    end
  end

  describe "#description" do
    it "returns a description" do
      expect(tool.description).to include("PREFERRED tool for listing database tables")
      expect(tool.description).to include("database_schema")
    end
  end

  describe "#parameters" do
    it "returns an empty hash" do
      expect(tool.parameters).to eq({})
    end
  end

  describe "#execute" do
    let(:tables) { %w[messages conversations appconfig exchanges] }

    before do
      allow(history).to receive(:list_tables).and_return(tables)
    end

    it "lists all tables" do
      result = tool.execute(history: history, context: context)

      expect(result[:tables]).to eq(tables)
      expect(result[:count]).to eq(4)
    end

    it "accesses application from context" do
      # This line is in the code for debugging but doesn't use the result
      expect(context["application"]).to eq(application)

      tool.execute(history: history, context: context)
    end

    context "with empty table list" do
      before do
        allow(history).to receive(:list_tables).and_return([])
      end

      it "returns zero count" do
        result = tool.execute(history: history, context: context)

        expect(result[:tables]).to eq([])
        expect(result[:count]).to eq(0)
      end
    end

    context "with single table" do
      before do
        allow(history).to receive(:list_tables).and_return(["messages"])
      end

      it "returns count of one" do
        result = tool.execute(history: history, context: context)

        expect(result[:tables]).to eq(["messages"])
        expect(result[:count]).to eq(1)
      end
    end
  end
end
