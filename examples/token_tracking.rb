#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../lib/nu/agent'

# Example of using the ClaudeClient with token tracking

client = Nu::Agent::ClaudeClient.new

# Make a request - chat() returns just the text
response = client.chat(prompt: "What is the capital of France?")

puts "Response: #{response}"
puts "\nToken Usage:"
puts "  Input tokens: #{client.input_tokens}"
puts "  Output tokens: #{client.output_tokens}"
puts "  Total tokens: #{client.total_tokens}"

# Calculate approximate cost (example rates - check current pricing)
# Claude Sonnet pricing example (as of 2024):
# Input: $3 per million tokens
# Output: $15 per million tokens
input_cost = client.input_tokens * 0.000003
output_cost = client.output_tokens * 0.000015
total_cost = input_cost + output_cost

puts "\nEstimated Cost:"
puts "  Input cost: $#{format('%.6f', input_cost)}"
puts "  Output cost: $#{format('%.6f', output_cost)}"
puts "  Total cost: $#{format('%.6f', total_cost)}"

# The client tracks cumulative usage across multiple requests
prompts = [
  "What is 2+2?",
  "Name three colors",
  "What year is it?"
]

puts "\n\nProcessing multiple requests..."
puts "-" * 40

prompts.each do |prompt|
  response = client.chat(prompt: prompt)

  puts "\nPrompt: #{prompt}"
  puts "Response: #{response[0..50]}..."
  puts "Cumulative tokens: #{client.input_tokens} in / #{client.output_tokens} out / #{client.total_tokens} total"
end

puts "\n" + "=" * 40
puts "TOTAL TOKEN USAGE (CUMULATIVE):"
puts "  Total input tokens: #{client.input_tokens}"
puts "  Total output tokens: #{client.output_tokens}"
puts "  Total tokens: #{client.total_tokens}"
puts "=" * 40