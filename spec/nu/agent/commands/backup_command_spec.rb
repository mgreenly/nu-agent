# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/backup_command"
require "tempfile"
require "fileutils"

RSpec.describe Nu::Agent::Commands::BackupCommand do
  let(:application) { instance_double("Nu::Agent::Application") }
  let(:history) { instance_double("Nu::Agent::History") }
  let(:worker_manager) { instance_double("Nu::Agent::BackgroundWorkerManager") }
  let(:command) { described_class.new(application) }
  let(:source_db_path) { "/home/user/.nuagent/memory.db" }

  before do
    allow(application).to receive_messages(
      history: history,
      worker_manager: worker_manager,
      output_line: nil
    )
    allow(history).to receive(:db_path).and_return(source_db_path)
    allow(history).to receive(:close)
    allow(worker_manager).to receive(:pause_all)
    allow(worker_manager).to receive(:wait_until_all_paused).with(timeout: 5.0).and_return(true)
    allow(worker_manager).to receive(:resume_all)
    allow(File).to receive(:exist?).with(source_db_path).and_return(true)
    allow(File).to receive(:size).with(source_db_path).and_return(1024)
  end

  describe "#execute" do
    context "with default destination (timestamped)" do
      it "generates timestamp in YYYY-MM-DD-HHMMSS format" do
        freeze_time = Time.new(2025, 10, 30, 14, 30, 22)
        expected_path = "./memory-2025-10-30-143022.db"

        allow(Time).to receive(:now).and_return(freeze_time)
        allow(FileUtils).to receive(:cp)
        allow(File).to receive(:exist?).with(expected_path).and_return(true)
        allow(File).to receive(:size).with(expected_path).and_return(1024)

        command.execute("/backup")

        expect(FileUtils).to have_received(:cp).with(source_db_path, expected_path)
      end

      it "creates backup in current directory" do
        allow(Time).to receive(:now).and_return(Time.new(2025, 10, 30, 14, 30, 22))
        allow(FileUtils).to receive(:cp)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(source_db_path).and_return(true)
        allow(File).to receive(:exist?).with(%r{^\./memory-.*\.db$}).and_return(true)
        allow(File).to receive(:size).and_return(1024)

        result = command.execute("/backup")

        expect(result).to eq(:continue)
      end
    end

    context "with custom destination path" do
      it "uses the provided path" do
        custom_path = "/tmp/my-backup.db"

        allow(FileUtils).to receive(:cp)
        allow(File).to receive(:exist?).with(custom_path).and_return(true)
        allow(File).to receive(:size).with(custom_path).and_return(1024)

        command.execute("/backup #{custom_path}")

        expect(FileUtils).to have_received(:cp).with(source_db_path, custom_path)
      end

      it "expands home directory (~) in path" do
        custom_path = "~/backups/backup.db"
        expanded_path = File.expand_path(custom_path)

        allow(FileUtils).to receive(:cp)
        allow(File).to receive(:exist?).with(expanded_path).and_return(true)
        allow(File).to receive(:size).with(expanded_path).and_return(1024)

        command.execute("/backup #{custom_path}")

        expect(FileUtils).to have_received(:cp).with(source_db_path, expanded_path)
      end
    end

    context "worker coordination" do
      it "pauses workers before backup" do
        allow(FileUtils).to receive(:cp)
        allow(File).to receive_messages(exist?: true, size: 1024)

        command.execute("/backup")

        expect(worker_manager).to have_received(:pause_all).ordered
        expect(FileUtils).to have_received(:cp).ordered
      end

      it "waits for workers to pause" do
        allow(FileUtils).to receive(:cp)
        allow(File).to receive_messages(exist?: true, size: 1024)

        command.execute("/backup")

        expect(worker_manager).to have_received(:wait_until_all_paused).with(timeout: 5.0)
      end

      it "resumes workers after backup" do
        allow(FileUtils).to receive(:cp)
        allow(File).to receive_messages(exist?: true, size: 1024)

        command.execute("/backup")

        expect(FileUtils).to have_received(:cp).ordered
        expect(worker_manager).to have_received(:resume_all).ordered
      end
    end

    context "database connection management" do
      it "closes database before backup" do
        allow(FileUtils).to receive(:cp)
        allow(File).to receive_messages(exist?: true, size: 1024)

        command.execute("/backup")

        expect(history).to have_received(:close).ordered
        expect(FileUtils).to have_received(:cp).ordered
      end
    end

    context "backup verification" do
      it "verifies backup file exists" do
        backup_path = "./memory-2025-10-30-143022.db"

        allow(Time).to receive(:now).and_return(Time.new(2025, 10, 30, 14, 30, 22))
        allow(FileUtils).to receive(:cp)
        allow(File).to receive(:exist?).with(backup_path).and_return(false)

        expect(application).to receive(:output_line).with(/failed/i, type: :error)

        command.execute("/backup")
      end

      it "verifies backup file size matches source" do
        backup_path = "./memory-2025-10-30-143022.db"

        allow(Time).to receive(:now).and_return(Time.new(2025, 10, 30, 14, 30, 22))
        allow(FileUtils).to receive(:cp)
        allow(File).to receive(:exist?).with(backup_path).and_return(true)
        allow(File).to receive(:size).with(source_db_path).and_return(1000)
        allow(File).to receive(:size).with(backup_path).and_return(500)

        expect(application).to receive(:output_line).with(/size mismatch/i, type: :error)

        command.execute("/backup")
      end
    end

    context "error handling" do
      it "handles copy errors and resumes workers" do
        allow(FileUtils).to receive(:cp).and_raise(StandardError, "Disk full")

        expect(application).to receive(:output_line).with(/Backup failed: Disk full/i, type: :error)
        expect(worker_manager).to receive(:resume_all)

        command.execute("/backup")
      end
    end

    context "output messages" do
      it "displays success message with path, size, and timestamp" do
        backup_path = "./memory-2025-10-30-143022.db"
        freeze_time = Time.new(2025, 10, 30, 14, 30, 22)

        allow(Time).to receive(:now).and_return(freeze_time)
        allow(FileUtils).to receive(:cp)
        allow(File).to receive(:exist?).with(backup_path).and_return(true)
        allow(File).to receive(:size).with(source_db_path).and_return(1024)
        allow(File).to receive(:size).with(backup_path).and_return(1024)

        expect(application).to receive(:output_line).with(/Backup created successfully/i, type: :normal)
        expect(application).to receive(:output_line).with(/Path:.*#{Regexp.escape(backup_path)}/i, type: :normal)
        expect(application).to receive(:output_line).with(/Size:/i, type: :normal)

        command.execute("/backup")
      end

      it "formats file sizes correctly" do
        backup_path = "./memory-2025-10-30-143022.db"
        freeze_time = Time.new(2025, 10, 30, 14, 30, 22)

        allow(Time).to receive(:now).and_return(freeze_time)
        allow(File).to receive(:exist?).with(backup_path).and_return(true)

        # Test various file sizes (only small files that use FileUtils.cp)
        [
          [500, "500 B"],
          [2048, "2.0 KB"]
        ].each do |size, expected_format|
          allow(FileUtils).to receive(:cp)
          allow(File).to receive(:size).with(source_db_path).and_return(size)
          allow(File).to receive(:size).with(backup_path).and_return(size)

          expect(application).to receive(:output_line).with(/Size: #{Regexp.escape(expected_format)}/i, type: :normal)

          command.execute("/backup")
        end

        # Test large file sizes with mocked file operations
        [
          [1_048_576, "1.0 MB"],
          [2_147_483_648, "2.0 GB"]
        ].each do |size, expected_format|
          # Mock file I/O for large files
          input_file = instance_double(File)
          output_file = instance_double(File)

          allow(File).to receive(:size).with(source_db_path).and_return(size)
          allow(File).to receive(:size).with(backup_path).and_return(size)
          allow(File).to receive(:open).with(source_db_path, "rb").and_yield(input_file)
          allow(File).to receive(:open).with(backup_path, "wb").and_yield(output_file)
          allow(input_file).to receive(:read).and_return(nil) # EOF
          allow(output_file).to receive(:write)

          # Mock progress display (print statements)
          allow(command).to receive(:print)

          expect(application).to receive(:output_line).with(/Size: #{Regexp.escape(expected_format)}/i, type: :normal)

          command.execute("/backup")
        end
      end
    end

    context "progress bar" do
      it "does not show progress bar for files < 1 MB" do
        small_file_size = 500_000 # 500 KB

        allow(FileUtils).to receive(:cp)
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:size).with(source_db_path).and_return(small_file_size)
        allow(File).to receive(:size).with(%r{^\./memory-.*\.db$}).and_return(small_file_size)

        # Should NOT print progress indicators
        expect(application).not_to receive(:output_line).with(/\[.*\]/, type: :normal)

        command.execute("/backup")
      end

      it "shows progress bar for files > 1 MB" do
        large_file_size = 2_000_000 # 2 MB
        backup_path_pattern = %r{^\./memory-.*\.db$}

        # Mock file I/O for large files
        input_file = instance_double(File)
        output_file = instance_double(File)

        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:size).with(source_db_path).and_return(large_file_size)
        allow(File).to receive(:size).with(backup_path_pattern).and_return(large_file_size)
        allow(File).to receive(:open).with(source_db_path, "rb").and_yield(input_file)
        allow(File).to receive(:open).with(backup_path_pattern, "wb").and_yield(output_file)

        # Simulate reading chunks
        allow(input_file).to receive(:read).and_return(nil) # EOF
        allow(output_file).to receive(:write)

        # Mock progress display
        allow(command).to receive(:print)

        # Should use copy_with_progress instead of FileUtils.cp
        expect(FileUtils).not_to receive(:cp)

        command.execute("/backup")
      end
    end

    it "returns :continue" do
      allow(FileUtils).to receive(:cp)
      allow(File).to receive_messages(exist?: true, size: 1024)

      expect(command.execute("/backup")).to eq(:continue)
    end
  end
end
