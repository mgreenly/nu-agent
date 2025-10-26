#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to convert OutputBuffer patterns in formatter.rb to ConsoleIO

content = File.read("lib/nu/agent/formatter.rb")

# Pattern 1: Simple buffer.add(text) pattern
content.gsub!(/buffer = OutputBuffer\.new\s+buffer\.add\((.*?)\)\s+@output_manager&\.flush_buffer\(buffer\)/m) do
  text = Regexp.last_match(1)
  "@console.puts(#{text})"
end

# Pattern 2: buffer.debug(text) pattern
content.gsub!(/buffer = OutputBuffer\.new\s+buffer\.debug\((.*?)\)\s+@output_manager&\.flush_buffer\(buffer\)/m) do
  text = Regexp.last_match(1)
  "@console.puts(\"\\e[90m\#{#{text}}\\e[0m\") if @debug"
end

# Pattern 3: buffer.error(text) pattern
content.gsub!(/buffer = OutputBuffer\.new\s+buffer\.error\((.*?)\)\s+@output_manager&\.flush_buffer\(buffer\)/m) do
  text = Regexp.last_match(1)
  "@console.puts(\"\\e[31m\#{#{text}}\\e[0m\")"
end

# Write back
File.write("lib/nu/agent/formatter.rb", content)
puts "Conversion complete"
