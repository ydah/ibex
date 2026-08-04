# frozen_string_literal: true

require "digest"

module Ibex
  module Quality
    # Binds comparative wording or pending evidence to complete registry records.
    class ClaimPublications
      STRONG_WORDING = /(?:
        \b(?:faster|fastest|slower|slowest|better|best|worse|worst|beats?|outperforms?|superior|inferior|
        trail(?:s|ed)?|parity|fewer|smaller|larger)\b |
        より(?:速い|高速|遅い|優れ(?:る|ている)?|劣る|小さい|大きい) | 最速 | 最遅 | 最高 | 最低 |
        上回る | 下回る | 勝る | 劣る
      )/ix
      POLICY = "docs/comparison-policy.md"

      def initialize(root:, claims:, readme:, aliases:)
        @root = root
        @claims = claims
        @readme = readme
        @tool_wording = alias_pattern(aliases)
      end

      def self.body_sha256(body)
        lines = body.gsub("\r\n", "\n").lines(chomp: true).map(&:rstrip)
        Digest::SHA256.hexdigest("#{lines.join("\n")}\n")
      end

      def verify!
        publication_paths.each do |path|
          source = publication_source(path)
          blocks = marker_blocks(source, path)
          expected = expected_markers(path)
          actual = blocks.values.map { |block| [block.fetch(:kind), block.fetch(:id)] }.sort
          raise "#{path}: comparative markers do not match registry" unless actual == expected

          verify_blocks!(path, blocks)
          verify_unmarked_readme_strength!(source, blocks, path) if path == @readme
        end
      end

      private

      def alias_pattern(aliases)
        alternatives = aliases.values.flatten.map { |name| Regexp.escape(name) }.join("|")
        /(?<![A-Za-z0-9_])(?:#{alternatives})(?![A-Za-z0-9_])/i
      end

      def publication_paths
        bound = @claims.map { |claim| claim.dig("binding", "path") }
        evidence = @claims.flat_map { |claim| claim.fetch("evidence") }
                          .filter_map { |entry| entry["path"] if entry["path"].end_with?(".md") }
        (bound + evidence + [@readme, POLICY]).uniq.sort
      end

      def publication_source(path)
        absolute = File.expand_path(path, @root)
        raise "publication path escapes the repository" unless absolute.start_with?("#{@root}/")
        raise "missing claim publication #{path}" unless File.file?(absolute)

        source = File.read(absolute, encoding: Encoding::UTF_8)
        ComparativeWording.verify!(source, path: path, policy: path == POLICY)
        source
      end

      def expected_markers(path)
        @claims.filter_map do |claim|
          binding = claim.fetch("binding")
          [binding.fetch("kind"), claim.fetch("id")] if binding.fetch("path") == path
        end.sort
      end

      def marker_blocks(source, path)
        blocks = {}
        active = nil
        source.lines.each_with_index do |line, index|
          match = marker_match(line)
          if match&.[](3) == "start"
            raise "#{path}: nested comparative marker at line #{index + 1}" if active

            active = [match[1], match[2], index, []]
          elsif match
            active = close_block!(blocks, active, match, index, path)
          elsif active
            active[3] << line
          end
        end
        raise "#{path}: unclosed comparative marker #{active[1]}" if active

        blocks
      end

      def marker_match(line)
        line.match(/\A(?:> )?<!-- comparative-(claim|evidence):([a-z0-9-]+):(start|end) -->\s*\z/)
      end

      def close_block!(blocks, active, match, index, path)
        kind, id = match.captures.first(2)
        raise "#{path}: unmatched comparative marker at line #{index + 1}" unless
          active && active.values_at(0, 1) == [kind, id]

        key = [kind, id]
        raise "#{path}: duplicate comparative marker #{kind}:#{id}" if blocks.key?(key)

        body = active[3].join
        raise "#{path}: comparative marker #{kind}:#{id} must not be empty" if body.strip.empty?

        blocks[key] = { kind: kind, id: id, range: active[2]..index, body: body }
        nil
      end

      def verify_blocks!(path, blocks)
        blocks.each_value do |block|
          claim = @claims.find { |entry| entry.fetch("id") == block.fetch(:id) }
          verify_body_digest!(path, claim, block)
          wording = normalize(claim.fetch("wording"))
          body = normalize(block.fetch(:body))
          unless body.include?(wording)
            raise "#{path}: marker #{block.fetch(:id)} must contain the exact registry wording"
          end

          missing = claim.dig("binding", "required_text").reject { |text| block.fetch(:body).include?(text) }
          unless missing.empty?
            raise "#{path}: marker #{block.fetch(:id)} is missing bound evidence: #{missing.join(', ')}"
          end

          verify_additional_strength!(path, claim, block)
        end
      end

      def verify_body_digest!(path, claim, block)
        expected = claim.dig("binding", "body_sha256")
        actual = self.class.body_sha256(block.fetch(:body))
        return if actual == expected

        raise "#{path}: marker #{block.fetch(:id)} body digest mismatch; expected #{expected}, actual #{actual}"
      end

      def verify_additional_strength!(path, claim, block)
        wording = normalize(claim.fetch("wording"))
        units = strength_units(block.fetch(:body), wording)
        allowed = claim.dig("binding", "allowed_strength").map { |text| normalize(text) }
        unexpected = units - allowed
        missing = allowed - units
        unless unexpected.empty?
          raise "#{path}: marker #{block.fetch(:id)} has unregistered comparative strength: #{unexpected.first}"
        end
        return if missing.empty?

        raise "#{path}: marker #{block.fetch(:id)} is missing registered comparative strength: #{missing.first}"
      end

      def strength_units(body, wording)
        units = body.split(/\n\s*\n/).flat_map do |paragraph|
          remainder = normalize(paragraph)
          remainder = remainder.delete_prefix(wording).strip if remainder.start_with?(wording)
          remainder.split(/(?<=[.!?])\s+/)
        end
        units.grep(STRONG_WORDING)
      end

      def verify_unmarked_readme_strength!(source, blocks, path)
        claimed = blocks.values.select { |block| block.fetch(:kind) == "claim" }
                               .flat_map { |block| block.fetch(:range).to_a }
        visible = source.lines.each_with_index.reject { |_line, index| claimed.include?(index) }.map(&:first).join
        visible.split(/\n\s*\n/).each do |paragraph|
          next unless paragraph.match?(@tool_wording) && paragraph.match?(STRONG_WORDING)

          raise "#{path}: comparative strong wording must be enclosed by a measured claim marker"
        end
      end

      def normalize(value)
        value.lines.map { |line| line.sub(/\A>\s?/, "") }.join.gsub(/\s+/, " ").strip
      end
    end
  end
end
