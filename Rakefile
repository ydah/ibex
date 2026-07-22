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
    require_relative "lib/ibex"
    require_relative "lib/ibex/frontend/regenerator"

    output = File.expand_path("lib/ibex/frontend/generated_parser.rb", __dir__)
    File.write(output, Ibex::Frontend::Regenerator.generate)
  end
end

task default: %i[test lint]
