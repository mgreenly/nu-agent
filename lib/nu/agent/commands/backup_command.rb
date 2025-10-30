# frozen_string_literal: true

require_relative "base_command"
require "fileutils"
require "shellwords"
require "time"

module Nu
  module Agent
    module Commands
      # Command to create database backups with progress tracking
      #
      # The BackupCommand provides a safe way to create backups of the conversation
      # database while ensuring data integrity. It coordinates with background workers
      # and database connections to create consistent backups.
      #
      # @example Default backup (timestamped in current directory)
      #   /backup
      #   # Creates: ./memory-2025-10-30-143022.db
      #
      # @example Custom destination path
      #   /backup ~/backups/important-backup.db
      #   # Creates: /home/user/backups/important-backup.db
      #
      # Features:
      # - Automatic timestamped backups (YYYY-MM-DD-HHMMSS format)
      # - Custom destination path support with tilde (~) expansion
      # - Progress bar for files larger than 1 MB
      # - Pre-flight validation (source exists, disk space, permissions)
      # - Worker coordination (pause before backup, resume after)
      # - Database connection management (close before, reopen after)
      # - Backup verification (file existence and size matching)
      # - Comprehensive error handling with clear messages
      #
      # Safety guarantees:
      # - Workers are always resumed, even if backup fails
      # - Database is always reopened, even if backup fails
      # - Pre-flight checks run before pausing workers (fail fast)
      #
      class BackupCommand < BaseCommand
        # Execute the backup command
        # @param input [String] the raw command input (e.g., "/backup" or "/backup /path/to/backup.db")
        # @return [Symbol] :continue
        def execute(input)
          destination = parse_destination(input)

          # Pre-flight validation before pausing workers
          error_message = validate_backup(destination)
          if error_message
            app.output_line(error_message, type: :error)
            return :continue
          end

          pause_workers_and_close_database
          perform_backup(destination)
          :continue
        end

        private

        # Pause workers and close database connections
        def pause_workers_and_close_database
          app.worker_manager.pause_all
          app.worker_manager.wait_until_all_paused(timeout: 5.0)
          app.history.close
        end

        # Perform the backup operation with error handling
        # @param destination [String] the backup file path
        def perform_backup(destination)
          copy_with_progress(app.history.db_path, destination)
          verify_and_report(destination)
        rescue StandardError => e
          app.output_line("Backup failed: #{e.message}", type: :error)
        ensure
          reopen_database_and_resume_workers
        end

        # Verify backup and report results
        # @param destination [String] the backup file path
        def verify_and_report(destination)
          if backup_valid?(destination)
            display_success(destination)
          else
            app.output_line("Backup verification failed", type: :error)
          end
        end

        # Reopen database and resume workers
        def reopen_database_and_resume_workers
          app.reopen_database
          app.worker_manager.resume_all
        end

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

        # Validate backup pre-flight checks
        # @param destination [String] the backup destination path
        # @return [String, nil] error message if validation fails, nil if all checks pass
        def validate_backup(destination)
          source_path = app.history.db_path

          # Check source exists
          return "Database file not found: #{source_path}" unless File.exist?(source_path)

          # Check source is readable
          return "Cannot read database file: #{source_path}" unless File.readable?(source_path)

          # Check/create destination directory
          dest_dir = File.dirname(destination)
          unless Dir.exist?(dest_dir)
            begin
              FileUtils.mkdir_p(dest_dir)
            rescue StandardError => e
              return "Cannot create destination directory: #{e.message}"
            end
          end

          # Check destination is writable
          return "Destination directory is not writable: #{dest_dir}" unless File.writable?(dest_dir)

          # Check disk space
          source_size = File.size(source_path)
          available_space = get_available_space(dest_dir)
          if available_space && available_space < source_size
            return "Insufficient disk space (need #{format_bytes(source_size)}, " \
                   "have #{format_bytes(available_space)})"
          end

          nil # All checks passed
        end

        # Get available disk space for a path
        # @param path [String] directory path to check
        # @return [Integer, nil] available bytes, or nil if cannot be determined
        def get_available_space(path)
          # Use df command to check available space
          result = `df -B1 #{Shellwords.escape(path)} 2>/dev/null | tail -1 | awk '{print $4}'`
          result.strip.to_i
        rescue StandardError
          nil # Return nil if cannot determine space
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

        # Copy file with optional progress bar for large files
        # @param source [String] source file path
        # @param destination [String] destination file path
        # @param threshold [Integer] file size threshold for progress bar (default: 1 MB)
        def copy_with_progress(source, destination, threshold: 1_048_576)
          file_size = File.size(source)

          # Use simple copy for small files
          if file_size < threshold
            FileUtils.cp(source, destination)
            return
          end

          # Show progress updates for large files (output as regular lines via console queue)
          app.output_line("Copying database... (#{format_bytes(file_size)})", type: :normal)
          bytes_copied = 0
          update_interval = 1_048_576 # 1 MB intervals for progress updates
          last_update = 0

          File.open(source, "rb") do |input|
            File.open(destination, "wb") do |output|
              while (chunk = input.read(8192)) # 8 KB chunks
                output.write(chunk)
                bytes_copied += chunk.size

                if bytes_copied - last_update >= update_interval
                  display_progress(bytes_copied, file_size)
                  last_update = bytes_copied
                end
              end
            end
          end

          # Show completion
          display_progress(bytes_copied, file_size) if bytes_copied > last_update
        end

        # Display progress update
        # @param current [Integer] bytes copied so far
        # @param total [Integer] total bytes to copy
        def display_progress(current, total)
          percent = (current.to_f / total * 100).to_i
          current_formatted = format_bytes(current)
          total_formatted = format_bytes(total)

          app.output_line("  Progress: #{percent}% (#{current_formatted} / #{total_formatted})", type: :normal)
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
