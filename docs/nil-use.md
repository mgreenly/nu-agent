# Nil Usage Analysis

This document analyzes the use of `nil` in the codebase and the use of `NULL` in the database.

## Code Analysis

The codebase uses `nil` in several places, but it is handled safely. For example, in `lib/nu/agent/tool_call_orchestrator.rb`, the `system_prompt` is checked for `nil` before being used.

```ruby
send_params[:system_prompt] = system_prompt if system_prompt
```

In `lib/nu/agent/clients/openai.rb`, the `system_prompt` is also checked for `nil`.

```ruby
formatted << { role: "system", content: system_prompt } if system_prompt && !system_prompt.empty?
```

## Database Analysis

The database schema has several columns that can be `NULL`. This is handled safely in the code. For example, in `lib/nu/agent/conversation_repository.rb`, the `update_conversation_summary` method uses `cost || 'NULL'` to handle `nil` values.

```ruby
def update_conversation_summary(conversation_id:, summary:, model:, cost: nil)
  @connection.query(<<~SQL)
    UPDATE conversations
    SET summary = '#{escape_sql(summary)}',
        summary_model = '#{escape_sql(model)}',
        summary_cost = #{cost || 'NULL'}
    WHERE id = #{conversation_id}
  SQL
end
```

The `get_unsummarized_conversations` method explicitly queries for `NULL` values in the `summary` column.

```ruby
def get_unsummarized_conversations(exclude_id:)
  result = @connection.query(<<~SQL)
    SELECT id, created_at
    FROM conversations
    WHERE summary IS NULL
      AND id != #{exclude_id}
    ORDER BY id DESC
  SQL

  result.map do |row|
    {
      "id" => row[0],
      "created_at" => row[1]
    }
  end
end
```

## Recommendations

While `nil` is handled safely, there are opportunities to refactor the code to avoid using `nil`.

*   **Optional Fields**: For optional fields like `summary` in the `conversations` table, a Null Object Pattern could be used. A `NullConversation` class could be created with default values for the summary-related fields, which would prevent `nil` checks.
*   **Database Constraints**: Adding `NOT NULL` constraints to columns that should not be `NULL` would enforce data integrity at the database level. For example, `created_at` in the `conversations` table could be made non-nullable.
*   **Default Values**: Using default values in the database schema for columns that can have a sensible default would reduce the need for `nil` checks in the code.
