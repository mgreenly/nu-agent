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
      expect(messages.first[:actor]).to eq('user')
      expect(messages.first[:role]).to eq('user')
      expect(messages.first[:content]).to eq('Hello, world!')
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
      expect(messages.first[:model]).to eq('claude-sonnet-4-20250514')
      expect(messages.first[:tokens_input]).to eq(10)
      expect(messages.first[:tokens_output]).to eq(5)
    end

    it 'handles SQL special characters in content' do
      history.add_message(
        conversation_id: conversation_id,
        actor: 'user',
        role: 'user',
        content: "It's a test with 'quotes'"
      )

      messages = history.messages(conversation_id: conversation_id)
      expect(messages.first[:content]).to eq("It's a test with 'quotes'")
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
      expect(messages[0][:content]).to eq('Message 1')
      expect(messages[1][:content]).to eq('Message 3')
    end

    it 'returns all messages including metadata when requested' do
      messages = history.messages(conversation_id: conversation_id, include_in_context_only: false)
      expect(messages.length).to eq(3)
      expect(messages[1][:content]).to eq('Message 2')
    end

    it 'returns empty array for non-existent conversation' do
      messages = history.messages(conversation_id: 999)
      expect(messages).to eq([])
    end
  end

  describe '#messages_since' do
    let(:conversation_id) { history.create_conversation }

    it 'returns only messages after the specified id' do
      history.add_message(conversation_id: conversation_id, actor: 'user', role: 'user', content: 'M1')
      history.add_message(conversation_id: conversation_id, actor: 'user', role: 'user', content: 'M2')
      history.add_message(conversation_id: conversation_id, actor: 'user', role: 'user', content: 'M3')

      messages = history.messages(conversation_id: conversation_id)
      first_id = messages[0][:id]

      new_messages = history.messages_since(conversation_id: conversation_id, message_id: first_id)
      expect(new_messages.length).to eq(2)
      expect(new_messages[0][:content]).to eq('M2')
      expect(new_messages[1][:content]).to eq('M3')
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
end
