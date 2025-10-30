# frozen_string_literal: true

require "spec_helper"

module Nu
  module Agent
    # rubocop:disable Metrics/ModuleLength
    module RAG
      RSpec.describe RAGCache do
        let(:max_size) { 3 }
        let(:ttl_seconds) { 60 }
        let(:cache) { described_class.new(max_size: max_size, ttl_seconds: ttl_seconds) }

        describe "#initialize" do
          it "creates a cache with specified max_size" do
            expect(cache).to be_a(described_class)
          end

          it "defaults to max_size of 100" do
            default_cache = described_class.new
            expect(default_cache.instance_variable_get(:@max_size)).to eq(100)
          end

          it "defaults to ttl_seconds of 300 (5 minutes)" do
            default_cache = described_class.new
            expect(default_cache.instance_variable_get(:@ttl_seconds)).to eq(300)
          end
        end

        describe "#get and #set" do
          let(:key) { "test_key_123" }
          let(:value) { { conversations: [], exchanges: [], formatted_context: "test" } }

          it "returns nil for a missing key" do
            expect(cache.get(key)).to be_nil
          end

          it "stores and retrieves a value" do
            cache.set(key, value)
            expect(cache.get(key)).to eq(value)
          end

          it "returns nil for an expired entry" do
            short_ttl_cache = described_class.new(max_size: 10, ttl_seconds: 0.1)
            short_ttl_cache.set(key, value)
            sleep(0.2)
            expect(short_ttl_cache.get(key)).to be_nil
          end

          it "updates access time on get (for LRU tracking)" do
            cache.set("key1", { data: "value1" })
            sleep(0.01)
            cache.set("key2", { data: "value2" })
            sleep(0.01)

            # Access key1 to make it more recent
            cache.get("key1")

            # Add more entries to trigger eviction
            cache.set("key3", { data: "value3" })
            cache.set("key4", { data: "value4" }) # Should evict key2, not key1

            expect(cache.get("key1")).not_to be_nil
            expect(cache.get("key2")).to be_nil
          end
        end

        describe "LRU eviction" do
          it "evicts the least recently used entry when cache is full" do
            cache.set("key1", { data: "value1" })
            cache.set("key2", { data: "value2" })
            cache.set("key3", { data: "value3" })

            # Cache is now full (max_size = 3)
            # Add another entry - should evict key1 (oldest)
            cache.set("key4", { data: "value4" })

            expect(cache.get("key1")).to be_nil
            expect(cache.get("key2")).to eq({ data: "value2" })
            expect(cache.get("key3")).to eq({ data: "value3" })
            expect(cache.get("key4")).to eq({ data: "value4" })
          end

          it "keeps track of access order correctly" do
            cache.set("key1", { data: "value1" })
            cache.set("key2", { data: "value2" })
            cache.set("key3", { data: "value3" })

            # Access key1 to make it most recent
            cache.get("key1")

            # Add new entry - should evict key2 (now oldest)
            cache.set("key4", { data: "value4" })

            expect(cache.get("key1")).to eq({ data: "value1" })
            expect(cache.get("key2")).to be_nil
          end
        end

        describe "#invalidate" do
          it "removes a specific key from the cache" do
            cache.set("key1", { data: "value1" })
            cache.set("key2", { data: "value2" })

            cache.invalidate("key1")

            expect(cache.get("key1")).to be_nil
            expect(cache.get("key2")).to eq({ data: "value2" })
          end

          it "does nothing if key doesn't exist" do
            expect { cache.invalidate("nonexistent") }.not_to raise_error
          end
        end

        describe "#clear" do
          it "removes all entries from the cache" do
            cache.set("key1", { data: "value1" })
            cache.set("key2", { data: "value2" })
            cache.set("key3", { data: "value3" })

            cache.clear

            expect(cache.get("key1")).to be_nil
            expect(cache.get("key2")).to be_nil
            expect(cache.get("key3")).to be_nil
          end
        end

        describe "#size" do
          it "returns the number of entries in the cache" do
            expect(cache.size).to eq(0)

            cache.set("key1", { data: "value1" })
            expect(cache.size).to eq(1)

            cache.set("key2", { data: "value2" })
            expect(cache.size).to eq(2)

            cache.invalidate("key1")
            expect(cache.size).to eq(1)
          end
        end

        describe "thread safety" do
          it "handles concurrent access safely" do
            large_cache = described_class.new(max_size: 100, ttl_seconds: 300)

            threads = 10.times.map do |i|
              Thread.new do
                10.times do |j|
                  key = "thread_#{i}_key_#{j}"
                  large_cache.set(key, { data: "value_#{i}_#{j}" })
                  large_cache.get(key)
                end
              end
            end

            threads.each(&:join)

            # Should have up to 100 entries (max_size)
            expect(large_cache.size).to be <= 100
          end
        end

        describe "generate_cache_key" do
          let(:embedding) { [0.1234, 0.5678, 0.9012] }
          let(:config) { { current_conversation_id: 42, after_date: "2025-01-01" } }

          it "generates a consistent cache key from embedding and config" do
            key1 = cache.generate_cache_key(embedding, config)
            key2 = cache.generate_cache_key(embedding, config)
            expect(key1).to eq(key2)
          end

          it "generates different keys for different embeddings" do
            embedding2 = [0.9999, 0.8888, 0.7777]
            key1 = cache.generate_cache_key(embedding, config)
            key2 = cache.generate_cache_key(embedding2, config)
            expect(key1).not_to eq(key2)
          end

          it "generates different keys for different configs" do
            config2 = { current_conversation_id: 99, after_date: "2025-01-01" }
            key1 = cache.generate_cache_key(embedding, config)
            key2 = cache.generate_cache_key(embedding, config2)
            expect(key1).not_to eq(key2)
          end

          it "rounds embeddings for cache-friendly grouping" do
            embedding1 = [0.12345, 0.56789, 0.90123]
            embedding2 = [0.12349, 0.56784, 0.90127] # Slightly different
            # With default rounding precision of 3, these should hash to the same key
            key1 = cache.generate_cache_key(embedding1, config)
            key2 = cache.generate_cache_key(embedding2, config)
            expect(key1).to eq(key2)
          end
        end
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
