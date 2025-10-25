#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/nu/agent/tui_manager'

# Simple TUI test
puts "Testing TUI Manager..."
puts "This will initialize a split-pane interface."
puts "Type some text and press Enter to see it in the output pane."
puts "Type 'exit' or press Ctrl-D to quit."
puts ""
print "Press Enter to start TUI test..."
gets

begin
  tui = Nu::Agent::TUIManager.new

  # Write some test output
  tui.write_output("Welcome to TUI test!")
  tui.write_output("Output pane is working (top 80%).")
  tui.write_debug("This is a debug message (dimmed)")
  tui.write_error("This is an error message (red)")
  tui.write_output("")
  tui.write_output("Instructions:")
  tui.write_output("  - Type in the input pane below (bottom 20%)")
  tui.write_output("  - Press Enter to submit")
  tui.write_output("  - Type 'exit' or press Ctrl-D to quit")
  tui.write_output("")
  tui.write_output("Try typing now...")

  # Test input loop
  loop do
    line = tui.readline("> ")
    break if line.nil?

    tui.write_output("Echo: #{line}")

    if line.downcase == "exit"
      tui.write_output("Goodbye!")
      break
    elsif line.downcase == "test"
      tui.write_output("Testing multiple lines:")
      5.times do |i|
        tui.write_output("  Line #{i + 1}")
        sleep(0.1)
      end
    end
  end

  tui.close
  puts "\nTUI test completed successfully!"

rescue => e
  # Make sure we close curses before showing error
  begin
    require 'curses'
    Curses.close_screen rescue nil
  rescue
  end

  puts "\nError: #{e.class}: #{e.message}"
  puts e.backtrace.first(10)
end
