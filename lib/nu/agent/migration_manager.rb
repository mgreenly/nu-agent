# frozen_string_literal: true

module Nu
  module Agent
    # Manages database schema migrations
    class MigrationManager
      def initialize(connection)
        @connection = connection
      end

      # Get the current schema version from the database
      def current_version
        ensure_schema_version_table

        result = @connection.query("SELECT version FROM schema_version LIMIT 1")
        row = result.to_a.first
        row ? row[0] : 0
      rescue StandardError
        0
      end

      # Ensure the schema_version table exists
      def ensure_schema_version_table
        @connection.query(<<~SQL)
          CREATE TABLE IF NOT EXISTS schema_version (
            version INTEGER NOT NULL,
            applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          )
        SQL
      end

      # Update the schema version in the database
      def update_version(version)
        @connection.query("DELETE FROM schema_version")
        @connection.query(<<~SQL)
          INSERT INTO schema_version (version, applied_at)
          VALUES (#{version.to_i}, CURRENT_TIMESTAMP)
        SQL
      end

      # Get list of pending migrations that need to be applied
      def pending_migrations
        migrations_dir = File.join(Dir.pwd, "migrations")
        return [] unless File.directory?(migrations_dir)

        current = current_version
        migration_files = Dir.glob(File.join(migrations_dir, "*.rb"))

        migrations = migration_files.map do |file|
          basename = File.basename(file, ".rb")
          match = basename.match(/^(\d+)_(.+)$/)
          next unless match

          version = match[1].to_i
          name = match[2]

          {
            version: version,
            name: name,
            path: file
          }
        end.compact

        migrations.select { |m| m[:version] > current }.sort_by { |m| m[:version] }
      end

      # Run a single migration
      def run_migration(migration)
        ensure_schema_version_table

        begin
          migration[:up].call(@connection)
          update_version(migration[:version])
        rescue StandardError => e
          # Rollback version on failure
          update_version(current_version)
          raise e
        end
      end

      # Run all pending migrations
      def run_pending_migrations
        migrations = pending_migrations
        return if migrations.empty?

        migrations.each do |migration_info|
          # Load and execute the migration file
          migration_code = File.read(migration_info[:path])
          migration = eval(migration_code) # rubocop:disable Security/Eval

          run_migration(migration)
        end
      end
    end
  end
end
