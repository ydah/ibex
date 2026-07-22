# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tool/type_stats"
require "tmpdir"

class TypeStatsTest < Minitest::Test
  STATS = <<~OUTPUT
    # Calculating stats:

    Target,File,Status,Typed calls,Untyped calls,All calls,Typed %
    library,lib/one.rb,success,10,2,12,83
    library,lib/two.rb,success,5,3,8,63
  OUTPUT

  def test_renders_aggregate_steep_and_signature_counts
    Dir.mktmpdir("ibex-type-stats") do |directory|
      File.write(File.join(directory, "one.rbs"), "class One\n  def value: () -> untyped\nend\n")
      File.write(File.join(directory, "two.rbs"), "class Two\n  def call: (untyped) -> untyped\nend\n")
      File.write(File.join(directory, "typed.rbs"), "class Typed\nend\n")

      markdown = Ibex::Tooling::TypeStats.new(stats_output: STATS, signature_root: directory).markdown

      assert_equal "The current whole-library `steep stats` result is 15 typed calls and 5 untyped calls out " \
                   "of 20 (75.0% typed).\nThe generated signature tree contains 3 explicit `untyped` occurrences " \
                   "across 2 files.", markdown
    end
  end

  def test_replaces_only_the_generated_readme_section
    Dir.mktmpdir("ibex-empty-signatures") do |directory|
      stats = Ibex::Tooling::TypeStats.new(stats_output: STATS, signature_root: directory)
      readme = <<~MARKDOWN
        before
        <!-- type-stats:start -->
        stale
        <!-- type-stats:end -->
        after
      MARKDOWN

      updated = stats.update_readme(readme)

      assert_includes updated, "before\n<!-- type-stats:start -->\nThe current whole-library"
      assert_includes updated, "across 0 files.\n<!-- type-stats:end -->\nafter\n"
      assert stats.current?(updated)
      refute stats.current?(readme)
    end
  end

  def test_rejects_missing_markers_empty_results_and_inconsistent_totals
    Dir.mktmpdir("ibex-empty-signatures") do |directory|
      stats = Ibex::Tooling::TypeStats.new(stats_output: STATS, signature_root: directory)
      error = assert_raises(ArgumentError) { stats.update_readme("no generated section\n") }
      assert_match(/type stats markers/, error.message)

      error = assert_raises(ArgumentError) do
        header = "Target,File,Status,Typed calls,Untyped calls,All calls,Typed %\n"
        Ibex::Tooling::TypeStats.new(stats_output: header, signature_root: directory).markdown
      end
      assert_match(/no library rows/, error.message)

      inconsistent = STATS.sub(",12,83", ",13,83")
      error = assert_raises(ArgumentError) do
        Ibex::Tooling::TypeStats.new(stats_output: inconsistent, signature_root: directory).markdown
      end
      assert_match(/totals are inconsistent/, error.message)
    end
  end
end
