# frozen_string_literal: true

require "spec_helper"
require "net/http"

RSpec.describe Nu::Agent::Tools::SearchInternet do
  let(:tool) { described_class.new }
  let(:credentials_path) { File.join(Dir.home, ".secrets", "GOOGLE_SEARCH_API") }
  let(:api_key) { "test_api_key" }
  let(:cse_id) { "test_cse_id" }

  describe "#name" do
    it "returns the tool name" do
      expect(tool.name).to eq("search_internet")
    end
  end

  describe "#description" do
    it "returns a description" do
      expect(tool.description).to include("PREFERRED tool for searching the internet")
    end

    it "mentions Google Custom Search API" do
      expect(tool.description).to include("Google Custom Search API")
    end

    it "describes what results include" do
      expect(tool.description).to include("titles, URLs, and snippets")
    end
  end

  describe "#parameters" do
    it "defines expected parameters" do
      params = tool.parameters

      expect(params).to have_key(:query)
      expect(params).to have_key(:num_results)
    end

    it "marks query as required" do
      expect(tool.parameters[:query][:required]).to be true
    end

    it "marks num_results as optional" do
      expect(tool.parameters[:num_results][:required]).to be false
    end
  end

  describe "#available?" do
    it "returns true when credentials file exists with valid content" do
      allow(File).to receive(:exist?).with(credentials_path).and_return(true)
      allow(File).to receive(:readable?).with(credentials_path).and_return(true)
      allow(File).to receive(:readlines).with(credentials_path).and_return(%W[api_key\n cse_id\n])

      expect(tool.available?).to be true
    end

    it "returns false when credentials file doesn't exist" do
      allow(File).to receive(:exist?).with(credentials_path).and_return(false)

      expect(tool).not_to be_available
    end

    it "returns false when credentials file has less than 2 lines" do
      allow(File).to receive(:exist?).with(credentials_path).and_return(true)
      allow(File).to receive(:readable?).with(credentials_path).and_return(true)
      allow(File).to receive(:readlines).with(credentials_path).and_return(["api_key\n"])

      expect(tool).not_to be_available
    end
  end

  describe "#execute" do
    context "with missing query parameter" do
      it "returns error when query is nil" do
        result = tool.execute(arguments: {})

        expect(result[:error]).to eq("query is required")
        expect(result[:results]).to eq([])
      end

      it "returns error when query is empty string" do
        result = tool.execute(arguments: { query: "" })

        expect(result[:error]).to eq("query is required")
        expect(result[:results]).to eq([])
      end
    end

    context "with credentials errors" do
      it "returns error when credentials file doesn't exist" do
        allow(File).to receive(:exist?).with(credentials_path).and_return(false)

        result = tool.execute(arguments: { query: "test search" })

        expect(result[:error]).to include("Google Search API credentials not found")
        expect(result[:results]).to eq([])
      end

      it "returns error when credentials file is not readable" do
        allow(File).to receive(:exist?).with(credentials_path).and_return(true)
        allow(File).to receive(:readable?).with(credentials_path).and_return(false)

        result = tool.execute(arguments: { query: "test search" })

        expect(result[:error]).to include("Google Search API credentials not found")
        expect(result[:results]).to eq([])
      end

      it "returns error when credentials file has insufficient lines" do
        allow(File).to receive(:exist?).with(credentials_path).and_return(true)
        allow(File).to receive(:readable?).with(credentials_path).and_return(true)
        allow(File).to receive(:readlines).with(credentials_path).and_return(["only_one_line\n"])

        result = tool.execute(arguments: { query: "test search" })

        expect(result[:error]).to include("Google Search API credentials not found")
        expect(result[:results]).to eq([])
      end
    end

    context "with string keys in arguments" do
      before do
        setup_valid_credentials
        setup_successful_http_response
      end

      it "accepts string keys for all parameters" do
        result = tool.execute(
          arguments: {
            "query" => "test search",
            "num_results" => 3
          }
        )

        expect(result[:query]).to eq("test search")
      end
    end

    context "with num_results parameter" do
      before do
        setup_valid_credentials
      end

      it "defaults to 5 results when not specified" do
        expect(Net::HTTP).to receive(:get_response) do |uri|
          expect(uri.query).to include("num=5")
          setup_successful_response
        end

        tool.execute(arguments: { query: "test" })
      end

      it "uses specified num_results" do
        expect(Net::HTTP).to receive(:get_response) do |uri|
          expect(uri.query).to include("num=3")
          setup_successful_response
        end

        tool.execute(arguments: { query: "test", num_results: 3 })
      end

      it "clamps num_results to minimum of 1" do
        expect(Net::HTTP).to receive(:get_response) do |uri|
          expect(uri.query).to include("num=1")
          setup_successful_response
        end

        tool.execute(arguments: { query: "test", num_results: 0 })
      end

      it "clamps num_results to maximum of 10" do
        expect(Net::HTTP).to receive(:get_response) do |uri|
          expect(uri.query).to include("num=10")
          setup_successful_response
        end

        tool.execute(arguments: { query: "test", num_results: 15 })
      end
    end

    context "with successful API response" do
      before do
        setup_valid_credentials
        setup_successful_http_response
      end

      it "returns query in response" do
        result = tool.execute(arguments: { query: "ruby testing" })

        expect(result[:query]).to eq("ruby testing")
      end

      it "returns total_results from API" do
        result = tool.execute(arguments: { query: "ruby testing" })

        expect(result[:total_results]).to eq("1,234,567")
      end

      it "returns parsed search results" do
        result = tool.execute(arguments: { query: "ruby testing" })

        expect(result[:results]).to be_an(Array)
        expect(result[:results].length).to eq(2)
      end

      it "includes title, url, and snippet for each result" do
        result = tool.execute(arguments: { query: "ruby testing" })

        first_result = result[:results][0]
        expect(first_result[:title]).to eq("Ruby Testing Guide")
        expect(first_result[:url]).to eq("https://example.com/1")
        expect(first_result[:snippet]).to eq("A comprehensive guide to testing in Ruby")
      end

      it "returns count of results" do
        result = tool.execute(arguments: { query: "ruby testing" })

        expect(result[:count]).to eq(2)
      end
    end

    context "with HTTP error responses" do
      before do
        setup_valid_credentials
      end

      it "handles non-success HTTP response" do
        error_response = instance_double(Net::HTTPBadRequest, code: "400", message: "Bad Request", body: "{}")
        allow(error_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
        allow(Net::HTTP).to receive(:get_response).and_return(error_response)

        result = tool.execute(arguments: { query: "test" })

        expect(result[:error]).to include("HTTP 400: Bad Request")
        expect(result[:results]).to eq([])
      end

      it "includes API error message when available in response" do
        error_body = { "error" => { "message" => "Invalid API key" } }.to_json
        error_response = instance_double(
          Net::HTTPUnauthorized,
          code: "401",
          message: "Unauthorized",
          body: error_body
        )
        allow(error_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
        allow(Net::HTTP).to receive(:get_response).and_return(error_response)

        result = tool.execute(arguments: { query: "test" })

        expect(result[:error]).to include("HTTP 401: Unauthorized")
        expect(result[:error]).to include("Invalid API key")
      end

      it "handles JSON parse errors in error response body" do
        error_response = instance_double(
          Net::HTTPBadRequest,
          code: "400",
          message: "Bad Request",
          body: "not valid json"
        )
        allow(error_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
        allow(Net::HTTP).to receive(:get_response).and_return(error_response)

        result = tool.execute(arguments: { query: "test" })

        expect(result[:error]).to include("HTTP 400: Bad Request")
        expect(result[:results]).to eq([])
      end
    end

    context "with JSON parsing errors" do
      before do
        setup_valid_credentials
      end

      it "handles JSON::ParserError from successful response" do
        success_response = instance_double(Net::HTTPOK, body: "invalid json")
        allow(success_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(success_response).to receive(:is_a?).with(Hash).and_return(false)
        allow(Net::HTTP).to receive(:get_response).and_return(success_response)

        result = tool.execute(arguments: { query: "test" })

        expect(result[:error]).to include("Failed to parse API response")
        expect(result[:results]).to eq([])
      end
    end

    context "with StandardError during execution" do
      before do
        setup_valid_credentials
      end

      it "handles general errors" do
        allow(Net::HTTP).to receive(:get_response).and_raise(StandardError.new("Network timeout"))

        result = tool.execute(arguments: { query: "test" })

        expect(result[:error]).to include("Search failed: Network timeout")
        expect(result[:results]).to eq([])
      end
    end

    context "with empty search results" do
      before do
        setup_valid_credentials
        setup_empty_results_response
      end

      it "returns empty results array" do
        result = tool.execute(arguments: { query: "nonexistent query" })

        expect(result[:results]).to eq([])
        expect(result[:count]).to eq(0)
      end
    end
  end

  private

  def setup_valid_credentials
    allow(File).to receive(:exist?).with(credentials_path).and_return(true)
    allow(File).to receive(:readable?).with(credentials_path).and_return(true)
    allow(File).to receive(:readlines).with(credentials_path).and_return(["#{api_key}\n", "#{cse_id}\n"])
  end

  def setup_successful_http_response
    response_body = {
      "searchInformation" => { "formattedTotalResults" => "1,234,567" },
      "items" => [
        {
          "title" => "Ruby Testing Guide",
          "link" => "https://example.com/1",
          "snippet" => "A comprehensive guide to testing in Ruby"
        },
        {
          "title" => "RSpec Best Practices",
          "link" => "https://example.com/2",
          "snippet" => "Learn the best practices for RSpec testing"
        }
      ]
    }.to_json

    success_response = instance_double(Net::HTTPOK, body: response_body)
    allow(success_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    allow(success_response).to receive(:is_a?).with(Hash).and_return(false)
    allow(Net::HTTP).to receive(:get_response).and_return(success_response)
  end

  def setup_successful_response
    response_body = { "items" => [], "searchInformation" => {} }.to_json
    success_response = instance_double(Net::HTTPOK, body: response_body)
    allow(success_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    allow(success_response).to receive(:is_a?).with(Hash).and_return(false)
    success_response
  end

  def setup_empty_results_response
    response_body = {
      "searchInformation" => { "formattedTotalResults" => "0" },
      "items" => []
    }.to_json

    success_response = instance_double(Net::HTTPOK, body: response_body)
    allow(success_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    allow(success_response).to receive(:is_a?).with(Hash).and_return(false)
    allow(Net::HTTP).to receive(:get_response).and_return(success_response)
  end
end
