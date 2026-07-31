# frozen_string_literal: true

require "bundler/gem_helper"
require "rake/testtask"

Bundler::GemHelper.install_tasks(name: "ibex")

Rake::TestTask.new(:test) do |task|
  task.libs << "test"
  task.pattern = "test/**/*_test.rb"
  task.warning = true
end

desc "Run RuboCop"
task :lint do
  sh "bundle", "exec", "rubocop"
end

namespace :frontend do
  desc "Regenerate the self-hosted grammar parser"
  task :generate do
    require_relative "lib/ibex/frontend/regenerator"

    output = File.expand_path("lib/ibex/frontend/generated_parser.rb", __dir__)
    File.write(output, Ibex::Frontend::Regenerator.generate)
  end

  desc "Verify that the self-hosted grammar parser is current"
  task :check do
    require_relative "lib/ibex/frontend/regenerator"

    output = File.expand_path("lib/ibex/frontend/generated_parser.rb", __dir__)
    abort "self-hosted grammar parser is stale; run bundle exec rake frontend:generate" unless
      File.binread(output) == Ibex::Frontend::Regenerator.generate
  end
end

namespace :runtime do
  desc "Build the standalone runtime gem"
  task :build do
    sh "gem", "build", "ibex-runtime.gemspec"
  end
end

namespace :quality do
  desc "Run the bounded mutation suite for compact parser tables"
  task :mutation do
    sh "bundle", "exec", "mutant", "run"
  end

  desc "Verify the JSON error UX and repair evidence"
  task :error_ux do
    sh "bundle", "exec", "ruby", "tool/error_ux_snapshot.rb"
  end
end

# rubocop:disable Metrics/BlockLength -- quality gates are intentionally discoverable under one namespace.
namespace :test do
  desc "Run the representative invariant matrix"
  task :matrix do
    ruby "-Itest", "-r./test/support/matrix_runner", "-e",
         "Ibex::TestSupport::MatrixRunner.new.run"
  end

  namespace :matrix do
    desc "Run the complete invariant matrix"
    task :full do
      ruby "-Itest", "-r./test/support/matrix_runner", "-e",
           "Ibex::TestSupport::MatrixRunner.new.run(full: true)"
    end
  end

  desc "Verify feature-off generated source against reviewed golden bytes"
  task :zero_cost do
    ruby "-Ilib", "-r./tool/quality/golden", "-e", "Ibex::Quality::Golden.new.verify!"
  end

  desc "Generate twice under distinct locale, timezone, and RUBYOPT inputs"
  task :reproducible do
    ruby "-Ilib", "-r./tool/quality/golden", "-e", "Ibex::Quality::Golden.new.reproducible!"
  end

  desc "Run the compatible-mode black-box suite"
  task :compat do
    ruby "-Itest", "test/compat/black_box_test.rb"
  end

  desc "Run closed-schema round-trip and rejection tests"
  task :ir_schema do
    ruby "-Itest", "test/ir/json_schema_test.rb"
    ruby "-Itest", "test/ir/validator_test.rb"
    ruby "-Itest", "test/ir/golden_fixture_test.rb"
  end

  desc "Run bounded hostile-input tests"
  task :adversarial do
    ruby "-Itest", "test/adversarial/limits_test.rb"
  end

  desc "Prove analysis paths do not execute grammar semantic actions"
  task :no_exec do
    ruby "-Itest", "test/analysis_no_exec_test.rb"
  end

  desc "Require synchronized English/Japanese coverage for every Stable contract"
  task :docs_coverage do
    ruby "-Ilib", "-r./tool/quality/docs_coverage", "-e", "Ibex::Quality::DocsCoverage.new.verify!"
  end
end
# rubocop:enable Metrics/BlockLength

namespace :golden do
  desc "Create the initial generated-source golden baseline"
  task :record do
    ruby "-Ilib", "-r./tool/quality/golden", "-e", "Ibex::Quality::Golden.new.record!"
  end

  desc "Update generated-source golden bytes and their digest index"
  task :update do
    ruby "-Ilib", "-r./tool/quality/golden", "-e", "Ibex::Quality::Golden.new.update!"
  end
end

