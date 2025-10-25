#!/usr/bin/env ruby
# frozen_string_literal: true

require 'curses'

# Very simple ncurses test to debug input
puts "Simple ncurses input test"
puts "Press Enter to start..."
gets

begin
  Curses.init_screen
  Curses.cbreak
  Curses.noecho
  Curses.curs_set(1)

  # Create a simple window
  win = Curses.stdscr
  win.keypad(true)

  win.clear
  win.setpos(0, 0)
  win.addstr("Type something (Ctrl-D to exit):\n")
  win.addstr("> ")
  win.refresh

  buffer = String.new  # Mutable string
  cursor_pos = 0

  loop do
    ch = win.getch

    # Show what we received (for debugging)
    win.setpos(5, 0)
    win.clrtoeol
    win.addstr("Received: #{ch.inspect} (class: #{ch.class})")

    if ch.is_a?(String)
      if ch == "\u0004" # Ctrl-D
        break
      elsif ch == "\n" || ch == "\r"
        win.setpos(3, 0)
        win.clrtoeol
        win.addstr("You entered: #{buffer}")
        buffer = String.new  # Mutable string
        cursor_pos = 0
        win.setpos(1, 0)
        win.clrtoeol
        win.addstr("> ")
      elsif ch == "\u007F" || ch == "\b"
        if cursor_pos > 0
          buffer.slice!(cursor_pos - 1)
          cursor_pos -= 1
          win.setpos(1, 0)
          win.clrtoeol
          win.addstr("> " + buffer)
          win.setpos(1, 2 + cursor_pos)
        end
      elsif ch.ord >= 32 && ch.ord <= 126
        buffer.insert(cursor_pos, ch)
        cursor_pos += 1
        win.setpos(1, 0)
        win.clrtoeol
        win.addstr("> " + buffer)
        win.setpos(1, 2 + cursor_pos)
      end
    else
      # Integer
      if ch == 4 # Ctrl-D
        break
      elsif ch == 10 || ch == 13
        win.setpos(3, 0)
        win.clrtoeol
        win.addstr("You entered: #{buffer}")
        buffer = String.new  # Mutable string
        cursor_pos = 0
        win.setpos(1, 0)
        win.clrtoeol
        win.addstr("> ")
      elsif ch == 127 || ch == 8 || ch == Curses::KEY_BACKSPACE
        if cursor_pos > 0
          buffer.slice!(cursor_pos - 1)
          cursor_pos -= 1
          win.setpos(1, 0)
          win.clrtoeol
          win.addstr("> " + buffer)
          win.setpos(1, 2 + cursor_pos)
        end
      elsif ch >= 32 && ch <= 126
        buffer.insert(cursor_pos, ch.chr)
        cursor_pos += 1
        win.setpos(1, 0)
        win.clrtoeol
        win.addstr("> " + buffer)
        win.setpos(1, 2 + cursor_pos)
      end
    end

    win.refresh
  end

  Curses.close_screen
  puts "\nDebug test completed!"
  puts "Last buffer: #{buffer}"

rescue => e
  Curses.close_screen rescue nil
  puts "\nError: #{e.class}: #{e.message}"
  puts e.backtrace.first(10)
end
