# frozen_string_literal: true

module Nu
  module Agent
    # Manages CRUD operations for agent personas
    class PersonaManager
      NAME_REGEX = /^[a-z0-9_-]+$/
      MAX_NAME_LENGTH = 50

      def initialize(connection)
        @connection = connection
      end

      # Returns array of all personas ordered by name
      def list
        result = @connection.query(<<~SQL)
          SELECT id, name, system_prompt, is_default, created_at, updated_at
          FROM personas
          ORDER BY name
        SQL

        result.to_a
      end

      # Returns persona hash or nil if not found
      def get(name)
        result = @connection.query(<<~SQL, [name])
          SELECT id, name, system_prompt, is_default, created_at, updated_at
          FROM personas
          WHERE name = ?
        SQL

        personas = result.to_a
        personas.empty? ? nil : personas.first
      end

      # Creates a new persona and returns it
      def create(name:, system_prompt:)
        validate_name(name)
        validate_system_prompt(system_prompt)

        begin
          @connection.query(<<~SQL, [name, system_prompt])
            INSERT INTO personas (name, system_prompt, is_default, created_at, updated_at)
            VALUES (?, ?, FALSE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
          SQL

          get(name)
        rescue DuckDB::Error => e
          if e.message.include?("Duplicate key") || e.message.include?("Constraint")
            raise Error, "Persona '#{name}' already exists"
          end

          raise Error, "Failed to create persona: #{e.message}"
        end
      end

      # Updates an existing persona and returns it
      def update(name:, system_prompt:)
        validate_system_prompt(system_prompt)

        persona = get(name)
        raise Error, "Persona '#{name}' not found" unless persona

        @connection.query(<<~SQL, [system_prompt, name])
          UPDATE personas
          SET system_prompt = ?, updated_at = CURRENT_TIMESTAMP
          WHERE name = ?
        SQL

        get(name)
      end

      # Deletes a persona (with validations)
      def delete(name) # rubocop:disable Naming/PredicateMethod
        persona = get(name)
        raise Error, "Persona '#{name}' not found" unless persona

        # Prevent deletion of default persona
        raise Error, "Cannot delete the default persona" if persona["is_default"]

        # Prevent deletion of active persona
        active_persona = get_active
        if active_persona && active_persona["id"] == persona["id"]
          raise Error, "Cannot delete the currently active persona. Switch to another persona first."
        end

        @connection.query(<<~SQL, [name])
          DELETE FROM personas WHERE name = ?
        SQL

        true
      end

      # Returns the currently active persona
      def get_active # rubocop:disable Naming/AccessorMethodName
        result = @connection.query(<<~SQL)
          SELECT value FROM appconfig WHERE key = 'active_persona_id'
        SQL

        rows = result.to_a
        if rows.empty?
          # No active persona set, return default
          return get_default_persona
        end

        active_id = rows.first["value"].to_i

        result = @connection.query(<<~SQL, [active_id])
          SELECT id, name, system_prompt, is_default, created_at, updated_at
          FROM personas
          WHERE id = ?
        SQL

        personas = result.to_a
        personas.empty? ? get_default_persona : personas.first
      end

      # Sets the active persona
      def set_active(name) # rubocop:disable Naming/AccessorMethodName
        persona = get(name)
        raise Error, "Persona '#{name}' not found" unless persona

        @connection.query(<<~SQL, [persona["id"].to_s])
          INSERT OR REPLACE INTO appconfig (key, value, updated_at)
          VALUES ('active_persona_id', ?, CURRENT_TIMESTAMP)
        SQL

        persona
      end

      private

      def validate_name(name)
        raise Error, "Invalid persona name: name cannot be empty" if name.nil? || name.empty?

        if name.length > MAX_NAME_LENGTH
          raise Error, "Invalid persona name: name cannot exceed #{MAX_NAME_LENGTH} characters"
        end

        return if name.match?(NAME_REGEX)

        raise Error, "Invalid persona name: must contain only lowercase letters, numbers, hyphens, and underscores"
      end

      def validate_system_prompt(system_prompt)
        return unless system_prompt.nil? || system_prompt.empty?

        raise Error, "System prompt cannot be empty"
      end

      def get_default_persona # rubocop:disable Naming/AccessorMethodName
        result = @connection.query(<<~SQL)
          SELECT id, name, system_prompt, is_default, created_at, updated_at
          FROM personas
          WHERE is_default = TRUE
        SQL

        result.to_a.first
      end
    end
  end
end
