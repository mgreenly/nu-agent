#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../lib/nu/agent'

# Example of using the ClaudeClient with token tracking

client = Nu::Agent::ClaudeClient.new

# Make a request and get both response and token usage
result = client.chat(prompt: "What is the capital of France?")

puts "Response: #{result[:text]}"
puts "\nToken Usage:"
puts "  Input tokens: #{result[:usage]['input_tokens']}"
puts "  Output tokens: #{result[:usage]['output_tokens']}"
puts "  Total tokens: #{result[:usage]['input_tokens'] + result[:usage]['output_tokens']}"

# Calculate approximate cost (example rates - check current pricing)
# Claude Sonnet pricing example (as of 2024):
# Input: $3 per million tokens
# Output: $15 per million tokens
input_cost = result[:usage]['input_tokens'] * 0.000003
output_cost = result[:usage]['output_tokens'] * 0.000015
total_cost = input_cost + output_cost

puts "\nEstimated Cost:"
puts "  Input cost: $#{format('%.6f', input_cost)}"
puts "  Output cost: $#{format('%.6f', output_cost)}"
puts "  Total cost: $#{format('%.6f', total_cost)}"

# Track cumulative usage across multiple requests
total_input_tokens = 0
total_output_tokens = 0

prompts = [
  "What is 2+2?",
  "Name three colors",
  "What year is it?"
]

puts "\n\nProcessing multiple requests..."
puts "-" * 40

prompts.each do |prompt|
  result = client.chat(prompt: prompt)
  input_tokens = result[:usage]['input_tokens']
  output_tokens = result[:usage]['output_tokens']

  total_input_tokens += input_tokens
  total_output_tokens += output_tokens

  puts "\nPrompt: #{prompt[0..30]}..."
  puts "Response: #{result[:text][0..50]}..."
  puts "Tokens: #{input_tokens} in / #{output_tokens} out"
end

puts "\n" + "=" * 40
puts "TOTAL TOKEN USAGE:"
puts "  Total input tokens: #{total_input_tokens}"
puts "  Total output tokens: #{total_output_tokens}"
puts "  Total tokens: #{total_input_tokens + total_output_tokens}"
puts "=" * 40