# frozen_string_literal: true

require "fileutils"

module Nu
  module Agent
    # Generates new migration files with timestamped filenames and templates
    class MigrationGenerator
      attr_reader :migrations_dir

      def initialize(migrations_dir: nil)
        @migrations_dir = migrations_dir || File.join(Dir.pwd, "migrations")
      end

      # Get the next version number based on existing migrations
      def next_version
        return 1 unless Dir.exist?(@migrations_dir)

        migration_files = Dir.glob(File.join(@migrations_dir, "*.rb"))
        return 1 if migration_files.empty?

        versions = migration_files.map do |file|
          basename = File.basename(file, ".rb")
          match = basename.match(/^(\d+)_/)
          match ? match[1].to_i : 0
        end

        versions.max + 1
      end

      # Generate a new migration file
      def generate(name)
        raise ArgumentError, "Migration name cannot be empty" if name.nil? || name.strip.empty?

        normalized_name = normalize_name(name)
        validate_name!(normalized_name)

        version = next_version
        filename = format("%<version>03d_%<name>s.rb", version: version, name: normalized_name)
        file_path = File.join(@migrations_dir, filename)

        FileUtils.mkdir_p(@migrations_dir)
        File.write(file_path, template(version, normalized_name))

        file_path
      end

      private

      # Normalize migration name to snake_case
      def normalize_name(name)
        name
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .tr("-", "_")
          .downcase
      end

      # Validate migration name format
      def validate_name!(name)
        return if name.match?(/^[a-z0-9_]+$/)

        raise ArgumentError, "Invalid migration name: '#{name}'. Use only lowercase letters, numbers, and underscores."
      end

      # Generate migration file template
      def template(version, name)
        <<~RUBY
          # frozen_string_literal: true

          # Migration: #{name}
          {
            version: #{version},
            name: "#{name}",
            up: lambda do |conn|
              # Add your migration SQL here
              # Example:
              # conn.query(<<~SQL)
              #   CREATE TABLE example (
              #     id INTEGER PRIMARY KEY,
              #     name VARCHAR NOT NULL
              #   )
              # SQL
            end
          }
        RUBY
      end
    end
  end
end
