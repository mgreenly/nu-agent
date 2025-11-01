# frozen_string_literal: true

require "spec_helper"
require "benchmark"

# This benchmark suite measures the performance of the LLM request builder
#
# Usage:
#   bundle exec rspec spec/benchmarks/llm_request_builder_benchmark.rb --format documentation
#
# Note: This is not part of the regular test suite. Run it separately to collect performance data.
RSpec.describe "LLM Request Builder Performance Benchmarks", :benchmark do
  let(:builder) { Nu::Agent::LlmRequestBuilder.new }

  let(:system_prompt) { "You are a helpful assistant." }
  let(:simple_messages) do
    [
      { "actor" => "user", "role" => "user", "content" => "Hello" },
      { "actor" => "orchestrator", "role" => "assistant", "content" => "Hi there!" }
    ]
  end

  let(:complex_messages) do
    20.times.map do |i|
      [
        { "actor" => "user", "role" => "user", "content" => "Question #{i}?" },
        { "actor" => "orchestrator", "role" => "assistant", "content" => "Answer #{i}." }
      ]
    end.flatten
  end

  let(:simple_tools) do
    [
      {
        "name" => "test_tool",
        "description" => "A test tool",
        "input_schema" => {
          "type" => "object",
          "properties" => {
            "arg" => { "type" => "string" }
          }
        }
      }
    ]
  end

  let(:complex_tools) do
    10.times.map do |i|
      {
        "name" => "tool_#{i}",
        "description" => "Tool number #{i}",
        "input_schema" => {
          "type" => "object",
          "properties" => {
            "arg#{i}" => { "type" => "string" },
            "count" => { "type" => "integer" }
          },
          "required" => ["arg#{i}"]
        }
      }
    end
  end

  let(:rag_content) do
    {
      redactions: %w[secret1 secret2],
      spell_check: { "wrng" => "wrong", "teh" => "the" }
    }
  end

  let(:metadata) do
    {
      conversation_id: 1,
      exchange_id: 1
    }
  end

  describe "simple request building" do
    it "has minimal overhead for simple requests" do
      # Warm up
      10.times do
        Nu::Agent::LlmRequestBuilder.new
                                    .with_system_prompt(system_prompt)
                                    .with_user_query("Hello")
                                    .build
      end

      # Measure execution time for simple requests
      execution_time = Benchmark.realtime do
        1000.times do
          Nu::Agent::LlmRequestBuilder.new
                                      .with_system_prompt(system_prompt)
                                      .with_user_query("Hello")
                                      .build
        end
      end
      avg_time = execution_time / 1000.0

      puts "\n  📊 Simple Request Building:"
      puts "     Avg execution time: #{(avg_time * 1000).round(3)}ms"
      puts "     Ops/second:         #{(1.0 / avg_time).round(0)}"

      # Should be very fast (< 1ms on most systems)
      expect(avg_time).to be < 0.001
    end
  end

  describe "request with history" do
    it "handles message history efficiently" do
      # Warm up
      10.times do
        Nu::Agent::LlmRequestBuilder.new
                                    .with_system_prompt(system_prompt)
                                    .with_history(simple_messages)
                                    .with_user_query("New question")
                                    .build
      end

      # Measure with simple history (4 messages)
      simple_time = Benchmark.realtime do
        1000.times do
          Nu::Agent::LlmRequestBuilder.new
                                      .with_system_prompt(system_prompt)
                                      .with_history(simple_messages)
                                      .with_user_query("New question")
                                      .build
        end
      end
      simple_avg = simple_time / 1000.0

      # Measure with complex history (40 messages)
      complex_time = Benchmark.realtime do
        1000.times do
          Nu::Agent::LlmRequestBuilder.new
                                      .with_system_prompt(system_prompt)
                                      .with_history(complex_messages)
                                      .with_user_query("New question")
                                      .build
        end
      end
      complex_avg = complex_time / 1000.0

      puts "\n  📊 Request with Message History:"
      puts "     Simple (4 msgs):    #{(simple_avg * 1000).round(3)}ms"
      puts "     Complex (40 msgs):  #{(complex_avg * 1000).round(3)}ms"
      puts "     Ratio:              #{(complex_avg / simple_avg).round(2)}x"

      # Complex should not be dramatically slower (less than 10x)
      expect(complex_avg / simple_avg).to be < 10.0
    end
  end

  describe "request with tools" do
    it "handles tool definitions efficiently" do
      # Warm up
      10.times do
        Nu::Agent::LlmRequestBuilder.new
                                    .with_system_prompt(system_prompt)
                                    .with_user_query("Use tools")
                                    .with_tools(simple_tools)
                                    .build
      end

      # Measure with simple tools (1 tool)
      simple_time = Benchmark.realtime do
        1000.times do
          Nu::Agent::LlmRequestBuilder.new
                                      .with_system_prompt(system_prompt)
                                      .with_user_query("Use tools")
                                      .with_tools(simple_tools)
                                      .build
        end
      end
      simple_avg = simple_time / 1000.0

      # Measure with complex tools (10 tools)
      complex_time = Benchmark.realtime do
        1000.times do
          Nu::Agent::LlmRequestBuilder.new
                                      .with_system_prompt(system_prompt)
                                      .with_user_query("Use tools")
                                      .with_tools(complex_tools)
                                      .build
        end
      end
      complex_avg = complex_time / 1000.0

      puts "\n  📊 Request with Tools:"
      puts "     Simple (1 tool):    #{(simple_avg * 1000).round(3)}ms"
      puts "     Complex (10 tools): #{(complex_avg * 1000).round(3)}ms"
      puts "     Ratio:              #{(complex_avg / simple_avg).round(2)}x"

      # Complex should scale reasonably (less than 10x)
      expect(complex_avg / simple_avg).to be < 10.0
    end
  end

  describe "full request with all components" do
    it "builds complete requests efficiently" do
      # Warm up
      10.times do
        Nu::Agent::LlmRequestBuilder.new
                                    .with_system_prompt(system_prompt)
                                    .with_history(complex_messages)
                                    .with_user_query("Complex question")
                                    .with_tools(complex_tools)
                                    .with_rag_content(rag_content)
                                    .with_metadata(metadata)
                                    .build
      end

      # Measure full request building
      execution_time = Benchmark.realtime do
        1000.times do
          Nu::Agent::LlmRequestBuilder.new
                                      .with_system_prompt(system_prompt)
                                      .with_history(complex_messages)
                                      .with_user_query("Complex question")
                                      .with_tools(complex_tools)
                                      .with_rag_content(rag_content)
                                      .with_metadata(metadata)
                                      .build
        end
      end
      avg_time = execution_time / 1000.0

      puts "\n  📊 Full Request (all components):"
      puts "     Avg execution time: #{(avg_time * 1000).round(3)}ms"
      puts "     Ops/second:         #{(1.0 / avg_time).round(0)}"

      # Full request should still be fast (< 5ms)
      expect(avg_time).to be < 0.005
    end
  end

  describe "builder overhead vs direct hash construction" do
    it "has acceptable overhead compared to direct hash construction" do
      # Warm up both approaches
      10.times do
        # Builder approach
        Nu::Agent::LlmRequestBuilder.new
                                    .with_system_prompt(system_prompt)
                                    .with_history(simple_messages)
                                    .with_user_query("Question")
                                    .with_tools(simple_tools)
                                    .build

        # Direct hash approach
        {
          system_prompt: system_prompt,
          messages: simple_messages + [{ "actor" => "user", "role" => "user", "content" => "Question" }],
          tools: simple_tools,
          metadata: {}
        }
      end

      # Measure builder approach
      builder_time = Benchmark.realtime do
        1000.times do
          Nu::Agent::LlmRequestBuilder.new
                                      .with_system_prompt(system_prompt)
                                      .with_history(simple_messages)
                                      .with_user_query("Question")
                                      .with_tools(simple_tools)
                                      .build
        end
      end
      builder_avg = builder_time / 1000.0

      # Measure direct hash construction
      direct_time = Benchmark.realtime do
        1000.times do
          {
            system_prompt: system_prompt,
            messages: simple_messages + [{ "actor" => "user", "role" => "user", "content" => "Question" }],
            tools: simple_tools,
            metadata: {}
          }
        end
      end
      direct_avg = direct_time / 1000.0

      overhead_ratio = builder_avg / direct_avg

      puts "\n  📊 Builder Overhead vs Direct Hash:"
      puts "     Direct hash:        #{(direct_avg * 1000).round(3)}ms"
      puts "     Builder pattern:    #{(builder_avg * 1000).round(3)}ms"
      puts "     Overhead ratio:     #{overhead_ratio.round(2)}x"

      # Builder overhead should be reasonable (less than 5x)
      expect(overhead_ratio).to be < 5.0
    end
  end

  describe "memory efficiency" do
    it "does not create excessive intermediate objects" do
      # Measure memory allocation during builder usage
      before_gc = GC.stat(:total_allocated_objects)

      1000.times do
        Nu::Agent::LlmRequestBuilder.new
                                    .with_system_prompt(system_prompt)
                                    .with_history(simple_messages)
                                    .with_user_query("Question")
                                    .with_tools(simple_tools)
                                    .with_rag_content(rag_content)
                                    .with_metadata(metadata)
                                    .build
      end

      after_gc = GC.stat(:total_allocated_objects)
      objects_per_build = (after_gc - before_gc) / 1000.0

      puts "\n  📊 Memory Efficiency:"
      puts "     Objects per build:  #{objects_per_build.round(0)}"

      # Should not allocate excessive objects (< 100 per build is reasonable)
      expect(objects_per_build).to be < 100
    end
  end

  describe "comparison summary" do
    # rubocop:disable RSpec/ExampleLength
    it "displays overall performance characteristics" do
      scenarios = [
        {
          name: "Simple request",
          builder: lambda do |b|
            b.with_system_prompt(system_prompt)
             .with_user_query("Hello")
             .build
          end
        },
        {
          name: "With history (4 msgs)",
          builder: lambda do |b|
            b.with_system_prompt(system_prompt)
             .with_history(simple_messages)
             .with_user_query("Question")
             .build
          end
        },
        {
          name: "With tools (1 tool)",
          builder: lambda do |b|
            b.with_system_prompt(system_prompt)
             .with_user_query("Use tools")
             .with_tools(simple_tools)
             .build
          end
        },
        {
          name: "Full request (all)",
          builder: lambda do |b|
            b.with_system_prompt(system_prompt)
             .with_history(complex_messages)
             .with_user_query("Complex")
             .with_tools(complex_tools)
             .with_rag_content(rag_content)
             .with_metadata(metadata)
             .build
          end
        }
      ]

      puts "\n  📈 Performance Summary:"
      puts "  #{'=' * 60}"

      scenarios.each do |scenario|
        time = Benchmark.realtime do
          1000.times do
            builder_instance = Nu::Agent::LlmRequestBuilder.new
            scenario[:builder].call(builder_instance)
          end
        end
        avg_time = time / 1000.0

        puts "  #{scenario[:name].ljust(30)} #{(avg_time * 1000).round(3)}ms"
      end

      puts "  #{'=' * 60}"
    end
    # rubocop:enable RSpec/ExampleLength
  end
end
