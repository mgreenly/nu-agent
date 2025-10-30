# frozen_string_literal: true

# Migration: Create failed_jobs table for tracking background job failures
{
  version: 6,
  name: "create_failed_jobs",
  up: lambda do |conn|
    # Create sequence for failed_jobs id
    conn.query("CREATE SEQUENCE IF NOT EXISTS failed_jobs_id_seq START 1")

    # Create failed_jobs table if it doesn't exist
    conn.query(<<~SQL)
      CREATE TABLE IF NOT EXISTS failed_jobs (
        id INTEGER PRIMARY KEY DEFAULT nextval('failed_jobs_id_seq'),
        job_type VARCHAR NOT NULL,
        ref_id INTEGER,
        payload TEXT,
        error TEXT NOT NULL,
        retry_count INTEGER DEFAULT 0,
        failed_at TIMESTAMP NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    SQL

    # Create indexes for common queries
    conn.query(<<~SQL)
      CREATE INDEX IF NOT EXISTS idx_failed_jobs_job_type
      ON failed_jobs(job_type)
    SQL

    conn.query(<<~SQL)
      CREATE INDEX IF NOT EXISTS idx_failed_jobs_failed_at
      ON failed_jobs(failed_at)
    SQL

    conn.query(<<~SQL)
      CREATE INDEX IF NOT EXISTS idx_failed_jobs_ref_id
      ON failed_jobs(ref_id)
    SQL
  end
}
