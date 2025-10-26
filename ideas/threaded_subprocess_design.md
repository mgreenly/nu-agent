# Threaded Subprocess Communication Pattern

## Overview

This document describes a design pattern for managing long-running subprocesses in Ruby with bidirectional, multi-cycle communication. The pattern allows a parent thread to write to a subprocess's stdin and read from its stdout/stderr across many interaction cycles, without blocking or deadlocking.

## The Problem

When working with subprocesses in Ruby, several challenges arise:

### 1. Pipe Buffer Limitations
- Linux pipe buffers are typically **64 KB** (65,536 bytes)
- When a pipe fills, the **writing process blocks** until the reader consumes data
- If the parent doesn't read continuously, the child can deadlock

### 2. Thread-Level vs Process-Level I/O
- Threads in a process **share file descriptors** (stdin/stdout/stderr)
- You cannot give different threads different stdin/stdout/stderr streams
- All threads see the same fd 0, 1, 2

### 3. Multi-Cycle Communication Requirements
- Long-running processes need **dozens or hundreds** of write/read cycles
- Parent thread needs to decide **when** to write and **when** to read
- Subprocess output must be **buffered** and available on-demand
- Parent thread should **never block** waiting for subprocess I/O

## The Solution

Use `Open3.popen3` with dedicated collector threads that continuously drain the subprocess's stdout and stderr into thread-safe buffers. The parent thread interacts with these buffers, not the pipes directly.

### Architecture

```
Parent Thread                 Collector Threads              Subprocess
     |                               |                            |
     |-- write(data) ------------> stdin ----------------------> |
     |                               |                            |
     |                           [stdout] <--------------------- |
     |                               |                            |
     |                          read_nonblock                     |
     |                               |                            |
     |                         StringIO buffer                    |
     |                          (thread-safe)                     |
     |                               |                            |
     |-- read_stdout(clear: true) --|                            |
     |<- return buffered data -------|                            |
     |                               |                            |
     |                           [stderr] <--------------------- |
     |                               |                            |
     |                          read_nonblock                     |
     |                               |                            |
     |                         StringIO buffer                    |
     |                          (thread-safe)                     |
     |                               |                            |
     |-- read_stderr(clear: true) --|                            |
     |<- return buffered data -------|                            |
```

### Key Components

1. **Open3.popen3**: Creates subprocess with separate pipes for stdin, stdout, stderr
2. **Collector Threads**: Background threads continuously read from stdout/stderr
3. **StringIO Buffers**: In-memory buffers to accumulate output
4. **Mutex**: Ensures thread-safe access to buffers
5. **IO.select**: Non-blocking I/O to detect when data is available
6. **read_nonblock**: Non-blocking reads prevent collector threads from hanging

## Implementation

```ruby
require 'open3'
require 'stringio'
require 'thread'

class ThreadedSubprocess
  attr_reader :pid

  def initialize(cmd)
    @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(cmd)
    @pid = @wait_thr.pid

    # Thread-safe buffers
    @stdout_buffer = StringIO.new
    @stderr_buffer = StringIO.new
    @buffer_mutex = Mutex.new

    @running = true
    start_collector_threads
  end

  # Write to subprocess stdin (call from parent thread)
  def write(data)
    @stdin.write(data)
    @stdin.flush
  end

  # Read collected stdout (call from parent thread)
  # clear: true consumes the data, false just peeks
  def read_stdout(clear: false)
    @buffer_mutex.synchronize do
      data = @stdout_buffer.string.dup
      @stdout_buffer.truncate(0) if clear
      @stdout_buffer.rewind if clear
      data
    end
  end

  # Read collected stderr (call from parent thread)
  # clear: true consumes the data, false just peeks
  def read_stderr(clear: false)
    @buffer_mutex.synchronize do
      data = @stderr_buffer.string.dup
      @stderr_buffer.truncate(0) if clear
      @stderr_buffer.rewind if clear
      data
    end
  end

  # Check if subprocess is alive
  def alive?
    @wait_thr.alive?
  end

  # Close stdin (signals EOF to subprocess)
  def close_stdin
    @stdin.close unless @stdin.closed?
  end

  # Wait for subprocess to finish and stop collectors
  def wait
    @wait_thr.join
    @running = false
    @collector_threads.each(&:join)
    @wait_thr.value
  end

  # Kill subprocess
  def kill(signal = 'TERM')
    Process.kill(signal, @pid) if alive?
    wait
  end

  private

  def start_collector_threads
    @collector_threads = []

    # Stdout collector thread
    @collector_threads << Thread.new do
      loop do
        break unless @running && !@stdout.closed?

        # Wait up to 0.1s for data to be available
        ready = IO.select([@stdout], nil, nil, 0.1)
        next unless ready

        begin
          # Non-blocking read up to 4KB at a time
          data = @stdout.read_nonblock(4096)
          @buffer_mutex.synchronize do
            @stdout_buffer.write(data)
          end
        rescue IO::WaitReadable
          # Nothing to read right now
        rescue EOFError
          # Subprocess closed stdout
          break
        end
      end
    end

    # Stderr collector thread
    @collector_threads << Thread.new do
      loop do
        break unless @running && !@stderr.closed?

        ready = IO.select([@stderr], nil, nil, 0.1)
        next unless ready

        begin
          data = @stderr.read_nonblock(4096)
          @buffer_mutex.synchronize do
            @stderr_buffer.write(data)
          end
        rescue IO::WaitReadable
          # Nothing to read right now
        rescue EOFError
          # Subprocess closed stderr
          break
        end
      end
    end
  end
end
```

## Usage Examples

### Example 1: Python REPL - Multiple Calculation Cycles

