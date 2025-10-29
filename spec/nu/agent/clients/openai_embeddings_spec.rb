# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::Clients::OpenAIEmbeddings do
  let(:api_key) { "test_api_key_123" }
  let(:client) { described_class.new(api_key: api_key) }
  let(:mock_openai_client) { instance_double(OpenAI::Client) }

  before do
    allow(OpenAI::Client).to receive(:new).and_return(mock_openai_client)
  end

  describe "#initialize" do
    it "creates an OpenAI client with the provided API key" do
      expect(OpenAI::Client).to receive(:new).with(access_token: api_key)
      described_class.new(api_key: api_key)
    end

    context "when no API key is provided" do
      it "loads from the secrets file" do
        allow(File).to receive_messages(exist?: true, read: "file_api_key\n")

        expect(OpenAI::Client).to receive(:new).with(access_token: "file_api_key")
        described_class.new
      end

      it "raises an error if the secrets file does not exist" do
        allow(File).to receive(:exist?).and_return(false)

        expect do
          described_class.new
        end.to raise_error(Nu::Agent::Error, /API key not found/)
      end

      it "raises an error when file reading fails" do
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:read).and_raise(StandardError.new("Permission denied"))

        expect do
          described_class.new
        end.to raise_error(Nu::Agent::Error, /Error loading API key: Permission denied/)
      end
    end
  end

  describe "#name" do
    it "returns the client name with model" do
      expect(client.name).to eq("OpenAI Embeddings (text-embedding-3-small)")
    end
  end

  describe "#generate_embedding" do
    let(:embedding_vector) { Array.new(1536) { rand } }
    let(:openai_response) do
      {
        "data" => [
          { "embedding" => embedding_vector, "index" => 0 }
        ],
        "usage" => {
          "total_tokens" => 5
        },
        "model" => "text-embedding-3-small"
      }
    end

    before do
      allow(mock_openai_client).to receive(:embeddings).and_return(openai_response)
    end

    context "with single text input" do
      it "generates embedding for single text" do
        expect(mock_openai_client).to receive(:embeddings).with(
          parameters: {
            model: "text-embedding-3-small",
            input: ["Hello world"]
          }
        ).and_return(openai_response)

        result = client.generate_embedding("Hello world")

        expect(result["embeddings"]).to eq(embedding_vector)
        expect(result["model"]).to eq("text-embedding-3-small")
        expect(result["tokens"]).to eq(5)
        expect(result["spend"]).to be_within(0.0001).of(0.0001)
      end
    end

    context "with array input" do
      let(:embedding_vector2) { Array.new(1536) { rand } }
      let(:openai_response_multi) do
        {
          "data" => [
            { "embedding" => embedding_vector, "index" => 0 },
            { "embedding" => embedding_vector2, "index" => 1 }
          ],
          "usage" => {
            "total_tokens" => 10
          },
          "model" => "text-embedding-3-small"
        }
      end

      it "generates embeddings for multiple texts" do
        allow(mock_openai_client).to receive(:embeddings).and_return(openai_response_multi)

        result = client.generate_embedding(["Text 1", "Text 2"])

        expect(result["embeddings"]).to be_an(Array)
        expect(result["embeddings"].length).to eq(2)
        expect(result["embeddings"][0]).to eq(embedding_vector)
        expect(result["embeddings"][1]).to eq(embedding_vector2)
        expect(result["tokens"]).to eq(10)
        expect(result["spend"]).to be_within(0.00000001).of(0.0000002)
      end
    end

    context "with missing usage information" do
      let(:response_without_usage) do
        {
          "data" => [
            { "embedding" => embedding_vector, "index" => 0 }
          ],
          "model" => "text-embedding-3-small"
        }
      end

      it "defaults to 0 tokens when usage is missing" do
        allow(mock_openai_client).to receive(:embeddings).and_return(response_without_usage)

        result = client.generate_embedding("Hello")

        expect(result["tokens"]).to eq(0)
        expect(result["spend"]).to eq(0.0)
      end
    end

    context "with API errors" do
      let(:error_response) do
        {
          status: 401,
          headers: { "content-type" => "application/json" },
          body: '{"error": {"message": "Invalid API key"}}'
        }
      end

      let(:faraday_error) do
        error = Faraday::UnauthorizedError.new("Unauthorized")
        allow(error).to receive(:response).and_return(error_response)
        error
      end

      it "handles Faraday errors and returns formatted error response" do
        allow(mock_openai_client).to receive(:embeddings).and_raise(faraday_error)

        result = client.generate_embedding("Hello")

        expect(result).to have_key("error")
        expect(result["error"]["status"]).to eq(401)
        expect(result["error"]["headers"]).to eq({ "content-type" => "application/json" })
        expect(result["error"]["body"]).to include("Invalid API key")
        expect(result["embeddings"]).to be_nil
        expect(result["model"]).to eq("text-embedding-3-small")
      end

      it "handles error without response body using response_body method" do
        error = Faraday::Error.new("Connection failed")
        allow(error).to receive_messages(response: nil, response_body: "Connection timeout")

        allow(mock_openai_client).to receive(:embeddings).and_raise(error)

        result = client.generate_embedding("Hello")

        expect(result).to have_key("error")
        expect(result["error"]["status"]).to eq("unknown")
        expect(result["error"]["body"]).to eq("Connection timeout")
      end

      it "handles error with response hash using [] access" do
        error = Faraday::Error.new("Request failed")
        response_hash = { body: "Server error", status: 500 }
        allow(error).to receive(:response).and_return(response_hash)

        allow(mock_openai_client).to receive(:embeddings).and_raise(error)

        result = client.generate_embedding("Hello")

        expect(result).to have_key("error")
        expect(result["error"]["body"]).to eq("Server error")
      end

      it "handles error with response object that supports [] but not dig for body" do
        error = Faraday::Error.new("Request failed")
        # Create a response object where dig(:body) returns nil but [:body] works
        response_obj = double("response")
        allow(response_obj).to receive(:dig).with(:body).and_return(nil)
        allow(response_obj).to receive(:dig).with(:status).and_return(500)
        allow(response_obj).to receive(:dig).with(:headers).and_return({})
        allow(response_obj).to receive(:[]).with(:body).and_return("Error via [] access")

        allow(error).to receive_messages(response: response_obj, response_body: nil)

        allow(mock_openai_client).to receive(:embeddings).and_raise(error)

        result = client.generate_embedding("Hello")

        expect(result).to have_key("error")
        expect(result["error"]["body"]).to eq("Error via [] access")
      end

      it "falls back to error message when no body is available" do
        error = Faraday::Error.new("Network error")
        allow(error).to receive_messages(response: nil, response_body: nil)

        allow(mock_openai_client).to receive(:embeddings).and_raise(error)

        result = client.generate_embedding("Hello")

        expect(result).to have_key("error")
        expect(result["error"]["body"]).to eq("Network error")
      end
    end

    context "with cost calculation" do
      it "calculates cost correctly for various token amounts" do
        # 1 million tokens should cost exactly $0.020
        response = openai_response.dup
        response["usage"]["total_tokens"] = 1_000_000

        allow(mock_openai_client).to receive(:embeddings).and_return(response)

        result = client.generate_embedding("Test")

        expect(result["spend"]).to eq(0.020)
      end

      it "calculates cost for small token amounts" do
        response = openai_response.dup
        response["usage"]["total_tokens"] = 100

        allow(mock_openai_client).to receive(:embeddings).and_return(response)

        result = client.generate_embedding("Test")

        expect(result["spend"]).to be_within(0.000001).of(0.000002)
      end
    end
  end
end
