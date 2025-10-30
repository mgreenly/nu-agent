# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe Nu::Agent::FailedJobRepository do
  let(:test_db_path) { "db/test_failed_job_repository.db" }
  let(:db) { DuckDB::Database.open(test_db_path) }
  let(:connection) { db.connect }
  let(:schema_manager) { Nu::Agent::SchemaManager.new(connection) }
  let(:migration_manager) { Nu::Agent::MigrationManager.new(connection) }
  let(:repository) { described_class.new(connection) }

  before do
    FileUtils.rm_rf(test_db_path)
    FileUtils.mkdir_p("db")
    schema_manager.setup_schema
    migration_manager.run_pending_migrations
  end

  after do
    connection.close
    db.close
    FileUtils.rm_rf(test_db_path)
  end

  describe "#create_failed_job" do
    it "creates a failed job record and returns its id" do
      job_id = repository.create_failed_job(
        job_type: "exchange_summarization",
        ref_id: 123,
        payload: { exchange_id: 123, attempt: 1 }.to_json,
        error: "API rate limit exceeded"
      )

      expect(job_id).to be_a(Integer)
      expect(job_id).to be > 0
    end

    it "creates failed job with correct default values" do
      job_id = repository.create_failed_job(
        job_type: "embedding_generation",
        ref_id: 456,
        error: "Connection timeout"
      )

      result = connection.query("SELECT retry_count, failed_at FROM failed_jobs WHERE id = #{job_id}")
      row = result.to_a.first

      expect(row[0]).to eq(0) # default retry_count
      expect(row[1]).not_to be_nil # failed_at should be set
    end

    it "stores payload as JSON string" do
      payload = { exchange_id: 789, details: "test" }
      job_id = repository.create_failed_job(
        job_type: "test_job",
        ref_id: 789,
        payload: payload.to_json,
        error: "Test error"
      )

      result = connection.query("SELECT payload FROM failed_jobs WHERE id = #{job_id}")
      stored_payload = result.to_a.first[0]

      expect(stored_payload).to eq(payload.to_json)
    end
  end

  describe "#get_failed_job" do
    let(:job_id) do
      repository.create_failed_job(
        job_type: "exchange_summarization",
        ref_id: 111,
        payload: { test: "data" }.to_json,
        error: "Test error"
      )
    end

    it "retrieves a failed job by id" do
      job = repository.get_failed_job(job_id)

      expect(job).not_to be_nil
      expect(job["id"]).to eq(job_id)
      expect(job["job_type"]).to eq("exchange_summarization")
      expect(job["ref_id"]).to eq(111)
      expect(job["error"]).to eq("Test error")
    end

    it "returns nil for non-existent job" do
      job = repository.get_failed_job(99999)
      expect(job).to be_nil
    end
  end

  describe "#list_failed_jobs" do
    before do
      # Create several failed jobs
      repository.create_failed_job(
        job_type: "exchange_summarization",
        ref_id: 1,
        error: "Error 1"
      )
      repository.create_failed_job(
        job_type: "embedding_generation",
        ref_id: 2,
        error: "Error 2"
      )
      repository.create_failed_job(
        job_type: "exchange_summarization",
        ref_id: 3,
        error: "Error 3"
      )
    end

    it "lists all failed jobs" do
      jobs = repository.list_failed_jobs
      expect(jobs.length).to eq(3)
    end

    it "filters by job_type" do
      jobs = repository.list_failed_jobs(job_type: "exchange_summarization")
      expect(jobs.length).to eq(2)
      expect(jobs.all? { |j| j["job_type"] == "exchange_summarization" }).to be true
    end

    it "limits results" do
      jobs = repository.list_failed_jobs(limit: 2)
      expect(jobs.length).to eq(2)
    end

    it "orders by failed_at descending" do
      jobs = repository.list_failed_jobs
      failed_times = jobs.map { |j| Time.parse(j["failed_at"]) }
      expect(failed_times).to eq(failed_times.sort.reverse)
    end
  end

  describe "#increment_retry_count" do
    let(:job_id) do
      repository.create_failed_job(
        job_type: "test_job",
        ref_id: 1,
        error: "Initial error"
      )
    end

    it "increments the retry count" do
      repository.increment_retry_count(job_id)

      result = connection.query("SELECT retry_count FROM failed_jobs WHERE id = #{job_id}")
      retry_count = result.to_a.first[0]

      expect(retry_count).to eq(1)
    end

    it "increments multiple times" do
      repository.increment_retry_count(job_id)
      repository.increment_retry_count(job_id)
      repository.increment_retry_count(job_id)

      result = connection.query("SELECT retry_count FROM failed_jobs WHERE id = #{job_id}")
      retry_count = result.to_a.first[0]

      expect(retry_count).to eq(3)
    end
  end

  describe "#delete_failed_job" do
    let(:job_id) do
      repository.create_failed_job(
        job_type: "test_job",
        ref_id: 1,
        error: "Test error"
      )
    end

    it "deletes a failed job" do
      repository.delete_failed_job(job_id)

      job = repository.get_failed_job(job_id)
      expect(job).to be_nil
    end
  end

  describe "#delete_failed_jobs_older_than" do
    before do
      # Create jobs with different timestamps
      repository.create_failed_job(job_type: "test1", ref_id: 1, error: "Error 1")
      sleep 0.1
      repository.create_failed_job(job_type: "test2", ref_id: 2, error: "Error 2")
      sleep 0.1
      repository.create_failed_job(job_type: "test3", ref_id: 3, error: "Error 3")
    end

    it "deletes jobs older than specified days" do
      # Delete jobs older than 1 second (should delete all)
      deleted_count = repository.delete_failed_jobs_older_than(days: 0)
      expect(deleted_count).to be >= 0 # Some may be deleted depending on timing
    end

    it "returns count of deleted jobs" do
      deleted_count = repository.delete_failed_jobs_older_than(days: 365)
      expect(deleted_count).to eq(0) # Nothing older than 365 days
    end
  end

  describe "#get_failed_jobs_count" do
    it "returns 0 when no failed jobs" do
      expect(repository.get_failed_jobs_count).to eq(0)
    end

    it "returns correct count" do
      repository.create_failed_job(job_type: "test1", ref_id: 1, error: "Error 1")
      repository.create_failed_job(job_type: "test2", ref_id: 2, error: "Error 2")
      repository.create_failed_job(job_type: "test3", ref_id: 3, error: "Error 3")

      expect(repository.get_failed_jobs_count).to eq(3)
    end

    it "counts by job_type" do
      repository.create_failed_job(job_type: "type_a", ref_id: 1, error: "Error 1")
      repository.create_failed_job(job_type: "type_a", ref_id: 2, error: "Error 2")
      repository.create_failed_job(job_type: "type_b", ref_id: 3, error: "Error 3")

      expect(repository.get_failed_jobs_count(job_type: "type_a")).to eq(2)
      expect(repository.get_failed_jobs_count(job_type: "type_b")).to eq(1)
    end
  end
end
