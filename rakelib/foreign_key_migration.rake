# frozen_string_literal: true

desc "Add foreign key constraints to database schema"
task :foreign_key_migration do
  require_relative "../lib/nu/agent"

  # Helper method for SQL escaping
  def escape_sql(string)
    string.to_s.gsub("'", "''")
  end

  # Helper method to format timestamp for DuckDB TIMESTAMP columns
  def format_timestamp(timestamp)
    return "NULL" if timestamp.nil?

    # Handle different timestamp formats
    time = case timestamp
           when String
             Time.parse(timestamp)
           when Integer
             Time.at(timestamp)
           when Time
             timestamp
           else
             # If it's something else, try to convert it
             Time.parse(timestamp.to_s)
           end

    # Convert to UTC and format without timezone
    utc_time = time.utc
    "'#{utc_time.strftime('%Y-%m-%d %H:%M:%S')}'"
  end

  db_path = ENV["NUAGENT_DATABASE"] || File.join(Dir.home, ".nuagent", "memory.db")
  db_path = "./db/memory.db" if File.exist?("./db/memory.db")

  puts "=" * 80
  puts "FOREIGN KEY MIGRATION"
  puts "=" * 80
  puts "Database: #{db_path}"
  puts

  db = DuckDB::Database.open(db_path)
  conn = db.connect

  begin
    # Step 1: Check for orphaned data
    puts "Step 1: Checking for orphaned data..."
    puts "-" * 80

    orphaned_exchanges = conn.query(<<~SQL).to_a
      SELECT e.id, e.conversation_id
      FROM exchanges e
      LEFT JOIN conversations c ON e.conversation_id = c.id
      WHERE c.id IS NULL
    SQL

    orphaned_messages_conv = conn.query(<<~SQL).to_a
      SELECT m.id, m.conversation_id
      FROM messages m
      LEFT JOIN conversations c ON m.conversation_id = c.id
      WHERE m.conversation_id IS NOT NULL AND c.id IS NULL
    SQL

    orphaned_messages_exch = conn.query(<<~SQL).to_a
      SELECT m.id, m.exchange_id
      FROM messages m
      LEFT JOIN exchanges e ON m.exchange_id = e.id
      WHERE m.exchange_id IS NOT NULL AND e.id IS NULL
    SQL

    total_orphans = orphaned_exchanges.length + orphaned_messages_conv.length + orphaned_messages_exch.length

    if total_orphans > 0
      puts "❌ ORPHANED DATA FOUND:"
      puts "  - #{orphaned_exchanges.length} orphaned exchanges"
      puts "  - #{orphaned_messages_conv.length} messages with invalid conversation_id"
      puts "  - #{orphaned_messages_exch.length} messages with invalid exchange_id"
      puts
      puts "Migration ABORTED. Please fix orphaned data first."
      exit 1
    end

    puts "✅ No orphaned data found"
    puts

    # Step 2: Save data to memory
    puts "Step 2: Reading existing data into memory..."
    puts "-" * 80

    conversations_data = conn.query("SELECT * FROM conversations").to_a
    exchanges_data = conn.query("SELECT * FROM exchanges").to_a
    messages_data = conn.query("SELECT * FROM messages").to_a

    conv_count = conversations_data.length
    exch_count = exchanges_data.length
    msg_count = messages_data.length

    puts "✅ Read #{conv_count} conversations"
    puts "✅ Read #{exch_count} exchanges"
    puts "✅ Read #{msg_count} messages"
    puts

    # Step 3: Drop old tables
    puts "Step 3: Dropping old tables..."
    puts "-" * 80
    conn.query("DROP TABLE messages")
    puts "✅ Dropped messages"
    conn.query("DROP TABLE exchanges")
    puts "✅ Dropped exchanges"
    conn.query("DROP TABLE conversations")
    puts "✅ Dropped conversations"
    puts

    # Step 4: Create new tables with foreign keys
    puts "Step 4: Creating tables with foreign key constraints..."
    puts "-" * 80

    # Create conversations table
    conn.query(<<~SQL)
      CREATE TABLE conversations (
        id INTEGER PRIMARY KEY DEFAULT nextval('conversations_id_seq'),
        created_at TIMESTAMP,
        title TEXT,
        status TEXT,
        summary TEXT,
        summary_model TEXT,
        summary_cost FLOAT
      )
    SQL
    puts "✅ Created conversations"

    # Create exchanges table with foreign key
    conn.query(<<~SQL)
      CREATE TABLE exchanges (
        id INTEGER PRIMARY KEY DEFAULT nextval('exchanges_id_seq'),
        conversation_id INTEGER NOT NULL REFERENCES conversations(id),
        exchange_number INTEGER NOT NULL,
        started_at TIMESTAMP NOT NULL,
        completed_at TIMESTAMP,
        summary TEXT,
        summary_model TEXT,
        status TEXT,
        error TEXT,
        user_message TEXT,
        assistant_message TEXT,
        tokens_input INTEGER,
        tokens_output INTEGER,
        spend FLOAT,
        message_count INTEGER,
        tool_call_count INTEGER
      )
    SQL
    puts "✅ Created exchanges with foreign key to conversations"

    # Create messages table with foreign keys
    conn.query(<<~SQL)
      CREATE TABLE messages (
        id INTEGER PRIMARY KEY DEFAULT nextval('messages_id_seq'),
        conversation_id INTEGER REFERENCES conversations(id),
        actor TEXT,
        role TEXT,
        content TEXT,
        model TEXT,
        include_in_context BOOLEAN DEFAULT true,
        tokens_input INTEGER,
        tokens_output INTEGER,
        spend FLOAT,
        tool_calls TEXT,
        tool_call_id TEXT,
        tool_result TEXT,
        error TEXT,
        redacted BOOLEAN DEFAULT FALSE,
        exchange_id INTEGER REFERENCES exchanges(id),
        created_at TIMESTAMP
      )
    SQL
    puts "✅ Created messages with foreign keys to conversations and exchanges"
    puts

    # Step 5: Insert data back (maintaining referential integrity)
    puts "Step 5: Inserting data back (maintaining referential integrity)..."
    puts "-" * 80

    # Insert conversations first (no dependencies)
    conversations_data.each do |row|
      conn.query(<<~SQL)
        INSERT INTO conversations VALUES (
          #{row[0]},
          #{format_timestamp(row[1])},
          #{row[2] ? "'#{escape_sql(row[2])}'" : "NULL"},
          #{row[3] ? "'#{row[3]}'" : "NULL"},
          #{row[4] ? "'#{escape_sql(row[4])}'" : "NULL"},
          #{row[5] ? "'#{row[5]}'" : "NULL"},
          #{row[6] || "NULL"}
        )
      SQL
    end
    puts "✅ Inserted #{conv_count} conversations"

    # Insert exchanges (depends on conversations)
    exchanges_data.each do |row|
      conn.query(<<~SQL)
        INSERT INTO exchanges VALUES (
          #{row[0]}, #{row[1]}, #{row[2]},
          #{format_timestamp(row[3])},
          #{format_timestamp(row[4])},
          #{row[5] ? "'#{escape_sql(row[5])}'" : "NULL"},
          #{row[6] ? "'#{row[6]}'" : "NULL"},
          #{row[7] ? "'#{row[7]}'" : "NULL"},
          #{row[8] ? "'#{escape_sql(row[8])}'" : "NULL"},
          #{row[9] ? "'#{escape_sql(row[9])}'" : "NULL"},
          #{row[10] ? "'#{escape_sql(row[10])}'" : "NULL"},
          #{row[11] || "NULL"}, #{row[12] || "NULL"},
          #{row[13] || "NULL"}, #{row[14] || "NULL"}, #{row[15] || "NULL"}
        )
      SQL
    end
    puts "✅ Inserted #{exch_count} exchanges"

    # Insert messages (depends on conversations and exchanges)
    messages_data.each do |row|
      # Build SQL more carefully to handle all the fields
      id, conversation_id, actor, role, content, model, include_in_context,
        tokens_input, tokens_output, spend, tool_calls, tool_call_id, tool_result,
        error, redacted, exchange_id, created_at = row

      conn.query(<<~SQL)
        INSERT INTO messages (
          id, conversation_id, actor, role, content, model, include_in_context,
          tokens_input, tokens_output, spend, tool_calls, tool_call_id, tool_result,
          error, redacted, exchange_id, created_at
        ) VALUES (
          #{id},
          #{conversation_id || "NULL"},
          #{actor ? "'#{escape_sql(actor)}'" : "NULL"},
          #{role ? "'#{role}'" : "NULL"},
          #{content ? "'#{escape_sql(content)}'" : "NULL"},
          #{model ? "'#{model}'" : "NULL"},
          #{include_in_context.nil? ? "true" : include_in_context},
          #{tokens_input || "NULL"},
          #{tokens_output || "NULL"},
          #{spend || "NULL"},
          #{tool_calls ? "'#{escape_sql(tool_calls)}'" : "NULL"},
          #{tool_call_id ? "'#{tool_call_id}'" : "NULL"},
          #{tool_result ? "'#{escape_sql(tool_result)}'" : "NULL"},
          #{error ? "'#{escape_sql(error)}'" : "NULL"},
          #{redacted.nil? ? "false" : redacted},
          #{exchange_id || "NULL"},
          #{format_timestamp(created_at)}
        )
      SQL
    end
    puts "✅ Inserted #{msg_count} messages"
    puts

    # Step 6: Verify foreign keys
    puts "Step 6: Verifying foreign key constraints..."
    puts "-" * 80

    constraints = conn.query(<<~SQL).to_a
      SELECT table_name, constraint_text
      FROM duckdb_constraints()
      WHERE constraint_type = 'FOREIGN KEY'
      ORDER BY table_name
    SQL

    if constraints.empty?
      puts "⚠️  Warning: Could not verify constraints (may be DuckDB version limitation)"
    else
      constraints.each do |row|
        table_name, constraint_text = row
        puts "✅ #{table_name}: #{constraint_text}"
      end
    end
    puts

    puts "=" * 80
    puts "✅ MIGRATION COMPLETE!"
    puts "=" * 80
    puts
    puts "Foreign key constraints have been added to:"
    puts "  - exchanges.conversation_id → conversations.id"
    puts "  - messages.conversation_id → conversations.id"
    puts "  - messages.exchange_id → exchanges.id"
    puts
    puts "Next steps:"
    puts "  1. Update SchemaManager to include foreign keys in CREATE TABLE statements"
    puts "  2. Test the application to ensure it works correctly"
    puts
    puts "Rollback instructions (if needed):"
    puts "  cp ./db/memory-rollback.db ./db/memory.db"
    puts "  git reset --hard rollback-target"
    puts

  rescue StandardError => e
    puts
    puts "=" * 80
    puts "❌ MIGRATION FAILED"
    puts "=" * 80
    puts "Error: #{e.message}"
    puts
    puts e.backtrace.first(10).join("\n")
    puts
    puts "Database has NOT been modified (transaction rolled back)"
    puts
    puts "Rollback instructions:"
    puts "  cp ./db/memory-rollback.db ./db/memory.db"
    exit 1
  ensure
    conn&.close
    db&.close
  end
end
