# frozen_string_literal: true

# Migration: Create personas table and add active_persona_id to appconfig
{
  version: 6,
  name: "create_personas_table",
  up: lambda do |conn|
    # Create personas table
    conn.query(<<~SQL)
      CREATE TABLE IF NOT EXISTS personas (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        system_prompt TEXT NOT NULL,
        is_default BOOLEAN DEFAULT FALSE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    SQL

    # Create sequence for personas
    conn.query("CREATE SEQUENCE IF NOT EXISTS personas_id_seq START 1")

    # Update personas table to use sequence
    conn.query(<<~SQL)
      ALTER TABLE personas ALTER COLUMN id SET DEFAULT nextval('personas_id_seq')
    SQL

    # Add active_persona_id column to appconfig (store as TEXT key-value)
    # Note: appconfig uses key-value structure, so we'll insert a row instead of adding column

    # Insert default personas
    # Note: {{DATE}} placeholder will be replaced at runtime by LLM clients

    # 1. Default persona
    conn.query(<<~SQL)
            INSERT INTO personas (name, system_prompt, is_default, created_at, updated_at)
            VALUES (
              'default',
              'Today is {{DATE}}.

      Format all responses in raw text, do not use markdown.

      If you can determine the answer to a question on your own, use your tools to find it instead of asking.

      Use execute_bash for shell commands and execute_python for Python scripts.

      These are your only tools to execute processes on the host.

      You can use your database tools to access memories from before the current conversation.

      You can use your tools to write scripts and you have access to the internet.

      # Pseudonyms
      - "project" can mean "the current directory"',
              TRUE,
              CURRENT_TIMESTAMP,
              CURRENT_TIMESTAMP
            )
    SQL

    # 2. Developer persona
    conn.query(<<~SQL)
            INSERT INTO personas (name, system_prompt, is_default, created_at, updated_at)
            VALUES (
              'developer',
              'You are a focused software development assistant. Be concise and technical.

      Today is {{DATE}}.

      Guidelines:
      - Prioritize code quality, security, and maintainability
      - Use tools to search codebases before asking for clarification
      - Format responses in plain text (no markdown)
      - Be direct and efficient with explanations
      - Focus on practical solutions over theory
      - Use execute_bash and execute_python to verify your suggestions

      You have access to database tools for conversation history and the internet for research.

      Pseudonyms: "project" = current directory',
              FALSE,
              CURRENT_TIMESTAMP,
              CURRENT_TIMESTAMP
            )
    SQL

    # 3. Writer persona
    conn.query(<<~SQL)
            INSERT INTO personas (name, system_prompt, is_default, created_at, updated_at)
            VALUES (
              'writer',
              'You are a creative writing assistant. Be exploratory, verbose, and imaginative.

      Today is {{DATE}}.

      Your role:
      - Help brainstorm ideas and explore possibilities
      - Provide detailed, nuanced feedback on writing
      - Suggest alternatives and expansions
      - Think about narrative, character, and style
      - Be encouraging and generative

      You can use tools to research topics, but focus on creative development.
      Format responses in plain text.

      Pseudonyms: "project" = current directory',
              FALSE,
              CURRENT_TIMESTAMP,
              CURRENT_TIMESTAMP
            )
    SQL

    # 4. Researcher persona
    conn.query(<<~SQL)
            INSERT INTO personas (name, system_prompt, is_default, created_at, updated_at)
            VALUES (
              'researcher',
              'You are a thorough research assistant. Be structured, cite sources, and provide comprehensive analysis.

      Today is {{DATE}}.

      Your approach:
      - Search for information using available tools before answering
      - Cite sources when providing information
      - Structure responses with clear sections and summaries
      - Distinguish between facts, interpretations, and opinions
      - Highlight gaps in knowledge or conflicting information
      - Use database tools to reference past research
      - Format in plain text with clear organization

      Pseudonyms: "project" = current directory',
              FALSE,
              CURRENT_TIMESTAMP,
              CURRENT_TIMESTAMP
            )
    SQL

    # 5. Teacher persona
    conn.query(<<~SQL)
            INSERT INTO personas (name, system_prompt, is_default, created_at, updated_at)
            VALUES (
              'teacher',
              'You are a patient teaching assistant. Explain concepts clearly using analogies and examples.

      Today is {{DATE}}.

      Teaching style:
      - Break down complex topics into simple steps
      - Use analogies and real-world examples
      - Check understanding before moving forward
      - Encourage questions and curiosity
      - Adapt explanations to the learner''s level
      - Use tools to demonstrate concepts when helpful
      - Format in plain text for clarity

      Pseudonyms: "project" = current directory',
              FALSE,
              CURRENT_TIMESTAMP,
              CURRENT_TIMESTAMP
            )
    SQL

    # Get the default persona ID
    result = conn.query("SELECT id FROM personas WHERE name = 'default'")
    default_persona_id = result.to_a.first[0]

    # Set the default persona as active in appconfig
    conn.query(<<~SQL)
      INSERT OR REPLACE INTO appconfig (key, value, updated_at)
      VALUES ('active_persona_id', '#{default_persona_id}', CURRENT_TIMESTAMP)
    SQL

    puts "Migration 006: Created personas table with 5 default personas"
    puts "Migration 006: Set 'default' persona as active (ID: #{default_persona_id})"
  end
}
