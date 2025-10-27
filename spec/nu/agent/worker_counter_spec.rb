# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe Nu::Agent::WorkerCounter do
  let(:test_db_path) { "db/test_worker_counter.db" }
  let(:db) { DuckDB::Database.open(test_db_path) }
  let(:connection) { db.connect }
  let(:config_store) { Nu::Agent::ConfigStore.new(connection) }
  let(:worker_counter) { described_class.new(config_store) }
  let(:schema_manager) { Nu::Agent::SchemaManager.new(connection) }

  before do
    FileUtils.rm_rf(test_db_path)
    FileUtils.mkdir_p("db")
    # Setup schema so tables exist
    schema_manager.setup_schema
  end

  after do
    connection.close
    db.close
    FileUtils.rm_rf(test_db_path)
  end

  describe "#increment_workers" do
    it "increments worker count from 0 to 1" do
      worker_counter.increment_workers

      value = config_store.get_config("active_workers")
      expect(value).to eq("1")
    end

    it "increments worker count multiple times" do
      worker_counter.increment_workers
      worker_counter.increment_workers
      worker_counter.increment_workers

      value = config_store.get_config("active_workers")
      expect(value).to eq("3")
    end
  end

  describe "#decrement_workers" do
    before do
      config_store.set_config("active_workers", "3")
    end

    it "decrements worker count" do
      worker_counter.decrement_workers

      value = config_store.get_config("active_workers")
      expect(value).to eq("2")
    end

    it "does not go below zero" do
      config_store.set_config("active_workers", "1")
      worker_counter.decrement_workers
      worker_counter.decrement_workers
      worker_counter.decrement_workers

      value = config_store.get_config("active_workers")
      expect(value).to eq("0")
    end
  end

  describe "#workers_idle?" do
    it "returns true when worker count is 0" do
      config_store.set_config("active_workers", "0")

      expect(worker_counter.workers_idle?).to be true
    end

    it "returns false when worker count is greater than 0" do
      config_store.set_config("active_workers", "3")

      expect(worker_counter.workers_idle?).to be false
    end

    it "returns true when active_workers is not set" do
      # Initially active_workers is set to 0 by schema setup
      # but let's test the edge case explicitly
      result = connection.query("DELETE FROM appconfig WHERE key = 'active_workers'")

      expect(worker_counter.workers_idle?).to be true
    end
  end
end
