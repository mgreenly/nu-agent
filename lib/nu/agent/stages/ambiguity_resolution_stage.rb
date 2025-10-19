# frozen_string_literal: true

require "json"
require_relative "../debug"

module Nu
  module Agent
    module Stages
      # Stage that detects ambiguities in user prompts and collects clarifications
      class AmbiguityResolutionStage
        attr_reader :config

        def initialize(config = {})
          @config = {
            max_ambiguities: 3,
            debug: false,
            ask_for_clarification: true
          }.merge(config)
        end

        def process(context, llm:)
          Debug.log("Analyzing request for ambiguities...")

          # Detect ambiguities using the LLM
          ambiguities = detect_ambiguities(context.current_prompt, llm)

          if ambiguities.empty?
            Debug.log("No ambiguities detected, proceeding with request")
            return context
          end

          puts "\nFound #{ambiguities.length} ambiguous term(s) that need clarification.\n"
          Debug.log("Ambiguities detected: #{ambiguities.map { |a| a['term'] }.join(', ')}")

          # Collect clarifications from user
          clarifications = collect_clarifications(ambiguities)

          # Store clarifications in context
          clarifications.each do |term, answer|
            context.add_clarification(term, answer)
          end

          # Build enhanced prompt with clarifications
          enhanced_prompt = build_enhanced_prompt(
            context.original_prompt,
            clarifications
          )

          context.update_prompt(enhanced_prompt)
          Debug.log("Clarifications added. Processing enhanced request")

          context
        end

        private

        def detect_ambiguities(prompt, llm)
          detection_prompt = build_detection_prompt(prompt)

          Debug.log("Starting ambiguity detection call to LLM")

          # Save current conversation state
          original_history = llm.instance_variable_get(:@conversation_history)

          # Create temporary clean history for ambiguity detection
          llm.instance_variable_set(:@conversation_history, [])
          Debug.log("Temporarily cleared conversation history for ambiguity detection")

          begin
            # Get ambiguity analysis (tokens are still tracked)
            response = llm.chat(prompt: detection_prompt)
            parse_ambiguities(response)
          rescue StandardError => e
            Debug.log("Error detecting ambiguities: #{e.message}")
            [] # Return empty array on error, don't block the user
          ensure
            # Always restore original conversation history
            llm.instance_variable_set(:@conversation_history, original_history)
            Debug.log("Restored original conversation history")
          end
        end

        def build_detection_prompt(user_prompt)
          <<~PROMPT
            You are helping to identify ambiguities in a user's request to make it clearer.

            Analyze this user request and identify any ambiguous terms, vague directions, or unclear requirements:

            User Request: "#{user_prompt}"

            Identify specific ambiguous elements that would benefit from clarification.
            For each ambiguity, create ONE simple, direct question to clarify it.

            IMPORTANT:
            - Only identify genuine ambiguities that would significantly impact the response
            - Don't over-analyze - common terms and standard requests don't need clarification
            - Maximum of #{@config[:max_ambiguities]} ambiguities

            Respond ONLY with a JSON object in this exact format:
            {
              "ambiguities": [
                {
                  "term": "the specific ambiguous term or phrase from the request",
                  "question": "A simple clarifying question?"
                }
              ]
            }

            If there are no significant ambiguities, respond with:
            {"ambiguities": []}
          PROMPT
        end

        def parse_ambiguities(response)
          # Extract JSON from response
          json_match = response.match(/\{.*\}/m)
          return [] unless json_match

          begin
            result = JSON.parse(json_match[0])
            ambiguities = result["ambiguities"] || []

            # Validate and limit to configured maximum
            ambiguities.take(@config[:max_ambiguities]).select do |a|
              a.is_a?(Hash) && a["term"] && a["question"]
            end
          rescue JSON::ParserError => e
            Debug.log("Error parsing ambiguity detection response: #{e.message}")
            []
          end
        end

        def collect_clarifications(ambiguities)
          clarifications = {}

          puts "I need some clarification to better understand your request:\n\n"

          ambiguities.each_with_index do |ambiguity, index|
            puts "#{index + 1}. Regarding '#{ambiguity['term']}':"
            puts "   #{ambiguity['question']}"
            print "   > "

            answer = gets
            break if answer.nil? # Handle Ctrl+D/EOF

            answer = answer.strip

            # Store the clarification if an answer was provided
            unless answer.empty?
              clarifications[ambiguity['term']] = answer
              Debug.log("User clarified '#{ambiguity['term']}': #{answer}")
            end

            puts # Add blank line between questions
          end

          clarifications
        end

        def build_enhanced_prompt(original_prompt, clarifications)
          return original_prompt if clarifications.empty?

          clarification_text = clarifications.map do |term, answer|
            "- #{term}: #{answer}"
          end.join("\n")

          enhanced = <<~PROMPT
            #{original_prompt}

            Context and clarifications:
            #{clarification_text}
          PROMPT

          Debug.log_multiline("Enhanced prompt:", enhanced)

          enhanced
        end
      end
    end
  end
end