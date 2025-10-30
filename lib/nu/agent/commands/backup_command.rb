# frozen_string_literal: true

require_relative "base_command"
require "fileutils"
require "time"

module Nu
  module Agent
    module Commands
      # Command to create database backups
      class BackupCommand < BaseCommand
        # Execute the backup command
        # @param input [String] the raw command input (e.g., "/backup" or "/backup /path/to/backup.db")
        # @return [Symbol] :continue
        def execute(input)
          destination = parse_destination(input)

          # Pause workers and close database
          app.worker_manager.pause_all
          app.worker_manager.wait_until_all_paused(timeout: 5.0)
          app.history.close

          # Perform backup
          begin
            FileUtils.cp(app.history.db_path, destination)

            # Verify backup
            if backup_valid?(destination)
              display_success(destination)
            else
              app.output_line("Backup verification failed", type: :error)
            end
          rescue StandardError => e
            app.output_line("Backup failed: #{e.message}", type: :error)
          ensure
            # Resume workers
            app.worker_manager.resume_all
          end

          :continue
        end

        private

        # Parse the destination path from the input string
        # @param input [String] the command input
        # @return [String] the destination path
        def parse_destination(input)
          # Remove the command name and extract the path
          parts = input.strip.split(/\s+/, 2)
          if parts.length > 1 && !parts[1].empty?
            # Custom destination provided
            File.expand_path(parts[1])
          else
            # Generate default timestamped filename
            generate_default_destination
          end
        end

        # Generate default destination path with timestamp
        # @return [String] path like "./memory-2025-10-30-143022.db"
        def generate_default_destination
          timestamp = Time.now.strftime("%Y-%m-%d-%H%M%S")
          "./memory-#{timestamp}.db"
        end

        # Check if the backup was created successfully
        # @param destination [String] the backup file path
        # @return [Boolean] true if backup is valid
        def backup_valid?(destination)
          unless File.exist?(destination)
            app.output_line("Backup file was not created", type: :error)
            return false
          end

          source_size = File.size(app.history.db_path)
          dest_size = File.size(destination)

          unless source_size == dest_size
            app.output_line("Backup file size mismatch (expected #{source_size}, got #{dest_size})", type: :error)
            return false
          end

          true
        end

        # Display success message with backup details
        # @param destination [String] the backup file path
        def display_success(destination)
          file_size = File.size(destination)
          timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S")

          app.output_line("Backup created successfully:", type: :normal)
          app.output_line("  Path: #{destination}", type: :normal)
          app.output_line("  Size: #{format_bytes(file_size)}", type: :normal)
          app.output_line("  Time: #{timestamp}", type: :normal)
        end

        # Format bytes into human-readable string
        # @param bytes [Integer] number of bytes
        # @return [String] formatted string (e.g., "1.5 MB")
        def format_bytes(bytes)
          if bytes < 1024
            "#{bytes} B"
          elsif bytes < 1_048_576
            "#{(bytes / 1024.0).round(1)} KB"
          elsif bytes < 1_073_741_824
            "#{(bytes / 1_048_576.0).round(1)} MB"
          else
            "#{(bytes / 1_073_741_824.0).round(1)} GB"
          end
        end
      end
    end
  end
end
