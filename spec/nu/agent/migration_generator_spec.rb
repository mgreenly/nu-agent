# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require_relative "../../../lib/nu/agent/migration_generator"

RSpec.describe Nu::Agent::MigrationGenerator do
  let(:migrations_dir) { File.join(Dir.pwd, "tmp", "test_gen_migrations") }
  let(:generator) { described_class.new(migrations_dir: migrations_dir) }

  before do
    FileUtils.mkdir_p(migrations_dir)
  end

  after do
    FileUtils.rm_rf(migrations_dir)
  end

  describe "#next_version" do
    it "returns 1 when no migrations exist" do
      expect(generator.next_version).to eq(1)
    end

    it "returns the next version based on existing migrations" do
      File.write(File.join(migrations_dir, "001_first_migration.rb"), "# migration")
      File.write(File.join(migrations_dir, "002_second_migration.rb"), "# migration")
      File.write(File.join(migrations_dir, "005_fifth_migration.rb"), "# migration")

      expect(generator.next_version).to eq(6)
    end

    it "handles migrations with leading zeros" do
      File.write(File.join(migrations_dir, "007_seventh_migration.rb"), "# migration")

      expect(generator.next_version).to eq(8)
    end
  end

  describe "#generate" do
    it "creates a migration file with the correct naming format" do
      file_path = generator.generate("create_users_table")

      expect(File.exist?(file_path)).to be true
      expect(File.basename(file_path)).to match(/^\d{3}_create_users_table\.rb$/)
    end

    it "includes the correct version number in the filename" do
      File.write(File.join(migrations_dir, "001_first.rb"), "# migration")
      File.write(File.join(migrations_dir, "002_second.rb"), "# migration")

      file_path = generator.generate("third_migration")

      expect(File.basename(file_path)).to eq("003_third_migration.rb")
    end

    it "generates a file with version, name, and up lambda" do
      file_path = generator.generate("add_column_to_users")
      content = File.read(file_path)

      expect(content).to include("version: 1")
      expect(content).to include('name: "add_column_to_users"')
      expect(content).to include("up: lambda do |conn|")
      expect(content).to include("# Add your migration SQL here")
      expect(content).to include("conn.query(<<~SQL)")
    end

    it "includes frozen_string_literal comment" do
      file_path = generator.generate("test_migration")
      content = File.read(file_path)

      expect(content).to start_with("# frozen_string_literal: true\n")
    end

    it "includes a descriptive comment with the migration name" do
      file_path = generator.generate("create_posts_table")
      content = File.read(file_path)

      expect(content).to include("# Migration: create_posts_table")
    end

    it "raises an error if migration name is empty" do
      expect { generator.generate("") }.to raise_error(ArgumentError, /Migration name cannot be empty/)
    end

    it "raises an error if migration name contains invalid characters" do
      expect { generator.generate("create table!") }.to raise_error(ArgumentError, /Invalid migration name/)
    end

    it "converts migration name to snake_case format" do
      file_path = generator.generate("CreateUsersTable")

      expect(File.basename(file_path)).to eq("001_create_users_table.rb")
    end

    it "returns the full path to the generated migration file" do
      file_path = generator.generate("test_migration")

      expect(file_path).to eq(File.join(migrations_dir, "001_test_migration.rb"))
    end

    it "allows same migration name with different versions (like Rails)" do
      file1 = generator.generate("create_users")
      file2 = generator.generate("create_users")

      expect(File.basename(file1)).to eq("001_create_users.rb")
      expect(File.basename(file2)).to eq("002_create_users.rb")
      expect(File.exist?(file1)).to be true
      expect(File.exist?(file2)).to be true
    end
  end

  describe "#template" do
    it "generates valid Ruby code that can be evaluated" do
      file_path = generator.generate("test_migration")
      content = File.read(file_path)

      expect { eval(content) }.not_to raise_error # rubocop:disable Security/Eval
    end

    it "generates a hash with the correct structure" do
      file_path = generator.generate("test_migration")
      content = File.read(file_path)
      migration = eval(content) # rubocop:disable Security/Eval

      expect(migration).to be_a(Hash)
      expect(migration).to have_key(:version)
      expect(migration).to have_key(:name)
      expect(migration).to have_key(:up)
      expect(migration[:up]).to be_a(Proc)
    end
  end
end
