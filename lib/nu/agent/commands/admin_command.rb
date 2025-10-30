# frozen_string_literal: true

require_relative "base_command"

module Nu
  module Agent
    module Commands
      # Administrative command for managing failed jobs and system operations
      class AdminCommand < BaseCommand
        def execute(input)
          parts = input.strip.split(/\s+/)
          subcommand = parts[1]&.downcase
          args = parts[2..]

          case subcommand
          when "failures"
            handle_failures(args)
          when "show"
            handle_show(args)
          when "retry"
            handle_retry(args)
          when "purge-failures"
            handle_purge_failures(args)
          else
            show_help
          end

          :continue
        end

        private

        def handle_failures(args)
          # Parse options
          options = parse_options(args)
          job_type = options["type"]

          jobs = app.history.list_failed_jobs(job_type: job_type, limit: 100)

          if jobs.empty?
            app.console.puts("No failed jobs found.")
            return
          end

          app.console.puts("Failed Jobs:")
          app.console.puts("")

          jobs.each do |job|
            app.console.puts("  ID: #{job['id']}")
            app.console.puts("  Type: #{job['job_type']}")
            app.console.puts("  Ref ID: #{job['ref_id']}")
            app.console.puts("  Error: #{job['error']}")
            app.console.puts("  Retry Count: #{job['retry_count']}")
            app.console.puts("  Failed At: #{job['failed_at']}")
            app.console.puts("")
          end

          app.console.puts("Total: #{jobs.length} failed job(s)")
        end

        def handle_show(args)
          if args.empty?
            app.console.puts("Usage: /admin show <job_id>")
            return
          end

          job_id = args[0].to_i
          job = app.history.get_failed_job(job_id)

          if job.nil?
            app.console.puts("Failed job #{job_id} not found.")
            return
          end

          app.console.puts("Failed Job Details:")
          app.console.puts("")
          app.console.puts("  ID: #{job['id']}")
          app.console.puts("  Type: #{job['job_type']}")
          app.console.puts("  Ref ID: #{job['ref_id']}")
          app.console.puts("  Error: #{job['error']}")
          app.console.puts("  Retry Count: #{job['retry_count']}")
          app.console.puts("  Failed At: #{job['failed_at']}")
          app.console.puts("  Created At: #{job['created_at']}")

          if job["payload"] && !job["payload"].empty?
            app.console.puts("")
            app.console.puts("  Payload:")
            begin
              payload = JSON.parse(job["payload"])
              payload.each do |key, value|
                app.console.puts("    #{key}: #{value}")
              end
            rescue JSON::ParserError
              app.console.puts("    #{job['payload']}")
            end
          end
        end

        def handle_retry(args)
          if args.empty?
            app.console.puts("Usage: /admin retry <job_id>")
            return
          end

          job_id = args[0].to_i
          job = app.history.get_failed_job(job_id)

          if job.nil?
            app.console.puts("Failed job #{job_id} not found.")
            return
          end

          # Increment retry count and remove from failed jobs
          app.history.increment_failed_job_retry_count(job_id)
          app.history.delete_failed_job(job_id)

          app.console.puts("Retrying job #{job_id} (#{job['job_type']})...")

          # Trigger appropriate worker based on job type
          case job["job_type"]
          when "exchange_summarization", "conversation_summarization"
            app.worker_manager.start_summarization_worker
            app.console.puts("Summarization worker started.")
          when "embedding_generation"
            app.worker_manager.start_embedding_worker
            app.console.puts("Embedding worker started.")
          else
            app.console.puts("Warning: Unknown job type #{job['job_type']}, cannot retry automatically.")
          end
        end

        def handle_purge_failures(args)
          # Parse options
          options = parse_options(args)
          older_than = options["older-than"]&.to_i || 0

          # Count jobs to be purged
          total_count = app.history.get_failed_jobs_count(job_type: nil)

          if total_count.zero?
            app.console.puts("No failed jobs to purge.")
            return
          end

          if older_than.positive?
            app.console.puts("Purging failed jobs older than #{older_than} days...")
          else
            app.console.puts("Purging all failed jobs...")
          end

          deleted_count = app.history.delete_failed_jobs_older_than(days: older_than)
          app.console.puts("Purged #{deleted_count} failed job(s).")
        end

        def show_help
          app.console.puts("Admin Commands:")
          app.console.puts("")
          app.console.puts("  /admin failures [--type=<job_type>]")
          app.console.puts("    List failed jobs with optional filtering by type")
          app.console.puts("")
          app.console.puts("  /admin show <job_id>")
          app.console.puts("    Show details of a specific failed job")
          app.console.puts("")
          app.console.puts("  /admin retry <job_id>")
          app.console.puts("    Retry a failed job and start appropriate worker")
          app.console.puts("")
          app.console.puts("  /admin purge-failures [--older-than=<days>]")
          app.console.puts("    Purge failed jobs (optionally only older than N days)")
        end

        def parse_options(args)
          options = {}
          args.each do |arg|
            if arg.start_with?("--")
              key, value = arg[2..].split("=", 2)
              options[key] = value
            end
          end
          options
        end
      end
    end
  end
end
