# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::Tools::FileGrep::OutputParser do
  let(:parser) { described_class.new }

  describe "#parse_output" do
    context "with files_with_matches mode" do
      it "parses file paths from output" do
        stdout = "file1.rb\nfile2.rb\nfile3.rb\n"
        result = parser.parse_output(stdout, "files_with_matches", 100)

        expect(result[:files]).to eq(["file1.rb", "file2.rb", "file3.rb"])
        expect(result[:count]).to eq(3)
      end

      it "respects max_results limit" do
        stdout = "file1.rb\nfile2.rb\nfile3.rb\n"
        result = parser.parse_output(stdout, "files_with_matches", 2)

        expect(result[:files]).to eq(["file1.rb", "file2.rb"])
        expect(result[:count]).to eq(2)
      end

      it "handles empty output" do
        result = parser.parse_output("", "files_with_matches", 100)

        expect(result[:files]).to eq([])
        expect(result[:count]).to eq(0)
      end
    end

    context "with count mode" do
      it "parses count results" do
        stdout = "file1.rb:5\nfile2.rb:3\n"
        result = parser.parse_output(stdout, "count", 100)

        expect(result[:files]).to eq([
                                       { file: "file1.rb", count: 5 },
                                       { file: "file2.rb", count: 3 }
                                     ])
        expect(result[:total_files]).to eq(2)
        expect(result[:total_matches]).to eq(8)
      end

      it "respects max_results limit" do
        stdout = "file1.rb:5\nfile2.rb:3\nfile3.rb:2\n"
        result = parser.parse_output(stdout, "count", 2)

        expect(result[:files].length).to eq(2)
        expect(result[:total_files]).to eq(2)
      end

      it "handles malformed lines" do
        stdout = "file1.rb:5\ninvalid-line\nfile2.rb:3\n"
        result = parser.parse_output(stdout, "count", 100)

        expect(result[:files].length).to eq(2)
        expect(result[:total_matches]).to eq(8)
      end

      it "handles empty output" do
        result = parser.parse_output("", "count", 100)

        expect(result[:files]).to eq([])
        expect(result[:total_files]).to eq(0)
        expect(result[:total_matches]).to eq(0)
      end
    end

    context "with content mode" do
      it "parses JSON match results" do
        json_line = {
          type: "match",
          data: {
            path: { text: "file1.rb" },
            line_number: 42,
            lines: { text: "  def execute\n" },
            submatches: [{ match: { text: "execute" } }]
          }
        }.to_json

        result = parser.parse_output("#{json_line}\n", "content", 100)

        expect(result[:matches].length).to eq(1)
        expect(result[:matches][0]).to eq({
                                            file: "file1.rb",
                                            line_number: 42,
                                            line: "  def execute",
                                            match_text: "execute"
                                          })
        expect(result[:count]).to eq(1)
        expect(result[:truncated]).to be false
      end

      it "respects max_results limit" do
        json1 = { type: "match", data: {
          path: { text: "f1.rb" }, line_number: 1,
          lines: { text: "line1\n" }, submatches: []
        } }.to_json
        json2 = { type: "match", data: {
          path: { text: "f2.rb" }, line_number: 2,
          lines: { text: "line2\n" }, submatches: []
        } }.to_json

        result = parser.parse_output("#{json1}\n#{json2}\n", "content", 1)

        expect(result[:matches].length).to eq(1)
        expect(result[:truncated]).to be true
      end

      it "skips context lines" do
        match_json = {
          type: "match",
          data: {
            path: { text: "f.rb" }, line_number: 1,
            lines: { text: "match\n" }, submatches: []
          }
        }.to_json
        context_json = { type: "context", data: {} }.to_json

        result = parser.parse_output("#{match_json}\n#{context_json}\n", "content", 100)

        expect(result[:matches].length).to eq(1)
      end

      it "handles JSON parse errors" do
        invalid_json = "not a json line\n"
        result = parser.parse_output(invalid_json, "content", 100)

        expect(result[:matches]).to eq([])
        expect(result[:count]).to eq(0)
      end

      it "handles missing submatches" do
        json_line = {
          type: "match",
          data: {
            path: { text: "file.rb" },
            line_number: 1,
            lines: { text: "text\n" },
            submatches: nil
          }
        }.to_json

        result = parser.parse_output("#{json_line}\n", "content", 100)

        expect(result[:matches][0][:match_text]).to be_nil
      end

      it "handles empty output" do
        result = parser.parse_output("", "content", 100)

        expect(result[:matches]).to eq([])
        expect(result[:count]).to eq(0)
        expect(result[:truncated]).to be false
      end
    end
  end
end
