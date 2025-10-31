# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nu::Agent::ParallelExecutor do
  let(:tool_registry) { Nu::Agent::ToolRegistry.instance }
  let(:history) { instance_double(Nu::Agent::History) }
  let(:executor) { described_class.new(tool_registry: tool_registry, history: history) }

  describe '#execute_batch' do
    context 'with a single tool call' do
      let(:tool_call) do
        {
          'id' => 'call_1',
          'type' => 'function',
          'function' => {
            'name' => 'file_read',
            'arguments' => '{"file": "/tmp/test.txt"}'
          }
        }
      end

      it 'executes the tool call and returns the result' do
        allow(File).to receive(:exist?).with('/tmp/test.txt').and_return(true)
        allow(File).to receive(:read).with('/tmp/test.txt').and_return('test content')

        results = executor.execute_batch([tool_call])

        expect(results).to be_an(Array)
        expect(results.length).to eq(1)
        expect(results[0]).to include(
          tool_call: tool_call,
          result: hash_including(
            success: true,
            output: 'test content'
          )
        )
      end

      it 'preserves tool_call and result in output' do
        allow(File).to receive(:exist?).with('/tmp/test.txt').and_return(true)
        allow(File).to receive(:read).with('/tmp/test.txt').and_return('test content')

        results = executor.execute_batch([tool_call])

        expect(results[0][:tool_call]).to eq(tool_call)
        expect(results[0][:result]).to be_a(Hash)
        expect(results[0][:result][:success]).to eq(true)
      end

      it 'handles tool execution errors gracefully' do
        allow(File).to receive(:exist?).with('/tmp/test.txt').and_return(false)

        results = executor.execute_batch([tool_call])

        expect(results).to be_an(Array)
        expect(results.length).to eq(1)
        expect(results[0]).to include(
          tool_call: tool_call,
          result: hash_including(
            success: false,
            error: /does not exist/
          )
        )
      end
    end
  end
end
