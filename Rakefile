# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

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

namespace :quality do
  desc "Run the bounded mutation suite for compact parser tables"
  task :mutation do
    sh(
      { "BUNDLE_GEMFILE" => "gemfiles/mutation.Gemfile" },
      "bundle", "exec", "mutant", "run"
    )
  end

  desc "Verify the JSON error UX and repair evidence"
  task :error_ux do
    sh "bundle", "exec", "ruby", "tool/error_ux_snapshot.rb"
  end
end

namespace :grammar do
  desc "Run source examples declared in gallery grammars"
  task :test do
    Dir.glob("examples/*.y").each do |path|
      sh "bundle", "exec", "ruby", "-Ilib", "exe/ibex", "test", path
    end
  end
end

task default: %i[test lint]
