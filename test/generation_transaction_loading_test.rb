# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"

class GenerationTransactionLoadingTest < Minitest::Test
  FEATURES = %w[
    ibex/generation_transaction
    ibex/cli/generation_artifacts
    ibex/cli/watch
  ].freeze

  def test_each_transaction_boundary_loads_in_a_fresh_core_ruby_process
    FEATURES.each do |feature|
      stdout, stderr, process = Open3.capture3(
        RbConfig.ruby, "--disable-gems", "-I#{File.expand_path('../lib', __dir__)}",
        "-e", 'require ARGV.fetch(0); puts "loaded"', feature
      )

      assert process.success?, "#{feature} failed to load:\n#{stderr}"
      assert_equal "loaded\n", stdout
      assert_empty stderr
    end
  end
end
