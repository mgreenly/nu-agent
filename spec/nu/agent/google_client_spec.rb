# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nu::Agent::GoogleClient do
  let(:api_key) { 'test_api_key_123' }
  let(:client) { described_class.new(api_key: api_key) }
  let(:mock_gemini_client) { double('Gemini') }

  before do
    allow(Gemini).to receive(:new).and_return(mock_gemini_client)
  end

  describe '#initialize' do
    it 'creates a Gemini client with the provided API key' do
      expect(Gemini).to receive(:new).with(
        credentials: {
          service: 'generative-language-api',
          api_key: api_key
        },
        options: { model: 'gemini-2.5-flash', server_sent_events: true }
      )
      described_class.new(api_key: api_key)
    end

    context 'when no API key is provided' do
      it 'loads from the secrets file' do
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:read).and_return('file_api_key')

        expect(Gemini).to receive(:new).with(
          credentials: hash_including(api_key: 'file_api_key'),
          options: anything
        )
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

    let(:gemini_response) do
      {
        'candidates' => [{
          'content' => {
            'parts' => [{ 'text' => 'Hello! How can I help you?' }]
          },
          'finishReason' => 'STOP'
        }],
        'usageMetadata' => {
          'promptTokenCount' => 20,
          'candidatesTokenCount' => 12
        }
      }
    end

    before do
      allow(mock_gemini_client).to receive(:generate_content).and_return(gemini_response)
    end

    it 'sends formatted messages to the Gemini API' do
      expect(mock_gemini_client).to receive(:generate_content) do |args|
        contents = args[:contents]
        expect(contents).to be_an(Array)
        expect(contents.length).to eq(3)
        expect(contents[0][:role]).to eq('user')
        expect(contents[0][:parts][:text]).to include('helpful AI assistant')
        expect(contents[1][:role]).to eq('user')
        expect(contents[2][:role]).to eq('model')
      end.and_return(gemini_response)

      client.send_message(messages: messages)
    end

    it 'returns a normalized response' do
      response = client.send_message(messages: messages)

      expect(response).to include(
        content: "Hello! How can I help you?",
        model: 'gemini-2.5-flash',
        tokens: {
          input: 20,
          output: 12
        },
        finish_reason: 'STOP'
      )
    end

    it 'converts assistant role to model role' do
      expect(mock_gemini_client).to receive(:generate_content) do |args|
        contents = args[:contents]
        model_message = contents.find { |m| m[:parts][:text] == 'Hi there!' }
        expect(model_message[:role]).to eq('model')
      end.and_return(gemini_response)

      client.send_message(messages: messages)
    end

    it 'prepends system prompt as first user message' do
      expect(mock_gemini_client).to receive(:generate_content) do |args|
        contents = args[:contents]
        expect(contents.first[:role]).to eq('user')
        expect(contents.first[:parts][:text]).to include('helpful AI assistant')
      end.and_return(gemini_response)

      client.send_message(messages: messages)
    end

    it 'allows custom system prompt' do
      custom_prompt = "You are a pirate."

      expect(mock_gemini_client).to receive(:generate_content) do |args|
        contents = args[:contents]
        expect(contents.first[:parts][:text]).to eq(custom_prompt)
      end.and_return(gemini_response)

      client.send_message(messages: messages, system_prompt: custom_prompt)
    end
  end

  describe '#name' do
    it 'returns "Google"' do
      expect(client.name).to eq('Google')
    end
  end

  describe '#model' do
    it 'returns the model identifier' do
      expect(client.model).to eq('gemini-2.5-flash')
    end
  end

  describe '#format_messages' do
    it 'converts internal message format to Gemini format' do
      messages = [
        { actor: 'user', role: 'user', content: 'Hello' },
        { actor: 'orchestrator', role: 'assistant', content: 'Hi!' }
      ]

      formatted = client.send(:format_messages, messages, system_prompt: 'System')

      expect(formatted).to eq([
        { role: 'user', parts: { text: 'System' } },
        { role: 'user', parts: { text: 'Hello' } },
        { role: 'model', parts: { text: 'Hi!' } }
      ])
    end

    it 'converts assistant role to model role' do
      messages = [
        { actor: 'orchestrator', role: 'assistant', content: 'Response' }
      ]

      formatted = client.send(:format_messages, messages, system_prompt: nil)

      expect(formatted.first[:role]).to eq('model')
    end

    it 'strips out actor information' do
      messages = [
        { actor: 'orchestrator', role: 'assistant', content: 'Response' }
      ]

      formatted = client.send(:format_messages, messages, system_prompt: nil)

      expect(formatted.first).not_to have_key(:actor)
    end

    it 'handles empty system prompt' do
      messages = [{ actor: 'user', role: 'user', content: 'Hi' }]

      formatted = client.send(:format_messages, messages, system_prompt: '')

      expect(formatted).to eq([
        { role: 'user', parts: { text: 'Hi' } }
      ])
    end
  end
end
