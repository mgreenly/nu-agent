# frozen_string_literal: true

require "digest"

module Nu
  module Agent
    module RAG
      # Thread-safe LRU cache for RAG retrieval results
      # Provides TTL-based expiration and bounded size with least-recently-used eviction
      class RAGCache
        # Cache entry with value and metadata
        CacheEntry = Struct.new(:value, :timestamp, :last_accessed)

        def initialize(max_size: 100, ttl_seconds: 300)
          @max_size = max_size
          @ttl_seconds = ttl_seconds
          @cache = {}
          @mutex = Mutex.new
        end

        # Get a value from the cache
        # Returns nil if key doesn't exist or has expired
        def get(key)
          @mutex.synchronize do
            entry = @cache[key]
            return nil unless entry

            # Check if expired
            if expired?(entry)
              @cache.delete(key)
              return nil
            end

            # Update last accessed time for LRU tracking
            entry.last_accessed = Time.now
            entry.value
          end
        end

        # Set a value in the cache
        # Evicts least recently used entry if cache is full
        def set(key, value)
          @mutex.synchronize do
            # Evict LRU entry if cache is full and key is new
            evict_lru if @cache.size >= @max_size && !@cache.key?(key)

            now = Time.now
            @cache[key] = CacheEntry.new(value, now, now)
          end
        end

        # Remove a specific key from the cache
        def invalidate(key)
          @mutex.synchronize do
            @cache.delete(key)
          end
        end

        # Clear all entries from the cache
        def clear
          @mutex.synchronize do
            @cache.clear
          end
        end

        # Get the number of entries in the cache
        def size
          @mutex.synchronize do
            @cache.size
          end
        end

        # Generate a cache key from query embedding and config parameters
        # Rounds embeddings to create cache-friendly grouping
        def generate_cache_key(query_embedding, config, precision: 3)
          # Round embedding values for cache-friendly hashes
          rounded = query_embedding.map { |v| v.round(precision) }
          embedding_hash = Digest::SHA256.hexdigest(rounded.join(","))[0..15]

          # Include relevant config parameters in key
          config_parts = [
            config[:current_conversation_id],
            config[:after_date],
            config[:before_date],
            config[:recency_weight]
          ].compact

          config_hash = Digest::SHA256.hexdigest(config_parts.join("|"))[0..7]

          "#{embedding_hash}_#{config_hash}"
        end

        private

        # Check if an entry has expired based on TTL
        def expired?(entry)
          (Time.now - entry.timestamp) > @ttl_seconds
        end

        # Evict the least recently used entry
        def evict_lru
          return if @cache.empty?

          # Find the entry with the oldest last_accessed time
          lru_key = @cache.min_by { |_key, entry| entry.last_accessed }&.first
          @cache.delete(lru_key) if lru_key
        end
      end
    end
  end
end
