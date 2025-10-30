# frozen_string_literal: true

require_relative "metrics_collector"

module Nu
  module Agent
    class BackgroundWorkerManager
      attr_reader :summarizer_status, :exchange_summarizer_status, :embedding_status, :active_threads

      WORKER_NAMES = {
        "conversation-summarizer" => :conversation_summarizer,
        "exchange-summarizer" => :exchange_summarizer,
        "embeddings" => :embeddings
      }.freeze

      def initialize(options)
        @application = options[:application]
        @history = options[:history]
        @summarizer = options[:summarizer]
        @conversation_id = options[:conversation_id]
        @status_mutex = options[:status_mutex]
        @embedding_client = options[:embedding_client]
        @operation_mutex = Mutex.new
        @active_threads = []
        @workers = []
        @worker_threads = {} # Map worker name to thread
        @worker_instances = {} # Map worker name to worker instance

        @summarizer_status = build_summarizer_status
        @exchange_summarizer_status = build_exchange_summarizer_status
        @embedding_status = build_embedding_status

        # Initialize metrics collectors for each worker
        @conversation_summarizer_metrics = MetricsCollector.new
        @exchange_summarizer_metrics = MetricsCollector.new
        @embedding_metrics = MetricsCollector.new
      end

      def start_summarization_worker
        @operation_mutex.synchronize do
          # Start conversation summarizer
          config_store = @history.instance_variable_get(:@config_store)
          conversation_summarizer = Workers::ConversationSummarizer.new(
            history: @history,
            summarizer: @summarizer,
            application: @application,
            status_info: { status: @summarizer_status, mutex: @status_mutex },
            current_conversation_id: @conversation_id,
            config_store: config_store
          )
          @workers << conversation_summarizer

          thread = conversation_summarizer.start_worker
          @active_threads << thread

          # Start exchange summarizer
          exchange_summarizer = Workers::ExchangeSummarizer.new(
            history: @history,
            summarizer: @summarizer,
            application: @application,
            status_info: { status: @exchange_summarizer_status, mutex: @status_mutex },
            current_conversation_id: @conversation_id,
            config_store: config_store
          )
          @workers << exchange_summarizer

          thread = exchange_summarizer.start_worker
          @active_threads << thread
        end
      end

      def start_embedding_worker
        return unless @embedding_client

        @operation_mutex.synchronize do
          embedding_worker = Workers::EmbeddingGenerator.new(
            history: @history,
            embedding_client: @embedding_client,
            application: @application,
            status_info: { status: @embedding_status, mutex: @status_mutex },
            current_conversation_id: @conversation_id,
            config_store: @history.instance_variable_get(:@config_store)
          )
          @workers << embedding_worker

          thread = embedding_worker.start_worker
          @active_threads << thread
        end
      end

      # Start a specific worker by name
      # @param name [String] Worker name (e.g., "conversation-summarizer")
      # @return [Boolean] true if started, false if invalid or already running
      def start_worker(name)
        return false unless WORKER_NAMES.key?(name)
        return false if @worker_threads[name]&.alive?

        @operation_mutex.synchronize do
          worker, thread = create_worker(name)
          return false unless worker && thread

          @worker_threads[name] = thread
          @worker_instances[name] = worker
          @workers << worker
          @active_threads << thread
          true
        end
      end

      # Stop a specific worker by name
      # @param name [String] Worker name
      # @return [Boolean] true if stopped, false if invalid or not running
      def stop_worker(name)
        return false unless WORKER_NAMES.key?(name)

        @operation_mutex.synchronize do
          thread = @worker_threads[name]
          return false unless thread&.alive?

          Thread.kill(thread)
          @worker_threads.delete(name)
          @worker_instances.delete(name)
          true
        end
      end

      # Get status for a specific worker
      # @param name [String] Worker name
      # @return [Hash, nil] Status hash or nil if invalid
      def worker_status(name)
        case name
        when "conversation-summarizer"
          @summarizer_status
        when "exchange-summarizer"
          @exchange_summarizer_status
        when "embeddings"
          @embedding_status
        end
      end

      # Get status for all workers
      # @return [Hash] Hash mapping worker names to status hashes
      def all_workers_status
        {
          "conversation-summarizer" => @summarizer_status,
          "exchange-summarizer" => @exchange_summarizer_status,
          "embeddings" => @embedding_status
        }
      end

      # Get metrics collector for a specific worker
      # @param name [String] Worker name
      # @return [MetricsCollector, nil] Metrics collector or nil if invalid
      def worker_metrics(name)
        case name
        when "conversation-summarizer"
          @conversation_summarizer_metrics
        when "exchange-summarizer"
          @exchange_summarizer_metrics
        when "embeddings"
          @embedding_metrics
        end
      end

      # Check if a worker is enabled in config
      # @param name [String] Worker name
      # @return [Boolean] true if enabled
      def worker_enabled?(name)
        return false unless WORKER_NAMES.key?(name)

        config_store = @history.instance_variable_get(:@config_store)
        config_key = "#{WORKER_NAMES[name]}_enabled"

        value = config_store.get_config(config_key)

        # Default values if not set
        if value.nil?
          return name != "embeddings" # conversation and exchange default to true, embeddings to false
        end

        value.to_s.downcase == "true"
      end

      # Enable a worker (set config and start if not running)
      # @param name [String] Worker name
      # @return [Boolean] true if successful
      def enable_worker(name) # rubocop:disable Naming/PredicateMethod
        return false unless WORKER_NAMES.key?(name)

        config_store = @history.instance_variable_get(:@config_store)
        config_key = "#{WORKER_NAMES[name]}_enabled"
        config_store.set_config(config_key, "true")

        # Start if not already running
        start_worker(name) unless @worker_threads[name]&.alive?
        true
      end

      # Disable a worker (set config and stop if running)
      # @param name [String] Worker name
      # @return [Boolean] true if successful
      def disable_worker(name) # rubocop:disable Naming/PredicateMethod
        return false unless WORKER_NAMES.key?(name)

        config_store = @history.instance_variable_get(:@config_store)
        config_key = "#{WORKER_NAMES[name]}_enabled"
        config_store.set_config(config_key, "false")

        # Stop if running
        stop_worker(name) if @worker_threads[name]&.alive?
        true
      end

      # Pause all background workers
      def pause_all
        @operation_mutex.synchronize do
          @workers.each(&:pause)
        end
      end

      # Resume all background workers
      def resume_all
        @operation_mutex.synchronize do
          @workers.each(&:resume)
        end
      end

      # Wait for all workers to pause (with timeout)
      # @param timeout [Numeric] Maximum seconds to wait for all workers to pause
      # @return [Boolean] true if all workers paused within timeout
      def wait_until_all_paused(timeout: 5)
        @workers.all? { |worker| worker.wait_until_paused(timeout: timeout) }
      end

      private

      # Create a worker instance by name
      # @param name [String] Worker name
      # @return [Array<Object, Thread>, Array<nil, nil>] Worker instance and thread, or [nil, nil] if failed
      def create_worker(name)
        case name
        when "conversation-summarizer"
          create_conversation_summarizer
        when "exchange-summarizer"
          create_exchange_summarizer
        when "embeddings"
          create_embedding_generator
        else
          [nil, nil]
        end
      end

      def create_conversation_summarizer
        config_store = @history.instance_variable_get(:@config_store)
        worker = Workers::ConversationSummarizer.new(
          history: @history,
          summarizer: @summarizer,
          application: @application,
          status_info: { status: @summarizer_status, mutex: @status_mutex },
          current_conversation_id: @conversation_id,
          config_store: config_store,
          metrics_collector: @conversation_summarizer_metrics
        )
        [worker, worker.start_worker]
      end

      def create_exchange_summarizer
        config_store = @history.instance_variable_get(:@config_store)
        worker = Workers::ExchangeSummarizer.new(
          history: @history,
          summarizer: @summarizer,
          application: @application,
          status_info: { status: @exchange_summarizer_status, mutex: @status_mutex },
          current_conversation_id: @conversation_id,
          config_store: config_store,
          metrics_collector: @exchange_summarizer_metrics
        )
        [worker, worker.start_worker]
      end

      def create_embedding_generator
        return [nil, nil] unless @embedding_client

        config_store = @history.instance_variable_get(:@config_store)
        worker = Workers::EmbeddingGenerator.new(
          history: @history,
          embedding_client: @embedding_client,
          application: @application,
          status_info: { status: @embedding_status, mutex: @status_mutex },
          current_conversation_id: @conversation_id,
          config_store: config_store,
          metrics_collector: @embedding_metrics
        )
        [worker, worker.start_worker]
      end

      def build_summarizer_status
        {
          "running" => false,
          "total" => 0,
          "completed" => 0,
          "failed" => 0,
          "current_conversation_id" => nil,
          "last_summary" => nil,
          "spend" => 0.0
        }
      end

      def build_exchange_summarizer_status
        {
          "running" => false,
          "total" => 0,
          "completed" => 0,
          "failed" => 0,
          "current_exchange_id" => nil,
          "last_summary" => nil,
          "spend" => 0.0
        }
      end

      def build_embedding_status
        {
          "running" => false,
          "total" => 0,
          "completed" => 0,
          "failed" => 0,
          "current_item" => nil,
          "spend" => 0.0
        }
      end
    end
  end
end
