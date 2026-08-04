# frozen_string_literal: true

module Ibex
  module Quality
    # Binds public comparative wording to complete records in docs/claims.yml.
    class ClaimPublications
      AGGREGATE_SCORE = /\b(?:aggregate|overall)\s+(?:score|ranking)\b|総合点/i
      STRONG_WORDING = /\b(?:faster|slower|smaller|larger|better|best|outperform\w*|trail\w*|parity|fewer)\b/i
      TOOL_WORDING = /\b(?:Racc|Lrama|Bison|Menhir|Tree-sitter|ANTLR)\b/i

      def initialize(root:, claims:, readme:)
        @root = root
        @claims = claims
        @readme = readme
      end

      def verify!
        @claims.group_by { |claim| claim.dig("publication", "path") }.each do |path, claims|
          source = publication_source(path)
          blocks = claim_blocks(source, path)
          expected = claims.map { |claim| claim.fetch("id") }.sort
          raise "#{path}: claim markers do not match registry" unless blocks.keys.sort == expected

          verify_unmarked_strong_wording(source, blocks, path) if path == @readme
        end
      end

      private

      def publication_source(path)
        absolute = File.expand_path(path, @root)
        raise "publication path escapes the repository" unless absolute.start_with?("#{@root}/")
        raise "missing claim publication #{path}" unless File.file?(absolute)

        source = File.binread(absolute)
        raise "#{path}: aggregate scores and rankings are forbidden" if source.match?(AGGREGATE_SCORE)

        source
      end

      def claim_blocks(source, path)
        blocks = {}
        active = nil
        source.lines.each_with_index do |line, index|
          match = line.match(/\A(?:> )?<!-- comparative-claim:([a-z0-9-]+):(start|end) -->\s*\z/)
          if match&.[](2) == "start"
            raise "#{path}: nested claim marker at line #{index + 1}" if active

            active = [match[1], index, []]
          elsif match
            active = close_block!(blocks, active, match[1], index, path)
          elsif active
            active[2] << line
          end
        end
        raise "#{path}: unclosed claim marker #{active[0]}" if active

        blocks
      end

      def close_block!(blocks, active, id, index, path)
        raise "#{path}: unmatched claim marker at line #{index + 1}" unless active && active[0] == id
        raise "#{path}: duplicate claim marker #{id}" if blocks.key?(id)

        body = active[2].join
        raise "#{path}: claim #{id} must not be empty" if body.strip.empty?

        blocks[id] = { range: active[1]..index, body: body }
        nil
      end

      def verify_unmarked_strong_wording(source, blocks, path)
        claimed = blocks.values.flat_map { |block| block.fetch(:range).to_a }
        visible = source.lines.each_with_index.reject { |_line, index| claimed.include?(index) }.map(&:first).join
        visible.split(/\n\s*\n/).each do |paragraph|
          next unless paragraph.match?(TOOL_WORDING) && paragraph.match?(STRONG_WORDING)

          raise "#{path}: comparative strong wording must be enclosed by a claim marker: #{paragraph.lines.first.strip}"
        end
      end
    end
  end
end
