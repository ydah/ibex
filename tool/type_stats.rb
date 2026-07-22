# frozen_string_literal: true

require "open3"

module Ibex
  module Tooling
    # Aggregates Steep output and keeps the generated README summary current.
    class TypeStats
      START_MARKER = "<!-- type-stats:start -->"
      END_MARKER = "<!-- type-stats:end -->"

      def initialize(stats_output:, signature_root:)
        @stats_output = stats_output
        @signature_root = signature_root
      end

      def markdown
        typed, untyped, total = call_counts
        occurrences, files = signature_counts
        percentage = total.zero? ? 100.0 : (100.0 * typed / total)
        "The current whole-library `steep stats` result is #{number(typed)} typed calls and " \
          "#{number(untyped)} untyped calls out of #{number(total)} (#{format('%.1f', percentage)}% typed)." \
          "\nThe generated signature tree contains #{number(occurrences)} explicit `untyped` occurrences " \
          "across #{number(files)} files."
      end

      def update_readme(readme)
        ensure_markers(readme)
        readme.sub(section_pattern, [START_MARKER, markdown, END_MARKER].join("\n"))
      end

      def current?(readme)
        update_readme(readme) == readme
      end

      private

      def call_counts
        header = @stats_output.lines.index { |line| line.start_with?("Target,File,") }
        raise ArgumentError, "steep stats output has no CSV header" unless header

        columns = @stats_output.lines.fetch(header).strip.split(",")
        rows = @stats_output.lines.drop(header + 1).reject { |line| line.strip.empty? }.map do |line|
          columns.zip(line.strip.split(",", -1)).to_h
        end
        library_rows = rows.select { |row| row["Target"] == "library" }
        raise ArgumentError, "steep stats output has no library rows" if library_rows.empty?

        typed = sum(library_rows, "Typed calls")
        untyped = sum(library_rows, "Untyped calls")
        total = sum(library_rows, "All calls")
        raise ArgumentError, "steep stats call totals are inconsistent" unless typed + untyped == total

        [typed, untyped, total]
      end

      def sum(rows, column)
        rows.sum { |row| Integer(row[column], 10) }
      end

      def signature_counts
        counts = Dir.glob(File.join(@signature_root, "**/*.rbs")).filter_map do |path|
          count = File.read(path).scan(/\buntyped\b/).length
          count if count.positive?
        end
        [counts.sum, counts.length]
      end

      def ensure_markers(readme)
        starts = readme.scan(START_MARKER).length
        ends = readme.scan(END_MARKER).length
        return if starts == 1 && ends == 1 && readme.match?(section_pattern)

        raise ArgumentError, "README must contain exactly one ordered pair of type stats markers"
      end

      def section_pattern
        /#{Regexp.escape(START_MARKER)}\n.*?\n#{Regexp.escape(END_MARKER)}/m
      end

      def number(value)
        value.to_s.reverse.scan(/.{1,3}/).join(",").reverse
      end
    end

    # Command-line boundary for updating or checking the README summary.
    class TypeStatsCommand
      ROOT = File.expand_path("..", __dir__)

      def self.run(arguments)
        operation = arguments.shift
        return usage unless %w[--check --write].include?(operation) && arguments.empty?

        output, status = Open3.capture2e("bundle", "exec", "steep", "stats", chdir: ROOT)
        raise "steep stats failed:\n#{output}" unless status.success?

        readme_path = File.join(ROOT, "README.md")
        stats = TypeStats.new(stats_output: output, signature_root: File.join(ROOT, "sig"))
        readme = File.read(readme_path)
        return check(stats, readme) if operation == "--check"

        File.write(readme_path, stats.update_readme(readme))
        puts stats.markdown
        0
      rescue ArgumentError, RuntimeError => e
        warn e.message
        1
      end

      def self.check(stats, readme)
        return 0 if stats.current?(readme)

        warn "README type statistics are stale; run this command with --write"
        1
      end
      private_class_method :check

      def self.usage
        warn "usage: type_stats.rb --check|--write"
        1
      end
      private_class_method :usage
    end
  end
end

exit Ibex::Tooling::TypeStatsCommand.run(ARGV) if $PROGRAM_NAME == __FILE__
