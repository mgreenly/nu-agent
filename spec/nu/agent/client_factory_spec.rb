# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nu::Agent::ClientFactory do
  describe '.create' do
    it 'creates an Anthropic client for claude-haiku-4-5' do
      client = described_class.create('claude-haiku-4-5')
      expect(client).to be_a(Nu::Agent::Clients::Anthropic)
      expect(client.model).to eq('claude-haiku-4-5')
    end

    it 'creates an Anthropic client for claude-sonnet-4-5' do
      client = described_class.create('claude-sonnet-4-5')
      expect(client).to be_a(Nu::Agent::Clients::Anthropic)
      expect(client.model).to eq('claude-sonnet-4-5')
    end

    it 'creates an Anthropic client for claude-opus-4-1' do
      client = described_class.create('claude-opus-4-1')
      expect(client).to be_a(Nu::Agent::Clients::Anthropic)
      expect(client.model).to eq('claude-opus-4-1')
    end

    it 'creates a Google client for gemini-2.5-flash-lite' do
      client = described_class.create('gemini-2.5-flash-lite')
      expect(client).to be_a(Nu::Agent::Clients::Google)
      expect(client.model).to eq('gemini-2.5-flash-lite')
    end

    it 'creates a Google client for gemini-2.5-flash' do
      client = described_class.create('gemini-2.5-flash')
      expect(client).to be_a(Nu::Agent::Clients::Google)
      expect(client.model).to eq('gemini-2.5-flash')
    end

    it 'creates a Google client for gemini-2.5-pro' do
      client = described_class.create('gemini-2.5-pro')
      expect(client).to be_a(Nu::Agent::Clients::Google)
      expect(client.model).to eq('gemini-2.5-pro')
    end

    it 'creates an OpenAI client for gpt-5-nano-2025-08-07' do
      client = described_class.create('gpt-5-nano-2025-08-07')
      expect(client).to be_a(Nu::Agent::Clients::OpenAI)
      expect(client.model).to eq('gpt-5-nano-2025-08-07')
    end

    it 'creates an OpenAI client for gpt-5-mini' do
      client = described_class.create('gpt-5-mini')
      expect(client).to be_a(Nu::Agent::Clients::OpenAI)
      expect(client.model).to eq('gpt-5-mini')
    end

    it 'creates an OpenAI client for gpt-5' do
      client = described_class.create('gpt-5')
      expect(client).to be_a(Nu::Agent::Clients::OpenAI)
      expect(client.model).to eq('gpt-5')
    end

    it 'creates an XAI client for grok-3' do
      client = described_class.create('grok-3')
      expect(client).to be_a(Nu::Agent::Clients::XAI)
      expect(client.model).to eq('grok-3')
    end

    it 'creates an XAI client for grok-code-fast-1' do
      client = described_class.create('grok-code-fast-1')
      expect(client).to be_a(Nu::Agent::Clients::XAI)
      expect(client.model).to eq('grok-code-fast-1')
    end

    it 'raises an error when no model is specified' do
      expect {
        described_class.create(nil)
      }.to raise_error(Nu::Agent::Error, /Model name is required/)
    end

    it 'raises an error for unknown models' do
      expect {
        described_class.create('unknown-model')
      }.to raise_error(Nu::Agent::Error, /Unknown model/)
    end

    it 'handles case-insensitive model names' do
      client = described_class.create('GPT-5-NANO-2025-08-07')
      expect(client).to be_a(Nu::Agent::Clients::OpenAI)
      expect(client.model).to eq('gpt-5-nano-2025-08-07')
    end

    it 'handles whitespace in model names' do
      client = described_class.create('  gpt-5-nano-2025-08-07  ')
      expect(client).to be_a(Nu::Agent::Clients::OpenAI)
      expect(client.model).to eq('gpt-5-nano-2025-08-07')
    end
  end

  describe '.available_models' do
    it 'returns a hash of all available models by provider' do
      models = described_class.available_models

      expect(models[:anthropic]).to eq(['claude-haiku-4-5', 'claude-sonnet-4-5', 'claude-opus-4-1'])
      expect(models[:google]).to eq(['gemini-2.5-flash-lite', 'gemini-2.5-flash', 'gemini-2.5-pro'])
      expect(models[:openai]).to eq(['gpt-5-nano-2025-08-07', 'gpt-5-mini', 'gpt-5'])
      expect(models[:xai]).to eq(['grok-3', 'grok-code-fast-1'])
    end
  end

  describe '.display_models' do
    it 'returns the same as available_models' do
      expect(described_class.display_models).to eq(described_class.available_models)
    end
  end
end
