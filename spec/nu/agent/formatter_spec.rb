# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe Nu::Agent::Formatter do
  let(:history) { instance_double(Nu::Agent::History) }
  let(:output) { StringIO.new }
  let(:formatter) { described_class.new(history: history, output: output) }
  let(:conversation_id) { 1 }

  describe '#display_new_messages' do
    context 'when there are new messages' do
      let(:messages) do
        [
          {
            'id' => 1,
            'actor' => 'user',
            'role' => 'user',
            'content' => 'Hello',
            'tokens_input' => nil,
            'tokens_output' => nil
          },
          {
            'id' => 2,
            'actor' => 'orchestrator',
            'role' => 'assistant',
            'content' => 'Hi there!',
            'tokens_input' => 10,
            'tokens_output' => 5
          }
        ]
      end

      before do
        allow(history).to receive(:messages_since).and_return(messages)
      end

      it 'displays assistant messages' do
        formatter.display_new_messages(conversation_id: conversation_id)

        expect(output.string).to include('Hi there!')
      end

      it 'displays token counts for assistant messages' do
        formatter.display_new_messages(conversation_id: conversation_id)

        expect(output.string).to include('Tokens: 10 in / 5 out / 15 total')
      end

      it 'updates last_message_id' do
        formatter.display_new_messages(conversation_id: conversation_id)

        # Call again - should use updated last_message_id
        expect(history).to receive(:messages_since).with(
          conversation_id: conversation_id,
          message_id: 2
        ).and_return([])

        formatter.display_new_messages(conversation_id: conversation_id)
      end
    end

    context 'when there are no new messages' do
      before do
        allow(history).to receive(:messages_since).and_return([])
      end

      it 'does not output anything' do
        formatter.display_new_messages(conversation_id: conversation_id)

        expect(output.string).to be_empty
      end
    end
  end

  describe '#wait_for_completion' do
    it 'polls until workers are idle' do
      call_count = 0
      allow(history).to receive(:messages_since).and_return([])
      allow(history).to receive(:workers_idle?) do
        call_count += 1
        call_count >= 3  # Become idle after 3 calls
      end

      formatter.wait_for_completion(conversation_id: conversation_id, poll_interval: 0.01)

      expect(call_count).to eq(3)
    end

    it 'displays messages during polling' do
      messages = [
        {
          'id' => 1,
          'actor' => 'orchestrator',
          'role' => 'assistant',
          'content' => 'Processing...',
          'tokens_input' => 5,
          'tokens_output' => 3
        }
      ]

      call_count = 0
      allow(history).to receive(:messages_since) do
        call_count += 1
        call_count == 1 ? messages : []
      end

      allow(history).to receive(:workers_idle?).and_return(false, true)

      formatter.wait_for_completion(conversation_id: conversation_id, poll_interval: 0.01)

      expect(output.string).to include('Processing...')
    end
  end

  describe '#display_message' do
    it 'displays user messages (as no-op)' do
      message = { 'id' => 1, 'actor' => 'user', 'role' => 'user', 'content' => 'Hello' }

      formatter.display_message(message)

      # User messages are not re-displayed
      expect(output.string).to be_empty
    end

    it 'displays assistant messages with content and tokens' do
      message = {
        'id' => 2,
        'actor' => 'orchestrator',
        'role' => 'assistant',
        'content' => 'Hello back!',
        'tokens_input' => 8,
        'tokens_output' => 4
      }

      formatter.display_message(message)

      expect(output.string).to include('Hello back!')
      expect(output.string).to include('Tokens: 8 in / 4 out / 12 total')
    end

    it 'displays system messages with prefix' do
      message = { 'id' => 3, 'actor' => 'system', 'role' => 'system', 'content' => 'Starting up' }

      formatter.display_message(message)

      expect(output.string).to include('[System] Starting up')
    end
  end

  describe '#display_token_summary' do
    let(:messages) do
      [
        { 'id' => 1, 'role' => 'user', 'content' => 'Hi', 'tokens_input' => nil, 'tokens_output' => nil },
        { 'id' => 2, 'role' => 'assistant', 'content' => 'Hello', 'tokens_input' => 10, 'tokens_output' => 5 },
        { 'id' => 3, 'role' => 'user', 'content' => 'How are you?', 'tokens_input' => nil, 'tokens_output' => nil },
        { 'id' => 4, 'role' => 'assistant', 'content' => 'Good!', 'tokens_input' => 15, 'tokens_output' => 3 }
      ]
    end

    before do
      allow(history).to receive(:messages).and_return(messages)
    end

    it 'displays total token counts across all messages' do
      formatter.display_token_summary(conversation_id: conversation_id)

      expect(output.string).to include('Tokens: 25 in / 8 out / 33 total')
    end

    it 'handles messages with nil token counts' do
      expect { formatter.display_token_summary(conversation_id: conversation_id) }.not_to raise_error
    end
  end
end
