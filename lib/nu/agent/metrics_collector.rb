# frozen_string_literal: true

module Nu
  module Agent
    # Thread-safe metrics collector for counters and timers
    # Computes p50/p90/p99 percentiles for duration metrics
    class MetricsCollector
      def initialize
        @mutex = Mutex.new
        @counters = Hash.new(0)
        @timers = Hash.new { |h, k| h[k] = [] }
      end

      # Increment a counter
      # @param name [Symbol] Counter name
      # @param amount [Integer] Amount to increment by (default: 1)
      def increment(name, amount = 1)
        @mutex.synchronize do
          @counters[name] += amount
        end
      end

      # Record a duration measurement
      # @param name [Symbol] Timer name
      # @param duration [Numeric] Duration in milliseconds
      def record_duration(name, duration)
        @mutex.synchronize do
          @timers[name] << duration
        end
      end

      # Get current value of a counter
      # @param name [Symbol] Counter name
      # @return [Integer] Current counter value
      def get_counter(name)
        @mutex.synchronize do
          @counters[name]
        end
      end

      # Get timer statistics including percentiles
      # @param name [Symbol] Timer name
      # @return [Hash] Stats with :count, :p50, :p90, :p99
      def get_timer_stats(name)
        @mutex.synchronize do
          durations = @timers[name]
          return { count: 0, p50: 0, p90: 0, p99: 0 } if durations.empty?

          sorted = durations.sort
          {
            count: durations.length,
            p50: percentile(sorted, 50),
            p90: percentile(sorted, 90),
            p99: percentile(sorted, 99)
          }
        end
      end

      # Get a snapshot of all metrics
      # @return [Hash] Hash with :counters and :timers
      def snapshot
        @mutex.synchronize do
          {
            counters: @counters.dup,
            timers: @timers.transform_values do |durations|
              next { count: 0, p50: 0, p90: 0, p99: 0 } if durations.empty?

              sorted = durations.sort
              {
                count: durations.length,
                p50: percentile(sorted, 50),
                p90: percentile(sorted, 90),
                p99: percentile(sorted, 99)
              }
            end
          }
        end
      end

      # Reset all metrics
      def reset
        @mutex.synchronize do
          @counters.clear
          @timers.clear
        end
      end

      private

      # Calculate percentile from sorted array
      # @param sorted_array [Array<Numeric>] Sorted array of values
      # @param percentile [Integer] Percentile to calculate (0-100)
      # @return [Numeric] Percentile value
      def percentile(sorted_array, percentile)
        return 0 if sorted_array.empty?
        return sorted_array.first if sorted_array.length == 1

        # Use nearest-rank method
        rank = (percentile / 100.0 * sorted_array.length).ceil - 1
        rank = rank.clamp(0, sorted_array.length - 1)
        sorted_array[rank]
      end
    end
  end
end
