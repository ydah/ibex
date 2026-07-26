# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "rubocop/rake_task"

Rake::TestTask.new(:test) do |task|
  task.libs << "test"
  task.pattern = "test/**/*_test.rb"
  task.warning = true
end

RuboCop::RakeTask.new(:lint)

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
end

task default: %i[test lint]
