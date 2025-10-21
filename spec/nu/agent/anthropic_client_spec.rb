# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nu::Agent::AnthropicClient do
  let(:api_key) { 'test_api_key_123' }
  let(:client) { described_class.new(api_key: api_key) }
  let(:mock_anthropic_client) { instance_double(Anthropic::Client) }

  before do
    allow(Anthropic::Client).to receive(:new).and_return(mock_anthropic_client)
  end

  describe '#initialize' do
    it 'creates an Anthropic client with the provided API key' do
      expect(Anthropic::Client).to receive(:new).with(access_token: api_key)
      described_class.new(api_key: api_key)
    end

    context 'when no API key is provided' do
      it 'loads from the secrets file' do
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:read).and_return('file_api_key')

        expect(Anthropic::Client).to receive(:new).with(access_token: 'file_api_key')
        described_class.new
      end

      it 'raises an error if the secrets file does not exist' do
        allow(File).to receive(:exist?).and_return(false)

        expect {
          described_class.new
        }.to raise_error(Nu::Agent::Error, /API key not found/)
      end
    end
  end

  describe '#send_message' do
    let(:messages) do
      [
        { actor: 'user', role: 'user', content: 'Hello' },
        { actor: 'orchestrator', role: 'assistant', content: 'Hi there!' }
      ]
    end

    let(:anthropic_response) do
      {
        "content" => [{ "text" => "Hello! How can I help you?" }],
        "usage" => {
          "input_tokens" => 15,
          "output_tokens" => 10
        },
        "stop_reason" => "end_turn"
      }
    end

    before do
      allow(mock_anthropic_client).to receive(:messages).and_return(anthropic_response)
    end

    it 'sends formatted messages to the Anthropic API' do
      expect(mock_anthropic_client).to receive(:messages).with(
        parameters: hash_including(
          model: 'claude-sonnet-4-20250514',
          messages: [
            { role: 'user', content: 'Hello' },
            { role: 'assistant', content: 'Hi there!' }
          ]
        )
      )

      client.send_message(messages: messages)
    end

    it 'returns a normalized response' do
      response = client.send_message(messages: messages)

      expect(response).to include(
        content: "Hello! How can I help you?",
        model: 'claude-sonnet-4-20250514',
        tokens: {
          input: 15,
          output: 10
        },
        finish_reason: "end_turn"
      )
    end

    it 'includes the system prompt' do
      expect(mock_anthropic_client).to receive(:messages).with(
        parameters: hash_including(
          system: a_string_including('helpful AI assistant')
        )
      )

      client.send_message(messages: messages)
    end

    it 'allows custom system prompt' do
      custom_prompt = "You are a pirate."

      expect(mock_anthropic_client).to receive(:messages).with(
        parameters: hash_including(
          system: custom_prompt
        )
      )

      client.send_message(messages: messages, system_prompt: custom_prompt)
    end
  end

  describe '#name' do
    it 'returns "Anthropic"' do
      expect(client.name).to eq('Anthropic')
    end
  end

  describe '#model' do
    it 'returns the model identifier' do
      expect(client.model).to eq('claude-sonnet-4-20250514')
    end
  end

  describe '#format_messages' do
    it 'converts internal message format to Anthropic format' do
      messages = [
        { actor: 'user', role: 'user', content: 'Hello' },
        { actor: 'orchestrator', role: 'assistant', content: 'Hi!' }
      ]

      formatted = client.send(:format_messages, messages)

      expect(formatted).to eq([
        { role: 'user', content: 'Hello' },
        { role: 'assistant', content: 'Hi!' }
      ])
    end

    it 'strips out actor information' do
      messages = [
        { actor: 'orchestrator', role: 'assistant', content: 'Response' }
      ]

      formatted = client.send(:format_messages, messages)

      expect(formatted.first).not_to have_key(:actor)
    end
  end
end
