# frozen_string_literal: true

module Nu
  module Agent
    class ConsoleIO
      # Custom exception for invalid state transitions
      class StateTransitionError < StandardError; end

      # Base class for ConsoleIO states
      # Each state encapsulates behavior and valid transitions
      class State
        attr_reader :context

        def initialize(context)
          @context = context
        end

        # State name for debugging and logging
        def name
          self.class.name.split("::").last.gsub("State", "").downcase.to_sym
        end

        # Default implementations - subclasses override as needed

        def readline(_prompt)
          raise StateTransitionError, "Cannot read input in #{name} state"
        end

        def show_spinner(_message)
          raise StateTransitionError, "Cannot show spinner in #{name} state"
        end

        def hide_spinner
          raise StateTransitionError, "Cannot hide spinner in #{name} state"
        end

        def start_progress
          raise StateTransitionError, "Cannot start progress in #{name} state"
        end

        def update_progress(_text)
          raise StateTransitionError, "Cannot update progress in #{name} state"
        end

        def end_progress
          raise StateTransitionError, "Cannot end progress in #{name} state"
        end

        def pause
          # All states can transition to paused
          context.transition_to(PausedState.new(context, self))
        end

        # Hook called when entering this state
        def on_enter
          # Override in subclasses if needed
        end

        # Hook called when leaving this state
        def on_exit
          # Override in subclasses if needed
        end
      end

      # Idle state - ready for next operation
      class IdleState < State
        def readline(prompt)
          context.transition_to(ReadingUserInputState.new(context))
          context.do_readline(prompt)
        end

        def show_spinner(message)
          context.transition_to(StreamingAssistantState.new(context))
          context.do_show_spinner(message)
        end

        def start_progress
          context.transition_to(ProgressState.new(context))
          context.do_start_progress
        end
      end

      # Reading user input state - active readline loop
      class ReadingUserInputState < State
        def readline(prompt)
          # Already reading - continue
          context.do_readline(prompt)
        end

        def show_spinner(_message)
          raise StateTransitionError, "Cannot show spinner while reading user input"
        end

        # Called when input is completed (submit or EOF)
        def on_input_completed
          context.transition_to(IdleState.new(context))
        end
      end

      # Streaming assistant state - showing spinner while assistant thinks
      class StreamingAssistantState < State
        def readline(_prompt)
          raise StateTransitionError, "Cannot read input while streaming"
        end

        def show_spinner(message)
          # Update spinner message without state transition
          context.update_spinner_message(message)
        end

        def hide_spinner
          context.do_hide_spinner
          context.transition_to(IdleState.new(context))
        end
      end

      # Progress state - showing progress bar
      class ProgressState < State
        def update_progress(text)
          context.do_update_progress(text)
        end

        def end_progress
          context.do_end_progress
          context.transition_to(IdleState.new(context))
        end
      end

      # Paused state - can be entered from any state
      class PausedState < State
        attr_reader :previous_state

        def initialize(context, previous_state)
          super(context)
          @previous_state = previous_state
        end

        def resume
          context.transition_to(@previous_state)
        end

        # Override pause to prevent double-pausing
        def pause
          # Already paused - do nothing
        end
      end
    end
  end
end
