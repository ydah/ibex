# frozen_string_literal: true

require_relative "../test_helper"
require "open3"
require "rbconfig"
require "tmpdir"

class LazyRipperLoadingTest < Minitest::Test
  GENERATE = <<~'RUBY'
    require "stringio"
    require "ibex/cli"

    status = Ibex::CLI.start(
      [*ARGV.drop(2), "--output-file=#{ARGV.fetch(1)}", ARGV.fetch(0)],
      stdout: StringIO.new,
      stderr: StringIO.new
    )
    loaded = $LOADED_FEATURES.any? { |path| File.basename(path) == "ripper.rb" }
    puts "#{status}:#{loaded}"
  RUBY

  def test_ordinary_generation_does_not_load_ripper
    source = <<~GRAMMAR
      class OrdinaryParser
      rule
      start: TOKEN { val[0] }
      end
    GRAMMAR

    assert_equal "0:false\n", generate(source)
  end

  def test_indexed_expression_generation_does_not_load_ripper
    source = <<~GRAMMAR
      class IndexedParser
      rule
      start: TOKEN { result = val[0].to_s }
      end
    GRAMMAR

    assert_equal "0:false\n", generate(source)
  end

  def test_semantic_location_generation_loads_ripper
    source = <<~GRAMMAR
      class LocationParser
      rule
      start: TOKEN { [val[0], @1, @$] }
      end
    GRAMMAR

    assert_equal "0:true\n", generate(source)
  end

  def test_heredoc_generation_loads_ripper_when_columns_must_be_preserved
    source = <<~GRAMMAR
      class HeredocParser
      rule
      start: TOKEN {
        value = <<~TEXT
          token
        TEXT
        value
      }
      end
    GRAMMAR

    assert_equal "0:true\n", generate(source, "--no-line-convert")
  end

  private

  def generate(source, *options)
    Dir.mktmpdir("ibex-lazy-ripper") do |directory|
      grammar = File.join(directory, "grammar.y")
      output = File.join(directory, "parser.rb")
      File.write(grammar, source)
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, "-I#{File.expand_path('../../lib', __dir__)}", "-e", GENERATE,
        grammar, output, *options
      )
      assert status.success?, stderr
      assert File.file?(output)
      stdout
    end
  end
end
