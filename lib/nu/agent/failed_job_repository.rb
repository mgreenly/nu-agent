# frozen_string_literal: true

module Nu
  module Agent
    # Manages failed job CRUD operations
    class FailedJobRepository
      def initialize(connection)
        @connection = connection
      end

      # Create a new failed job record
      # @param job_type [String] the type of job that failed (e.g., "exchange_summarization")
      # @param ref_id [Integer, nil] optional reference id (e.g., exchange_id)
      # @param payload [String, nil] optional JSON payload
      # @param error [String] the error message
      # @return [Integer] the id of the created failed job
      def create_failed_job(job_type:, error:, ref_id: nil, payload: nil)
        payload_sql = payload ? "'#{escape_sql(payload)}'" : "NULL"
        ref_id_sql = ref_id || "NULL"

        result = @connection.query(<<~SQL)
          INSERT INTO failed_jobs (
            job_type, ref_id, payload, error, failed_at
          ) VALUES (
            '#{escape_sql(job_type)}',
            #{ref_id_sql},
            #{payload_sql},
            '#{escape_sql(error)}',
            CURRENT_TIMESTAMP
          )
          RETURNING id
        SQL
        result.to_a.first.first
      end

      # Get a failed job by id
      # @param id [Integer] the failed job id
      # @return [Hash, nil] the failed job record or nil if not found
      def get_failed_job(id)
        result = @connection.query(<<~SQL)
          SELECT id, job_type, ref_id, payload, error, retry_count, failed_at, created_at
          FROM failed_jobs
          WHERE id = #{id}
        SQL

        row = result.to_a.first
        return nil if row.nil?

        {
          "id" => row[0],
          "job_type" => row[1],
          "ref_id" => row[2],
          "payload" => row[3],
          "error" => row[4],
          "retry_count" => row[5],
          "failed_at" => row[6].to_s,
          "created_at" => row[7].to_s
        }
      end

      # List failed jobs with optional filtering
      # @param job_type [String, nil] optional job type filter
      # @param limit [Integer] maximum number of jobs to return (default: 100)
      # @return [Array<Hash>] array of failed job records
      def list_failed_jobs(job_type: nil, limit: 100)
        where_clause = job_type ? "WHERE job_type = '#{escape_sql(job_type)}'" : ""

        result = @connection.query(<<~SQL)
          SELECT id, job_type, ref_id, payload, error, retry_count, failed_at, created_at
          FROM failed_jobs
          #{where_clause}
          ORDER BY failed_at DESC
          LIMIT #{limit}
        SQL

        result.to_a.map do |row|
          {
            "id" => row[0],
            "job_type" => row[1],
            "ref_id" => row[2],
            "payload" => row[3],
            "error" => row[4],
            "retry_count" => row[5],
            "failed_at" => row[6].to_s,
            "created_at" => row[7].to_s
          }
        end
      end

      # Increment the retry count for a failed job
      # @param id [Integer] the failed job id
      def increment_retry_count(id)
        @connection.query(<<~SQL)
          UPDATE failed_jobs
          SET retry_count = retry_count + 1
          WHERE id = #{id}
        SQL
      end

      # Delete a failed job
      # @param id [Integer] the failed job id
      def delete_failed_job(id)
        @connection.query(<<~SQL)
          DELETE FROM failed_jobs
          WHERE id = #{id}
        SQL
      end

      # Delete failed jobs older than specified days
      # @param days [Integer] delete jobs older than this many days
      # @return [Integer] number of jobs deleted
      def delete_failed_jobs_older_than(days:)
        result = @connection.query(<<~SQL)
          DELETE FROM failed_jobs
          WHERE failed_at < CURRENT_TIMESTAMP - INTERVAL '#{days} days'
          RETURNING id
        SQL
        result.to_a.length
      end

      # Get count of failed jobs
      # @param job_type [String, nil] optional job type filter
      # @return [Integer] count of failed jobs
      def get_failed_jobs_count(job_type: nil)
        where_clause = job_type ? "WHERE job_type = '#{escape_sql(job_type)}'" : ""

        result = @connection.query(<<~SQL)
          SELECT COUNT(*) FROM failed_jobs #{where_clause}
        SQL
        result.to_a.first.first
      end

      private

      # Escape SQL string to prevent injection
      # @param str [String] the string to escape
      # @return [String] the escaped string
      def escape_sql(str)
        str.to_s.gsub("'", "''")
      end
    end
  end
end
