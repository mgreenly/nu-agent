# frozen_string_literal: true

module Nu
  module Agent
    class ManIndexer
      def initialize(history:, embeddings_client:, application: nil)
        @history = history
        @embeddings = embeddings_client
        @application = application
      end

      # Discover all available man pages on the system
      def all_man_pages
        output = `man -k . 2>/dev/null`
        return [] if output.nil? || output.empty?

        man_pages = []
        output.each_line do |line|
          # Parse: "grep (1) - print lines matching a pattern"
          next unless line =~ /^(\S+)\s+\((\d+)\)\s+-\s+(.*)$/

          name = ::Regexp.last_match(1)
          section = ::Regexp.last_match(2)
          ::Regexp.last_match(3).strip

          # Source format: "name.section"
          source = "#{name}.#{section}"
          man_pages << source
        end

        man_pages.uniq.sort
      end

      # Extract NAME, SYNOPSIS, and DESCRIPTION sections from a man page
      # Returns a formatted document combining these sections
      def extract_description(source)
        name, section = parse_source_name(source)
        return nil unless name && section

        output = fetch_man_page(name, section, source)
        return nil unless output

        sections = extract_sections(output, %w[NAME SYNOPSIS DESCRIPTION])
        document = build_document_from_sections(sections, source)
        return nil unless document

        truncate_if_needed(document, source)
      rescue StandardError => e
        log_error(source, e)
        nil
      end

      def parse_source_name(source)
        name, section = source.split(".")
        unless name && section
          @application&.output_line("[Man Indexer] Skipping #{source}: invalid source format", type: :debug)
        end
        [name, section]
      end

      def fetch_man_page(name, section, source)
        output = `man #{section} #{name} 2>/dev/null`
        if output.nil? || output.empty?
          @application&.output_line("[Man Indexer] Skipping #{source}: man page not accessible", type: :debug)
          return nil
        end
        output
      end

      def build_document_from_sections(sections, source)
        doc_parts = []
        doc_parts << "NAME\n#{sections['NAME']}" if sections["NAME"]
        doc_parts << "SYNOPSIS\n#{sections['SYNOPSIS']}" if sections["SYNOPSIS"]
        doc_parts << "DESCRIPTION\n#{sections['DESCRIPTION']}" if sections["DESCRIPTION"]

        if doc_parts.empty?
          @application&.output_line(
            "[Man Indexer] Skipping #{source}: no NAME/SYNOPSIS/DESCRIPTION sections found",
            type: :debug
          )
          return nil
        end

        doc_parts.join("\n\n")
      end

      def truncate_if_needed(document, source)
        return document if document.length <= 32_000

        @application&.output_line(
          "[Man Indexer] Truncating #{source}: content too long (#{document.length} chars)",
          type: :debug
        )
        document[0, 32_000]
      end

      def log_error(source, error)
        @application&.output_line(
          "[Man Indexer] Error processing #{source}: #{error.class}: #{error.message}",
          type: :debug
        )
      end

      private

      # Extract specific sections from man page content
      # Sections are identified by all-caps headers at the start of a line
      def extract_sections(content, section_names)
        lines = content.lines
        sections = {}
        current_section = nil
        current_lines = []

        lines.each do |line|
          # Check if this line is a section header (all caps, possibly with whitespace)
          if line =~ /^\s*([A-Z][A-Z\s]+)\s*$/
            section_name = line.strip

            # Save previous section if it was one we're looking for
            if current_section && section_names.include?(current_section)
              sections[current_section] = current_lines.join.strip
            end

            # Start new section
            current_section = section_name
            current_lines = []
          elsif current_section
            # Accumulate lines for current section
            current_lines << line
          end
        end

        # Don't forget the last section
        if current_section && section_names.include?(current_section)
          sections[current_section] = current_lines.join.strip
        end

        sections
      end

      # Check if a man page exists and is accessible
      def man_page_exists?(source)
        name, section = source.split(".")
        return false unless name && section

        system("man #{section} #{name} > /dev/null 2>&1")
      end
    end
  end
end