namespace :gallery do
  desc "Build every algorithm/table combination and execute gallery corpora"
  task :build do
    ruby "-Ilib", "-r./tool/quality/gallery", "-e", "Ibex::Quality::Gallery.new.build!"
  end

  desc "Check committed gallery conflict and state counts"
  task :conflicts do
    ruby "-Ilib", "-r./tool/quality/gallery", "-e", "Ibex::Quality::Gallery.new.conflicts!"
  end
end

namespace :fuzz do
  desc "Run the fixed-seed short gallery differential suite"
  task :short do
    ruby "-Ilib", "-r./tool/quality/fuzz", "-e", "Ibex::Quality::Fuzz.new(count: 100).run"
  end

  desc "Run 100,000 fixed-seed generated sentences per gallery grammar"
  task :long do
    ruby "-Ilib", "-r./tool/quality/fuzz", "-e", "Ibex::Quality::Fuzz.new(count: 100_000).run"
  end

  desc "Verify ten reachable parser-table faults are detected"
  task :injection do
    ruby "-Itest", "test/fuzz_test.rb", "--name=/ten_reachable/"
  end
end

desc "Verify every gallery automaton with the default independent checks"
task :verify do
  ruby "-Ilib", "-r./tool/quality/verify", "-e", "Ibex::Quality::Verify.new.run"
end

namespace :verify do
  desc "Include independent completeness and table-bisimulation checks"
  task :strict do
    ruby "-Ilib", "-r./tool/quality/verify", "-e", "Ibex::Quality::Verify.new.run(strict: true)"
  end

  desc "Prove that all twenty Automaton IR fault types are detected"
  task :injection do
    ruby "-Itest", "test/verify/verifier_test.rb", "--name=/twenty_structurally_valid/"
  end
end

namespace :equiv do
  desc "Run bounded equivalence acceptance, counterexample, tree-map, and budget cases"
  task :test do
    ruby "-Itest", "test/equiv_test.rb"
    ruby "-Itest", "test/cli_equiv_test.rb"
  end
end

namespace :analysis do
  desc "Run deterministic diff and metrics contracts"
  task :test do
    ruby "-Itest", "test/metrics_diff_test.rb"
    ruby "-Itest", "test/cli_metrics_diff_test.rb"
  end
end

namespace :fix do
  desc "Run conflict-repair safety contracts and the measured twenty-case baseline"
  task :test do
    ruby "-Itest", "test/fix_test.rb"
    ruby "-Itest", "test/cli_fix_test.rb"
    ruby "-Ilib", "-r./tool/quality/fix", "-e", "Ibex::Quality::Fix.new.verify!"
  end
end

namespace :i18n do
  desc "Verify built-in diagnostic catalog parity and language selection"
  task :coverage do
    ruby "-Itest", "test/messages_test.rb"
  end
end

namespace :bison do
  desc "Run synthetic Bison import, schema, CLI, and safety contracts"
  task :test do
    ruby "-Itest", "test/bison_import_test.rb"
    ruby "-Itest", "test/cli_bison_import_test.rb"
  end

  desc "Download pinned external grammars and verify aggregate import evidence"
  task :external do
    ruby "-Ilib", "-r./tool/quality/bison_external", "-e", "Ibex::Quality::BisonExternal.new.run!"
  end
end

namespace :deps do
  desc "Verify the standalone runtime has no runtime dependencies"
  task :zero do
    specification = Gem::Specification.load(File.expand_path("ibex-runtime.gemspec", __dir__))
    abort "ibex-runtime must have zero runtime dependencies" unless specification.runtime_dependencies.empty?
  end
end

namespace :network do
  desc "Verify packaged runtime sources do not load networking libraries"
  task :zero do
    forbidden = %r{require\s+["'](?:net/http|open-uri|socket)["']}
    paths = Dir.glob("lib/ibex/runtime{.rb,/**/*.rb}")
    matches = paths.select { |path| File.binread(path).match?(forbidden) }
    abort "runtime networking dependency found: #{matches.join(', ')}" unless matches.empty?
  end
end

namespace :grammar do
  desc "Run source examples and require complete production coverage in gallery grammars"
  task :test do
    Dir.glob("examples/*.y").each do |path|
      sh "bundle", "exec", "ruby", "-Ilib", "exe/ibex", "test", "--mode=extended", "--coverage=100", path
    end
  end
end

task default: %i[test lint]
