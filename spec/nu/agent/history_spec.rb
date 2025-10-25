# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe Nu::Agent::History do
  let(:test_db_path) { 'db/test_history.db' }
  let(:history) { described_class.new(db_path: test_db_path) }

  before do
    # Clean up test database before each test
    FileUtils.rm_rf('db/test_history.db')
  end

  after do
    history.close
    FileUtils.rm_rf('db/test_history.db')
  end

  describe '#create_conversation' do
    it 'creates a new conversation and returns its id' do
      conversation_id = history.create_conversation
      expect(conversation_id).to be_a(Integer)
      expect(conversation_id).to be > 0
    end

    it 'creates multiple conversations with unique ids' do
      id1 = history.create_conversation
      id2 = history.create_conversation
      expect(id1).not_to eq(id2)
    end
  end

  describe '#add_message' do
    let(:conversation_id) { history.create_conversation }

    it 'adds a user message to the conversation' do
      history.add_message(
        conversation_id: conversation_id,
        actor: 'user',
        role: 'user',
        content: 'Hello, world!'
      )

      messages = history.messages(conversation_id: conversation_id)
      expect(messages.length).to eq(1)
      expect(messages.first['actor']).to eq('user')
      expect(messages.first['role']).to eq('user')
      expect(messages.first['content']).to eq('Hello, world!')
    end

    it 'adds an assistant message with model and tokens' do
      history.add_message(
        conversation_id: conversation_id,
        actor: 'orchestrator',
        role: 'assistant',
        content: 'Hello back!',
        model: 'claude-sonnet-4-20250514',
        tokens_input: 10,
        tokens_output: 5
      )

      messages = history.messages(conversation_id: conversation_id)
      expect(messages.first['model']).to eq('claude-sonnet-4-20250514')
      expect(messages.first['tokens_input']).to eq(10)
      expect(messages.first['tokens_output']).to eq(5)
    end

    it 'handles SQL special characters in content' do
      history.add_message(
        conversation_id: conversation_id,
        actor: 'user',
        role: 'user',
        content: "It's a test with 'quotes'"
      )

      messages = history.messages(conversation_id: conversation_id)
      expect(messages.first['content']).to eq("It's a test with 'quotes'")
    end
  end

  describe '#messages' do
    let(:conversation_id) { history.create_conversation }

    before do
      history.add_message(
        conversation_id: conversation_id,
        actor: 'user',
        role: 'user',
        content: 'Message 1'
      )
      history.add_message(
        conversation_id: conversation_id,
        actor: 'orchestrator',
        role: 'assistant',
        content: 'Message 2',
        include_in_context: false
      )
      history.add_message(
        conversation_id: conversation_id,
        actor: 'orchestrator',
        role: 'assistant',
        content: 'Message 3'
      )
    end

    it 'returns all messages in order by default (include_in_context only)' do
      messages = history.messages(conversation_id: conversation_id)
      expect(messages.length).to eq(2)
      expect(messages[0]['content']).to eq('Message 1')
      expect(messages[1]['content']).to eq('Message 3')
    end

    it 'returns all messages including metadata when requested' do
      messages = history.messages(conversation_id: conversation_id, include_in_context_only: false)
      expect(messages.length).to eq(3)
      expect(messages[1]['content']).to eq('Message 2')
    end

    it 'returns empty array for non-existent conversation' do
      messages = history.messages(conversation_id: 999)
      expect(messages).to eq([])
    end

    it 'filters messages by since parameter' do
      history.add_message(conversation_id: conversation_id, actor: 'user', role: 'user', content: 'Old message')

      sleep 0.01
      cutoff_time = Time.now
      sleep 0.01

      history.add_message(conversation_id: conversation_id, actor: 'user', role: 'user', content: 'New message 1')
      history.add_message(conversation_id: conversation_id, actor: 'user', role: 'user', content: 'New message 2')

      messages = history.messages(conversation_id: conversation_id, since: cutoff_time)

      expect(messages.length).to eq(2)
      expect(messages[0]['content']).to eq('New message 1')
      expect(messages[1]['content']).to eq('New message 2')
    end

    it 'combines since and include_in_context filters' do
      history.add_message(conversation_id: conversation_id, actor: 'user', role: 'user', content: 'Old')

      sleep 0.01
      cutoff_time = Time.now
      sleep 0.01

      history.add_message(conversation_id: conversation_id, actor: 'user', role: 'user', content: 'New in context', include_in_context: true)
      history.add_message(conversation_id: conversation_id, actor: 'user', role: 'user', content: 'New not in context', include_in_context: false)

      messages = history.messages(conversation_id: conversation_id, since: cutoff_time, include_in_context_only: true)

      expect(messages.length).to eq(1)
      expect(messages[0]['content']).to eq('New in context')
    end
  end

  describe '#messages_since' do
    let(:conversation_id) { history.create_conversation }

    it 'returns only messages after the specified id' do
      history.add_message(conversation_id: conversation_id, actor: 'user', role: 'user', content: 'M1')
      history.add_message(conversation_id: conversation_id, actor: 'user', role: 'user', content: 'M2')
      history.add_message(conversation_id: conversation_id, actor: 'user', role: 'user', content: 'M3')

      messages = history.messages(conversation_id: conversation_id)
      first_id = messages[0]['id']

      new_messages = history.messages_since(conversation_id: conversation_id, message_id: first_id)
      expect(new_messages.length).to eq(2)
      expect(new_messages[0]['content']).to eq('M2')
      expect(new_messages[1]['content']).to eq('M3')
    end
  end

  describe '#session_tokens' do
    let(:conversation_id) { history.create_conversation }

    it 'returns cumulative token counts since a given time' do
      session_start = Time.now - 60

      sleep 0.01
      history.add_message(
        conversation_id: conversation_id,
        actor: 'assistant',
        role: 'assistant',
        content: 'First',
        tokens_input: 10,
        tokens_output: 5
      )

      history.add_message(
        conversation_id: conversation_id,
        actor: 'assistant',
        role: 'assistant',
        content: 'Second',
        tokens_input: 20,
        tokens_output: 8
      )

      tokens = history.session_tokens(conversation_id: conversation_id, since: session_start)

      # Input tokens should be MAX (20), not SUM (30), because each API call
      # reports the total context size, which already includes previous messages
      expect(tokens['input']).to eq(20)
      expect(tokens['output']).to eq(13)
      expect(tokens['total']).to eq(33)
    end

    it 'excludes messages before the session start time' do
      history.add_message(
        conversation_id: conversation_id,
        actor: 'assistant',
        role: 'assistant',
        content: 'Old message',
        tokens_input: 100,
        tokens_output: 50
      )

      sleep 0.01
      session_start = Time.now
      sleep 0.01

      history.add_message(
        conversation_id: conversation_id,
        actor: 'assistant',
        role: 'assistant',
        content: 'New message',
        tokens_input: 10,
        tokens_output: 5
      )

      tokens = history.session_tokens(conversation_id: conversation_id, since: session_start)

      expect(tokens['input']).to eq(10)
      expect(tokens['output']).to eq(5)
      expect(tokens['total']).to eq(15)
    end

    it 'returns zero for messages without tokens' do
      session_start = Time.now - 60

      sleep 0.01
      history.add_message(
        conversation_id: conversation_id,
        actor: 'user',
        role: 'user',
        content: 'User message'
      )

      tokens = history.session_tokens(conversation_id: conversation_id, since: session_start)

      expect(tokens['input']).to eq(0)
      expect(tokens['output']).to eq(0)
      expect(tokens['total']).to eq(0)
    end
  end

  describe '#list_tables' do
    it 'returns list of table names' do
      tables = history.list_tables

      expect(tables).to be_an(Array)
      expect(tables).to include('conversations')
      expect(tables).to include('messages')
      expect(tables).to include('appconfig')
    end
  end

  describe '#describe_table' do
    it 'returns schema information for a table' do
      columns = history.describe_table('messages')

      expect(columns).to be_an(Array)
      expect(columns.first).to have_key('column_name')
      expect(columns.first).to have_key('column_type')

      column_names = columns.map { |c| c['column_name'] }
      expect(column_names).to include('id')
      expect(column_names).to include('conversation_id')
      expect(column_names).to include('content')
    end
  end

  describe '#execute_query' do
    let(:conversation_id) { history.create_conversation }

    before do
      history.add_message(conversation_id: conversation_id, actor: 'user', role: 'user', content: 'Test 1')
      history.add_message(conversation_id: conversation_id, actor: 'user', role: 'user', content: 'Test 2')
    end

    it 'executes SELECT queries' do
      result = history.execute_query("SELECT content FROM messages WHERE conversation_id = #{conversation_id}")

      expect(result).to be_an(Array)
      expect(result.length).to eq(2)
      expect(result.first).to have_key('content')
    end

    it 'caps results at 500 rows' do
      # Add more than 500 messages
      510.times do |i|
        history.add_message(conversation_id: conversation_id, actor: 'user', role: 'user', content: "Message #{i}")
      end

      result = history.execute_query("SELECT * FROM messages")

      expect(result.length).to eq(500)
    end

    it 'caps results at 500 rows even with higher LIMIT' do
      # Add more than 500 messages
      510.times do |i|
        history.add_message(conversation_id: conversation_id, actor: 'user', role: 'user', content: "Message #{i}")
      end

      result = history.execute_query("SELECT * FROM messages LIMIT 1000")

      expect(result.length).to eq(500)
    end

    it 'rejects non-SELECT queries' do
      expect {
        history.execute_query("INSERT INTO messages (content) VALUES ('bad')")
      }.to raise_error(ArgumentError, /Only read-only queries/)
    end

    it 'allows SHOW queries' do
      result = history.execute_query("SHOW TABLES")

      expect(result).to be_an(Array)
    end
  end

  describe 'appconfig' do
    it 'sets and gets config values' do
      history.set_config('test_key', 'test_value')
      expect(history.get_config('test_key')).to eq('test_value')
    end

    it 'returns default value for non-existent key' do
      expect(history.get_config('nonexistent', default: 'default')).to eq('default')
    end

    it 'replaces existing values' do
      history.set_config('key', 'value1')
      history.set_config('key', 'value2')
      expect(history.get_config('key')).to eq('value2')
    end
  end

  describe 'worker tracking' do
    it 'starts with zero workers' do
      expect(history.workers_idle?).to be true
      expect(history.get_config('active_workers')).to eq('0')
    end

    it 'increments and decrements workers' do
      history.increment_workers
      expect(history.workers_idle?).to be false
      expect(history.get_config('active_workers')).to eq('1')

      history.increment_workers
      expect(history.get_config('active_workers')).to eq('2')

      history.decrement_workers
      expect(history.get_config('active_workers')).to eq('1')

      history.decrement_workers
      expect(history.workers_idle?).to be true
    end

    it 'does not go below zero when decrementing' do
      history.decrement_workers
      history.decrement_workers
      expect(history.get_config('active_workers')).to eq('0')
    end
  end

  describe 'exchanges' do
    let(:conversation_id) { history.create_conversation }

    describe '#create_exchange' do
      it 'creates a new exchange and returns its id' do
        exchange_id = history.create_exchange(
          conversation_id: conversation_id,
          user_message: 'Test question'
        )

        expect(exchange_id).to be_a(Integer)
        expect(exchange_id).to be > 0
      end

      it 'assigns sequential exchange numbers within a conversation' do
        ex1 = history.create_exchange(conversation_id: conversation_id, user_message: 'Q1')
        ex2 = history.create_exchange(conversation_id: conversation_id, user_message: 'Q2')
        ex3 = history.create_exchange(conversation_id: conversation_id, user_message: 'Q3')

        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)

        expect(exchanges[0]['exchange_number']).to eq(1)
        expect(exchanges[1]['exchange_number']).to eq(2)
        expect(exchanges[2]['exchange_number']).to eq(3)
      end

      it 'starts with status in_progress' do
        exchange_id = history.create_exchange(conversation_id: conversation_id, user_message: 'Q')
        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)

        expect(exchanges.first['status']).to eq('in_progress')
      end

      it 'stores the user message' do
        exchange_id = history.create_exchange(
          conversation_id: conversation_id,
          user_message: 'What is 2+2?'
        )

        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)
        expect(exchanges.first['user_message']).to eq('What is 2+2?')
      end
    end

    describe '#update_exchange' do
      let(:exchange_id) do
        history.create_exchange(conversation_id: conversation_id, user_message: 'Test')
      end

      it 'updates exchange status' do
        history.update_exchange(exchange_id: exchange_id, updates: { status: 'completed' })

        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)
        expect(exchanges.first['status']).to eq('completed')
      end

      it 'updates exchange metrics' do
        history.update_exchange(
          exchange_id: exchange_id,
          updates: {
            tokens_input: 100,
            tokens_output: 50,
            spend: 0.001,
            message_count: 5,
            tool_call_count: 2
          }
        )

        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)
        ex = exchanges.first

        expect(ex['tokens_input']).to eq(100)
        expect(ex['tokens_output']).to eq(50)
        expect(ex['spend']).to be_within(0.000001).of(0.001)
        expect(ex['message_count']).to eq(5)
        expect(ex['tool_call_count']).to eq(2)
      end

      it 'updates assistant message' do
        history.update_exchange(
          exchange_id: exchange_id,
          updates: { assistant_message: 'The answer is 42' }
        )

        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)
        expect(exchanges.first['assistant_message']).to eq('The answer is 42')
      end
    end

    describe '#complete_exchange' do
      let(:exchange_id) do
        history.create_exchange(conversation_id: conversation_id, user_message: 'Test')
      end

      it 'marks exchange as completed' do
        history.complete_exchange(exchange_id: exchange_id)

        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)
        expect(exchanges.first['status']).to eq('completed')
      end

      it 'sets completed_at timestamp' do
        history.complete_exchange(exchange_id: exchange_id)

        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)
        expect(exchanges.first['completed_at']).not_to be_nil
      end

      it 'saves metrics and assistant message' do
        history.complete_exchange(
          exchange_id: exchange_id,
          assistant_message: 'Done!',
          metrics: {
            tokens_input: 75,
            tokens_output: 25,
            spend: 0.0005,
            message_count: 3,
            tool_call_count: 1
          }
        )

        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)
        ex = exchanges.first

        expect(ex['assistant_message']).to eq('Done!')
        expect(ex['tokens_input']).to eq(75)
        expect(ex['tokens_output']).to eq(25)
        expect(ex['spend']).to be_within(0.000001).of(0.0005)
        expect(ex['message_count']).to eq(3)
        expect(ex['tool_call_count']).to eq(1)
      end
    end

    describe '#get_exchange_messages' do
      let(:exchange_id) do
        history.create_exchange(conversation_id: conversation_id, user_message: 'Test')
      end

      it 'returns messages for a specific exchange' do
        history.add_message(
          conversation_id: conversation_id,
          exchange_id: exchange_id,
          actor: 'user',
          role: 'user',
          content: 'Question'
        )

        history.add_message(
          conversation_id: conversation_id,
          exchange_id: exchange_id,
          actor: 'orchestrator',
          role: 'assistant',
          content: 'Answer'
        )

        messages = history.get_exchange_messages(exchange_id: exchange_id)

        expect(messages.length).to eq(2)
        expect(messages[0]['content']).to eq('Question')
        expect(messages[1]['content']).to eq('Answer')
      end

      it 'returns empty array for exchange with no messages' do
        messages = history.get_exchange_messages(exchange_id: exchange_id)
        expect(messages).to eq([])
      end
    end

    describe '#get_conversation_exchanges' do
      it 'returns all exchanges for a conversation' do
        ex1 = history.create_exchange(conversation_id: conversation_id, user_message: 'Q1')
        ex2 = history.create_exchange(conversation_id: conversation_id, user_message: 'Q2')

        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)

        expect(exchanges.length).to eq(2)
        expect(exchanges[0]['user_message']).to eq('Q1')
        expect(exchanges[1]['user_message']).to eq('Q2')
      end

      it 'returns exchanges in order by exchange_number' do
        history.create_exchange(conversation_id: conversation_id, user_message: 'First')
        history.create_exchange(conversation_id: conversation_id, user_message: 'Second')
        history.create_exchange(conversation_id: conversation_id, user_message: 'Third')

        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)

        expect(exchanges[0]['exchange_number']).to eq(1)
        expect(exchanges[1]['exchange_number']).to eq(2)
        expect(exchanges[2]['exchange_number']).to eq(3)
      end
    end

    describe '#migrate_exchanges' do
      it 'creates exchanges from existing messages' do
        # Add messages without exchange_id
        history.add_message(
          conversation_id: conversation_id,
          actor: 'user',
          role: 'user',
          content: 'What is 2+2?'
        )

        history.add_message(
          conversation_id: conversation_id,
          actor: 'orchestrator',
          role: 'assistant',
          content: '4',
          model: 'test-model',
          tokens_input: 50,
          tokens_output: 10,
          spend: 0.0005
        )

        # Run migration
        stats = history.migrate_exchanges

        expect(stats[:conversations]).to eq(1)
        expect(stats[:exchanges_created]).to eq(1)
        expect(stats[:messages_updated]).to eq(2)

        # Verify exchange was created
        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)
        expect(exchanges.length).to eq(1)
        expect(exchanges.first['user_message']).to eq('What is 2+2?')
        expect(exchanges.first['assistant_message']).to eq('4')
      end

      it 'groups multiple user/assistant pairs into separate exchanges' do
        # First exchange
        history.add_message(conversation_id: conversation_id, actor: 'user', role: 'user', content: 'Q1')
        history.add_message(conversation_id: conversation_id, actor: 'orchestrator', role: 'assistant', content: 'A1')

        # Second exchange
        history.add_message(conversation_id: conversation_id, actor: 'user', role: 'user', content: 'Q2')
        history.add_message(conversation_id: conversation_id, actor: 'orchestrator', role: 'assistant', content: 'A2')

        stats = history.migrate_exchanges

        expect(stats[:exchanges_created]).to eq(2)

        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)
        expect(exchanges[0]['user_message']).to eq('Q1')
        expect(exchanges[0]['assistant_message']).to eq('A1')
        expect(exchanges[1]['user_message']).to eq('Q2')
        expect(exchanges[1]['assistant_message']).to eq('A2')
      end

      it 'calculates metrics from messages' do
        history.add_message(conversation_id: conversation_id, actor: 'user', role: 'user', content: 'Q')
        history.add_message(
          conversation_id: conversation_id,
          actor: 'orchestrator',
          role: 'assistant',
          content: 'A',
          tokens_input: 100,
          tokens_output: 50,
          spend: 0.001
        )

        history.migrate_exchanges

        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)
        ex = exchanges.first

        expect(ex['tokens_input']).to eq(100)
        expect(ex['tokens_output']).to eq(50)
        expect(ex['spend']).to be_within(0.000001).of(0.001)
        expect(ex['message_count']).to eq(2)
      end

      it 'excludes spell_checker messages from exchange boundaries' do
        history.add_message(conversation_id: conversation_id, actor: 'spell_checker', role: 'user', content: 'Check')
        history.add_message(conversation_id: conversation_id, actor: 'spell_checker', role: 'assistant', content: 'Checked')
        history.add_message(conversation_id: conversation_id, actor: 'user', role: 'user', content: 'Real question')
        history.add_message(conversation_id: conversation_id, actor: 'orchestrator', role: 'assistant', content: 'Answer')

        stats = history.migrate_exchanges

        # Should create only 1 exchange (spell_checker messages don't start exchanges)
        expect(stats[:exchanges_created]).to eq(1)

        exchanges = history.get_conversation_exchanges(conversation_id: conversation_id)
        expect(exchanges.first['user_message']).to eq('Real question')
      end
    end

    describe 'messages with exchange_id' do
      let(:exchange_id) do
        history.create_exchange(conversation_id: conversation_id, user_message: 'Test')
      end

      it 'allows adding messages with exchange_id' do
        history.add_message(
          conversation_id: conversation_id,
          exchange_id: exchange_id,
          actor: 'user',
          role: 'user',
          content: 'Test'
        )

        messages = history.messages(conversation_id: conversation_id, include_in_context_only: false)
        expect(messages.first['exchange_id']).to eq(exchange_id)
      end

      it 'allows messages without exchange_id (backward compatibility)' do
        history.add_message(
          conversation_id: conversation_id,
          actor: 'user',
          role: 'user',
          content: 'Test'
        )

        messages = history.messages(conversation_id: conversation_id, include_in_context_only: false)
        expect(messages.first['exchange_id']).to be_nil
      end
    end
  end
end
