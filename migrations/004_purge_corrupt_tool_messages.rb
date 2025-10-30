# frozen_string_literal: true

# Migration: Purge messages with corrupt JSON in tool-related fields
{
  version: 4,
  name: "purge_corrupt_tool_messages",
  up: lambda do |conn|
    # Find messages with potentially corrupt JSON fields
    result = conn.query(<<~SQL)
      SELECT id, role, tool_calls, tool_result, error
      FROM messages
      WHERE tool_calls IS NOT NULL
         OR tool_result IS NOT NULL
         OR error IS NOT NULL
    SQL

    corrupt_ids = []

    result.each do |row|
      message_id = row[0]
      row[1]
      tool_calls = row[2]
      tool_result = row[3]
      error = row[4]

      is_corrupt = false

      # Test each JSON field
      begin
        JSON.parse(tool_calls) if tool_calls
      rescue JSON::ParserError
        is_corrupt = true
      end

      begin
        JSON.parse(tool_result) if tool_result
      rescue JSON::ParserError
        is_corrupt = true
      end

      begin
        JSON.parse(error) if error
      rescue JSON::ParserError
        is_corrupt = true
      end

      # If corrupt and tool-related (role is 'tool' or has tool data), mark for deletion
      corrupt_ids << message_id if is_corrupt
    end

    if corrupt_ids.empty?
      puts "Migration 004: No corrupt messages found"
    else
      puts "Migration 004: Found #{corrupt_ids.length} message(s) with corrupt JSON"
      puts "  Deleting message IDs: #{corrupt_ids.join(', ')}"

      # Delete corrupt messages
      corrupt_ids.each do |id|
        conn.query("DELETE FROM messages WHERE id = #{id}")
      end

      puts "  ✓ Deleted #{corrupt_ids.length} corrupt message(s)"
    end
  end
}