```ruby
proc = ThreadedSubprocess.new('python3 -i')

# Cycle 1: Set variable
proc.write("x = 5\n")
sleep 0.2  # Give subprocess time to process
puts "Cycle 1: #{proc.read_stdout(clear: true)}"

# Cycle 2: Calculate
proc.write("print(x * 2)\n")
sleep 0.2
puts "Cycle 2: #{proc.read_stdout(clear: true)}"

# Cycle 3: Import and use library
proc.write("import math\n")
proc.write("print(math.pi)\n")
sleep 0.2
puts "Cycle 3: #{proc.read_stdout(clear: true)}"

# Cycle 4: Trigger error
proc.write("undefined_variable\n")
sleep 0.2
puts "Error: #{proc.read_stderr(clear: true)}"

# Many more cycles...

proc.write("exit()\n")
proc.wait
```

### Example 2: Interactive Shell

```ruby
shell = ThreadedSubprocess.new('/bin/bash')

10.times do |i|
  shell.write("echo 'Command #{i}'\n")
  shell.write("ls -la | head -3\n")
  sleep 0.3

  output = shell.read_stdout(clear: true)
  puts "=== Cycle #{i} ==="
  puts output
end

shell.write("exit\n")
shell.wait
```

### Example 3: Peeking vs Consuming Data

```ruby
proc = ThreadedSubprocess.new('python3 -i')

proc.write("for i in range(5): print(i)\n")
sleep 0.5

# Peek at output without consuming
preview = proc.read_stdout(clear: false)
puts "Preview: #{preview}"

# Data still in buffer, peek again
preview2 = proc.read_stdout(clear: false)
puts "Preview again: #{preview2}"

# Now consume the data
final = proc.read_stdout(clear: true)
puts "Final: #{final}"

# Buffer is now empty
empty = proc.read_stdout(clear: false)
puts "Empty: #{empty.inspect}"  # => ""

proc.write("exit()\n")
proc.wait
```

## Why This Design Works

### 1. Prevents Deadlock
- Collector threads **continuously drain** stdout and stderr
- Subprocess never blocks waiting for parent to read
- 64 KB pipe buffer limit is not a concern

### 2. Non-Blocking Parent Thread
- Parent writes to stdin and reads from buffers **without blocking**
- `IO.select` with timeout prevents collector threads from hanging
- `read_nonblock` ensures no blocking reads

### 3. Thread-Safe
- `Mutex` protects buffer access
- Parent and collector threads can safely access buffers concurrently
- No race conditions or corruption

### 4. Flexible Reading
- `clear: false` - **Peek** at data without consuming
- `clear: true` - **Consume** data (read and clear buffer)
- Parent decides when to read and what to do with data

### 5. Multi-Cycle Support
- No limit on number of write/read cycles
- Buffers accumulate output until parent reads
- Works for long-running interactive processes

## Important Considerations

### Timing and Sleep
- After writing to stdin, you may need to **sleep** briefly
- Subprocess needs time to process input and generate output
- Collector threads need time to read from pipes
- Typical sleep: 0.1 - 0.5 seconds depending on subprocess

### Memory Usage
- Buffers grow until parent reads them
- Use `clear: true` regularly to prevent unbounded memory growth
- For very chatty subprocesses, read frequently

### Process Lifetime
- Call `wait()` to clean up when done
- Collector threads will join and exit
- Use `kill()` if subprocess doesn't exit gracefully

### Error Handling
- Always check `stderr` for error messages
- Monitor `alive?` to detect subprocess crashes
- Handle EOFError in collectors (already done in implementation)

### IO.select Timeout
- 0.1 second timeout is a good balance
- Too short: wastes CPU cycles
- Too long: increases latency in detecting new data

## Alternatives Considered

### Why Not Fork?
- **Fork** gives you separate processes with their own stdin/stdout/stderr
- More complex: manual pipe setup, exec management
- Less portable: doesn't work on Windows
- Overkill if you just need to run external commands
- **Use fork only if**: running Ruby code in child, need extreme control

### Why Not Blocking Reads?
- Parent thread would block waiting for subprocess
- Can't do other work while waiting
- Would need complex select logic in parent
- Collector threads isolate this complexity

### Why Not System/Backticks/exec?
- These run commands and wait for completion
- No multi-cycle communication
- No access to stdin during execution
- No streaming of output

## When to Use This Pattern

**Use this pattern when:**
- Running long-lived subprocesses (REPLs, shells, daemons)
- Need bidirectional communication (write and read)
- Need multiple write/read cycles (dozens or more)
- Parent thread must remain responsive
- Subprocess generates significant output (>64 KB possible)

**Don't use this pattern when:**
- One-shot command execution (use `system`, backticks, or `Open3.capture3`)
- Subprocess runs briefly and exits
- Only need output at the end (use `Open3.capture3`)
- Only writing to stdin OR reading from stdout (simpler solutions exist)

## Future Enhancements

Possible improvements to this design:

1. **Line buffering**: Buffer by lines instead of raw bytes
2. **Callbacks**: Trigger callback when new data arrives
3. **Timeout**: Auto-kill subprocess after timeout
4. **Combined output**: Option to merge stdout and stderr
5. **Statistics**: Track bytes read, cycles, uptime
6. **Logging**: Debug logging of all I/O operations
7. **Backpressure**: Pause/resume output collection if buffer too large

## References

- Ruby `Open3` documentation: https://ruby-doc.org/stdlib/libdoc/open3/rdoc/Open3.html
- Ruby `StringIO` documentation: https://ruby-doc.org/stdlib/libdoc/stringio/rdoc/StringIO.html
- Linux pipe buffer size: `man 7 pipe`, see "Pipe capacity"
- IO.select documentation: https://ruby-doc.org/core/IO.html#method-c-select
