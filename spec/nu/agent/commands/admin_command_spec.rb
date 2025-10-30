# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::Commands::AdminCommand do
  let(:history) { instance_double(Nu::Agent::History) }
  let(:worker_manager) { instance_double(Nu::Agent::BackgroundWorkerManager) }
  let(:console) { instance_double(Nu::Agent::ConsoleIO) }
  let(:application) do
    instance_double(
      Nu::Agent::Application,
      history: history,
      worker_manager: worker_manager,
      console: console
    )
  end
  let(:command) { described_class.new(application) }

  describe "#execute" do
    context "with 'failures' subcommand" do
      it "lists all failed jobs" do
        jobs = [
          {
            "id" => 1,
            "job_type" => "exchange_summarization",
            "ref_id" => 123,
            "error" => "API timeout",
            "retry_count" => 0,
            "failed_at" => "2025-10-30 10:00:00"
          },
          {
            "id" => 2,
            "job_type" => "embedding_generation",
            "ref_id" => 456,
            "error" => "Rate limit exceeded",
            "retry_count" => 1,
            "failed_at" => "2025-10-30 11:00:00"
          }
        ]

        allow(history).to receive(:list_failed_jobs).with(job_type: nil, limit: 100).and_return(jobs)
        expect(console).to receive(:puts).at_least(:once)

        result = command.execute("/admin failures")
        expect(result).to eq(:continue)
      end

      it "filters by job type" do
        jobs = [
          {
            "id" => 1,
            "job_type" => "exchange_summarization",
            "ref_id" => 123,
            "error" => "API timeout",
            "retry_count" => 0,
            "failed_at" => "2025-10-30 10:00:00"
          }
        ]

        allow(history).to receive(:list_failed_jobs)
          .with(job_type: "exchange_summarization", limit: 100)
          .and_return(jobs)
        expect(console).to receive(:puts).at_least(:once)

        result = command.execute("/admin failures --type=exchange_summarization")
        expect(result).to eq(:continue)
      end

      it "handles no failed jobs" do
        allow(history).to receive(:list_failed_jobs).with(job_type: nil, limit: 100).and_return([])
        expect(console).to receive(:puts).with(/No failed jobs/)

        result = command.execute("/admin failures")
        expect(result).to eq(:continue)
      end
    end

    context "with 'show' subcommand" do
      it "shows details of a specific failed job" do
        job = {
          "id" => 1,
          "job_type" => "exchange_summarization",
          "ref_id" => 123,
          "payload" => '{"exchange_id":123}',
          "error" => "API timeout",
          "retry_count" => 2,
          "failed_at" => "2025-10-30 10:00:00"
        }

        allow(history).to receive(:get_failed_job).with(1).and_return(job)
        expect(console).to receive(:puts).at_least(:once)

        result = command.execute("/admin show 1")
        expect(result).to eq(:continue)
      end

      it "handles non-existent job" do
        allow(history).to receive(:get_failed_job).with(999).and_return(nil)
        expect(console).to receive(:puts).with(/not found/)

        result = command.execute("/admin show 999")
        expect(result).to eq(:continue)
      end

      it "requires job id" do
        expect(console).to receive(:puts).with(/Usage:/)

        result = command.execute("/admin show")
        expect(result).to eq(:continue)
      end

      it "handles invalid JSON in payload" do
        job = {
          "id" => 1,
          "job_type" => "exchange_summarization",
          "ref_id" => 123,
          "payload" => "invalid json {",
          "error" => "API timeout",
          "retry_count" => 0,
          "failed_at" => "2025-10-30 10:00:00",
          "created_at" => "2025-10-30 09:00:00"
        }

        allow(history).to receive(:get_failed_job).with(1).and_return(job)
        expect(console).to receive(:puts).at_least(:once)

        result = command.execute("/admin show 1")
        expect(result).to eq(:continue)
      end

      it "handles empty payload" do
        job = {
          "id" => 1,
          "job_type" => "exchange_summarization",
          "ref_id" => 123,
          "payload" => "",
          "error" => "API timeout",
          "retry_count" => 0,
          "failed_at" => "2025-10-30 10:00:00",
          "created_at" => "2025-10-30 09:00:00"
        }

        allow(history).to receive(:get_failed_job).with(1).and_return(job)
        expect(console).to receive(:puts).at_least(:once)

        result = command.execute("/admin show 1")
        expect(result).to eq(:continue)
      end
    end

    context "with 'retry' subcommand" do
      it "retries a failed job" do
        job = {
          "id" => 1,
          "job_type" => "exchange_summarization",
          "ref_id" => 123,
          "payload" => '{"exchange_id":123}'
        }

        allow(history).to receive(:get_failed_job).with(1).and_return(job)
        allow(history).to receive(:increment_failed_job_retry_count).with(1)
        allow(history).to receive(:delete_failed_job).with(1)
        allow(worker_manager).to receive(:start_summarization_worker)
        expect(console).to receive(:puts).at_least(:once)

        result = command.execute("/admin retry 1")
        expect(result).to eq(:continue)
      end

      it "handles non-existent job" do
        allow(history).to receive(:get_failed_job).with(999).and_return(nil)
        expect(console).to receive(:puts).with(/not found/)

        result = command.execute("/admin retry 999")
        expect(result).to eq(:continue)
      end

      it "requires job id" do
        expect(console).to receive(:puts).with(/Usage:/)

        result = command.execute("/admin retry")
        expect(result).to eq(:continue)
      end

      it "handles unknown job type" do
        job = {
          "id" => 1,
          "job_type" => "unknown_type",
          "ref_id" => 123,
          "payload" => '{"data":"test"}'
        }

        allow(history).to receive(:get_failed_job).with(1).and_return(job)
        allow(history).to receive(:increment_failed_job_retry_count).with(1)
        allow(history).to receive(:delete_failed_job).with(1)
        expect(console).to receive(:puts).with("Retrying job 1 (unknown_type)...")
        expect(console).to receive(:puts).with(/Warning/)

        result = command.execute("/admin retry 1")
        expect(result).to eq(:continue)
      end

      it "handles embedding_generation job type" do
        job = {
          "id" => 1,
          "job_type" => "embedding_generation",
          "ref_id" => 456,
          "payload" => '{"item_id":456}'
        }

        allow(history).to receive(:get_failed_job).with(1).and_return(job)
        allow(history).to receive(:increment_failed_job_retry_count).with(1)
        allow(history).to receive(:delete_failed_job).with(1)
        allow(worker_manager).to receive(:start_embedding_worker)
        expect(console).to receive(:puts).at_least(:once)

        result = command.execute("/admin retry 1")
        expect(result).to eq(:continue)
      end
    end

    context "with 'purge-failures' subcommand" do
      it "purges all failed jobs" do
        allow(history).to receive(:get_failed_jobs_count).with(job_type: nil).and_return(5)
        allow(history).to receive(:delete_failed_jobs_older_than).with(days: 0).and_return(5)
        expect(console).to receive(:puts).at_least(:once)

        result = command.execute("/admin purge-failures")
        expect(result).to eq(:continue)
      end

      it "purges failed jobs older than specified days" do
        allow(history).to receive(:get_failed_jobs_count).with(job_type: nil).and_return(10)
        allow(history).to receive(:delete_failed_jobs_older_than).with(days: 7).and_return(3)
        expect(console).to receive(:puts).at_least(:once)

        result = command.execute("/admin purge-failures --older-than=7")
        expect(result).to eq(:continue)
      end

      it "handles no jobs to purge" do
        allow(history).to receive(:get_failed_jobs_count).with(job_type: nil).and_return(0)
        expect(console).to receive(:puts).with(/No failed jobs to purge/)

        result = command.execute("/admin purge-failures")
        expect(result).to eq(:continue)
      end
    end

    context "with unknown subcommand" do
      it "shows help" do
        expect(console).to receive(:puts).at_least(:once)

        result = command.execute("/admin unknown")
        expect(result).to eq(:continue)
      end
    end

    context "without subcommand" do
      it "shows help" do
        expect(console).to receive(:puts).at_least(:once)

        result = command.execute("/admin")
        expect(result).to eq(:continue)
      end
    end
  end
end
