# frozen_string_literal: true

require "json"

module Nu
  module Agent
    module Tools
      class FileGrep
        # Parses ripgrep output in different formats
        class OutputParser
          def parse_output(stdout, output_mode, max_results)
            case output_mode
            when "files_with_matches"
              parse_files_with_matches(stdout, max_results)
            when "count"
              parse_count(stdout, max_results)
            when "content"
              parse_content(stdout, max_results)
            end
          end

          private

          def parse_files_with_matches(stdout, max_results)
            files = stdout.split("\n").take(max_results)
            {
              files: files,
              count: files.length
            }
          end

          def parse_count(stdout, max_results)
            results = []
            stdout.split("\n").take(max_results).each do |line|
              # Format: "path/to/file:count"
              next unless line =~ /^(.+):(\d+)$/

              results << {
                file: ::Regexp.last_match(1),
                count: ::Regexp.last_match(2).to_i
              }
            end

            {
              files: results,
              total_files: results.length,
              total_matches: results.sum { |r| r[:count] }
            }
          end

          def parse_content(stdout, max_results)
            matches = []

            stdout.each_line do |line|
              data = JSON.parse(line)

              case data["type"]
              when "match"
                match_data = data["data"]

                matches << {
                  file: match_data["path"]["text"],
                  line_number: match_data["line_number"],
                  line: match_data["lines"]["text"].chomp,
                  match_text: match_data["submatches"]&.first&.dig("match", "text")
                }

                break if matches.length >= max_results

              when "context"
                # Context lines could be added to the previous match if needed
                # For now, we'll skip them as ripgrep --json provides them separately
              end
            rescue JSON::ParserError
              # Skip non-JSON lines
            end

            {
              matches: matches,
              count: matches.length,
              truncated: matches.length >= max_results
            }
          end
        end
      end
    end
  end
end
