# frozen_string_literal: true

require_relative "pipeline_context"
require_relative "stages/ambiguity_resolution_stage"
require_relative "debug"

module Nu
  module Agent
    # Manages multi-stage prompt processing
    class PromptPipeline
      attr_reader :stages, :llm, :enabled, :config

      def initialize(llm:, enabled: true, config: {}, debug: false)
        @llm = llm
        @enabled = enabled
        @config = default_config.merge(config).merge(debug: debug)
        @stages = []
        register_default_stages if @enabled
      end

      def process(original_prompt)
        return original_prompt unless @enabled

        Debug.log("Starting pipeline with #{@stages.length} stage(s)")
        Debug.log("Original prompt length: #{original_prompt.length} chars")

        context = PipelineContext.new(original_prompt: original_prompt)

        @stages.each_with_index do |stage, index|
          stage_name = stage.class.name.split('::').last
          Debug.log("Stage #{index + 1}/#{@stages.length}: #{stage_name}")

          context = stage.process(context, llm: @llm)

          Debug.log("Stage #{stage_name} complete")
          break if context.halted?
        end

        Debug.log("Pipeline complete. Final prompt length: #{context.final_prompt.length} chars")

        context.final_prompt
      end

      def add_stage(stage)
        @stages << stage
      end

      def remove_stage(stage_class)
        @stages.reject! { |s| s.is_a?(stage_class) }
      end

      def clear_stages
        @stages = []
      end

      def toggle_enabled
        @enabled = !@enabled
      end

      private

      def default_config
        {
          max_ambiguities: 3,
          debug: false,
          ask_for_clarification: true
        }
      end

      def register_default_stages
        @stages << Stages::AmbiguityResolutionStage.new(@config)
        # Future stages can be added here:
        # @stages << Stages::IntentClassificationStage.new
        # @stages << Stages::PromptEnhancementStage.new
      end
    end
  end
end