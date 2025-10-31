# Database Migration Guide

## Overview

Nu-Agent uses a simple, lightweight migration system for managing database schema changes. Migrations are versioned files containing SQL operations that transform your database schema.

## Migration Workflow

### 1. Generate a New Migration

Use the Rake task to generate a new migration file:

```bash
rake migration:generate NAME=create_users_table
```

This creates a timestamped file in `migrations/` directory:
```
migrations/008_create_users_table.rb
```

### 2. Edit the Migration

Open the generated file and add your SQL statements:

```ruby
# frozen_string_literal: true

# Migration: create_users_table
{
  version: 8,
  name: "create_users_table",
  up: lambda do |conn|
    # Create sequence for id generation
    conn.query("CREATE SEQUENCE IF NOT EXISTS users_id_seq START 1")

    # Create the users table
    conn.query(<<~SQL)
      CREATE TABLE users (
        id INTEGER PRIMARY KEY DEFAULT nextval('users_id_seq'),
        username VARCHAR NOT NULL,
        email VARCHAR NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    SQL

    # Add indexes
    conn.query(<<~SQL)
      CREATE INDEX IF NOT EXISTS idx_users_email
      ON users(email)
    SQL
  end
}
```

### 3. Apply Pending Migrations

Migrations are automatically applied when the application starts. The MigrationManager:
- Tracks the current schema version in the `schema_version` table
- Identifies pending migrations (version > current version)
- Applies them in order
- Updates the schema version after each successful migration

To manually trigger migrations during development:
```bash
# Start the application (migrations run automatically)
rake run
```

## Migration File Structure

Migrations are Ruby files that evaluate to a hash with three keys:

- `version`: Integer - Must match the filename prefix (e.g., 008)
- `name`: String - Descriptive name in snake_case
- `up`: Lambda - Receives database connection, executes SQL

## Naming Conventions

Migration names should be descriptive and follow snake_case:
- `create_table_name` - Creating a new table
- `add_column_to_table` - Adding a column
- `remove_column_from_table` - Removing a column
- `rename_column_in_table` - Renaming a column
- `add_index_to_table` - Adding an index

## Guardrails and Best Practices

### ⚠️ Safety Rules

1. **Always backup before destructive changes**
   - Migrations that DROP tables or columns are irreversible
   - Test migrations on a copy of production data first
   - Document rollback procedures for risky migrations

2. **Use idempotent SQL**
   - Use `CREATE TABLE IF NOT EXISTS` for table creation
   - Use `CREATE INDEX IF NOT EXISTS` for index creation
   - Use `CREATE SEQUENCE IF NOT EXISTS` for sequences
   - This allows safe re-application if a migration partially fails

3. **Version numbers must be sequential**
   - The generator automatically assigns the next version
   - Never manually edit version numbers
   - Never skip version numbers

4. **One logical change per migration**
   - Keep migrations focused on a single schema change
   - Multiple migrations are better than one complex migration
   - Easier to debug and rollback if needed

5. **Test before committing**
   - Apply the migration on a test database
   - Verify the schema changes are correct
   - Run application tests to ensure compatibility

### ✅ Good Practices

```ruby
# GOOD: Idempotent, clear, safe
{
  version: 9,
  name: "add_status_to_jobs",
  up: lambda do |conn|
    conn.query(<<~SQL)
      ALTER TABLE jobs
      ADD COLUMN IF NOT EXISTS status VARCHAR DEFAULT 'pending'
    SQL
  end
}
```

### ❌ Bad Practices

```ruby
# BAD: Not idempotent, will fail on re-run
{
  version: 9,
  name: "add_status_to_jobs",
  up: lambda do |conn|
    conn.query("ALTER TABLE jobs ADD COLUMN status VARCHAR")
  end
}

# BAD: Multiple unrelated changes
{
  version: 10,
  name: "various_schema_changes",
  up: lambda do |conn|
    conn.query("CREATE TABLE users ...")
    conn.query("DROP TABLE old_logs")
    conn.query("ALTER TABLE jobs ...")
  end
}
```

## Troubleshooting

### Migration Failed Midway

If a migration fails:
1. Check the error message in the logs
2. Fix the SQL in the migration file
3. Manually rollback any partial changes
4. The version will remain at the last successful migration
5. Re-run the application to retry

### Need to Rollback

Currently, the migration system does not support automatic rollback. To rollback:
1. Manually write SQL to reverse the changes
2. Execute it directly on the database
3. Update `schema_version` table to the previous version:
   ```sql
   DELETE FROM schema_version;
   INSERT INTO schema_version (version) VALUES (7);
   ```

### Check Current Schema Version

```ruby
# In Rails console or Ruby script
manager = Nu::Agent::MigrationManager.new(connection)
puts manager.current_version
```

### List Pending Migrations

```ruby
manager = Nu::Agent::MigrationManager.new(connection)
pending = manager.pending_migrations
pending.each { |m| puts "#{m[:version]}: #{m[:name]}" }
```

## DuckDB-Specific Considerations

Nu-Agent uses DuckDB, which has some differences from PostgreSQL/MySQL:

1. **Sequences**: Use `CREATE SEQUENCE` for auto-incrementing IDs
2. **Data Types**: DuckDB supports standard SQL types (INTEGER, VARCHAR, TIMESTAMP, FLOAT, etc.)
3. **Transactions**: Each migration runs in the context of the application's transaction handling
4. **IF NOT EXISTS**: DuckDB supports this for idempotent operations

## Migration History

Current migrations (as of v0.12):
- 001: Add embedding constraints
- 002: Setup VSS (Vector Similarity Search)
- 003: Drop source column
- 004: Purge corrupt tool messages
- 005: Cleanup orphaned embeddings
- 006: Create failed_jobs table
- 007: Create rag_retrieval_logs table

## Questions?

For migration issues or questions:
- Check the `spec/nu/agent/migration_manager_spec.rb` for usage examples
- Review existing migrations in `migrations/` directory
- Consult the MigrationManager source at `lib/nu/agent/migration_manager.rb`
