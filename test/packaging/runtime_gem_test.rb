# frozen_string_literal: true

require_relative "../test_helper"
require "fileutils"
require "open3"
require "rbconfig"
require "rubygems/package"
require "tmpdir"

class RuntimeGemPackagingTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  RUNTIME_GEMSPEC = File.join(ROOT, "ibex-runtime.gemspec")
  GENERATOR_GEMSPEC = File.join(ROOT, "ibex.gemspec")
  ISOLATED_ENV = { "BUNDLE_GEMFILE" => nil, "RUBYLIB" => nil, "RUBYOPT" => nil }.freeze
  SOURCE = <<~GRAMMAR
    class RuntimeOnlyParser
    token VALUE
    rule
    start: VALUE { result = val[0] }
    end
  GRAMMAR

  def test_runtime_has_an_independent_version_and_package_boundary
    runtime = Gem::Specification.load(RUNTIME_GEMSPEC)
    generator = Gem::Specification.load(GENERATOR_GEMSPEC)

    assert_equal "ibex-runtime", runtime.name
    assert_equal Ibex::Runtime::VERSION, runtime.version.to_s
    assert_includes runtime.files, "lib/ibex/runtime.rb"
    assert_includes runtime.files, "lib/ibex/runtime/version.rb"
    assert_includes runtime.files, "lib/ibex/tables/compact.rb"
    assert_includes runtime.files, "lib/ibex/tables/compact_actions.rb"
    assert_includes runtime.files, "lib/ibex/tables/compact_productions.rb"
    assert_runtime_signatures(runtime)
    refute_includes runtime.files, "lib/ibex/frontend.rb"
    refute_includes runtime.files, "exe/ibex"

    dependency = generator.runtime_dependencies.find { |entry| entry.name == "ibex-runtime" }
    refute_nil dependency
    assert dependency.requirement.satisfied_by?(runtime.version)
    refute_includes generator.files, "lib/ibex/runtime.rb"
    refute_includes generator.files, "lib/ibex/runtime/parser.rb"
  end

  def assert_runtime_signatures(runtime)
    assert_includes runtime.files, "sig/ibex/runtime/parser.rbs"
    assert_includes runtime.files, "sig/ibex/tables/compact_actions.rbs"
    assert_includes runtime.files, "sig/ibex/tables/compact_productions.rbs"
  end

  def test_runtime_gemspec_builds
    Dir.mktmpdir("ibex-runtime-package") do |directory|
      output = File.join(directory, "ibex-runtime.gem")
      build_gem(RUNTIME_GEMSPEC, output)
    end
  end

  def test_built_generator_runs_with_the_installed_runtime_dependency
    Dir.mktmpdir("ibex-installed-packages") do |directory|
      runtime_gem = build_gem(RUNTIME_GEMSPEC, File.join(directory, "ibex-runtime.gem"))
      generator_gem = build_gem(GENERATOR_GEMSPEC, File.join(directory, "ibex.gem"))
      gem_home = File.join(directory, "gems")
      environment = isolated_gem_environment(gem_home)

      install_gem(runtime_gem, gem_home, environment)
      install_gem(generator_gem, gem_home, environment)
      assert_installed_generator_works(directory, gem_home, environment)
    end
  end

  def test_generator_gem_builds_without_git_metadata
    Dir.mktmpdir("ibex-source-package") do |directory|
      source_root = File.join(directory, "source")
      copy_tracked_source(source_root)
      output = build_gem(
        File.join(source_root, "ibex.gemspec"),
        File.join(directory, "ibex.gem"),
        chdir: source_root
      )
      files = Gem::Package.new(output).spec.files

      %w[exe/ibex lib/ibex.rb lib/ibex/cli.rb schema/lexer-ir-v1.schema.json].each do |path|
        assert_includes files, path
      end
    end
  end

  def test_nonembedded_generated_parser_runs_with_runtime_files_only
    source = generated_parser(embedded: false)
    refute_includes source, 'require "ibex/tables"'

    with_runtime_tree do |directory|
      File.binwrite(File.join(directory, "parser.rb"), source)
      script = runtime_script
      _stdout, stderr, status = Open3.capture3(
        ISOLATED_ENV,
        RbConfig.ruby, "--disable-gems", "-I", File.join(directory, "lib"), "-e", script, chdir: directory
      )

      assert status.success?, stderr
    end
  end

  def test_embedded_generated_parser_remains_dependency_free
    Dir.mktmpdir("ibex-embedded-package") do |directory|
      File.binwrite(File.join(directory, "parser.rb"), generated_parser(embedded: true))
      _stdout, stderr, status = Open3.capture3(
        ISOLATED_ENV, RbConfig.ruby, "--disable-gems", "-e", runtime_script, chdir: directory
      )

      assert status.success?, stderr
    end
  end

  private

  def build_gem(gemspec, output, chdir: ROOT)
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, "-S", "gem", "build", gemspec, "--output", output, chdir: chdir
    )

    assert status.success?, stderr
    assert File.file?(output)
    assert_operator File.size(output), :>, 0
    output
  end

  def install_gem(path, gem_home, environment)
    _stdout, stderr, status = Bundler.with_unbundled_env do
      Open3.capture3(
        environment,
        RbConfig.ruby, "-S", "gem", "install", path,
        "--local", "--no-document", "--install-dir", gem_home
      )
    end
    assert status.success?, stderr
  end

  def isolated_gem_environment(gem_home)
    ISOLATED_ENV.merge("GEM_HOME" => gem_home, "GEM_PATH" => gem_home)
  end

  def assert_installed_generator_works(directory, gem_home, environment)
    executable = File.join(gem_home, "bin", "ibex")
    stdout, stderr, status = Bundler.with_unbundled_env do
      Open3.capture3(environment, executable, "--version", chdir: directory)
    end
    assert status.success?, stderr
    assert_equal "ibex #{Ibex::VERSION}\n", stdout

    grammar = File.join(directory, "grammar.y")
    output = File.join(directory, "parser.rb")
    File.binwrite(grammar, SOURCE)
    _stdout, stderr, status = Bundler.with_unbundled_env do
      Open3.capture3(environment, executable, grammar, "--output-file", output, chdir: directory)
    end
    assert status.success?, stderr
    assert File.file?(output)
  end

  def copy_tracked_source(destination)
    stdout, stderr, status = Open3.capture3("git", "ls-files", "-z", chdir: ROOT)
    assert status.success?, stderr

    stdout.split("\0").each do |relative|
      source = File.join(ROOT, relative)
      next unless File.file?(source)

      target = File.join(destination, relative)
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.cp(source, target)
    end
  end

  def generated_parser(embedded:)
    ast = Ibex::Frontend::Parser.new(SOURCE, file: "runtime-only.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    Ibex::Codegen::Ruby.new(automaton, embedded: embedded).generate
  end

  def with_runtime_tree
    specification = Gem::Specification.load(RUNTIME_GEMSPEC)
    Dir.mktmpdir("ibex-runtime-tree") do |directory|
      specification.files.grep(%r{\Alib/}).each do |relative|
        target = File.join(directory, relative)
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp(File.join(ROOT, relative), target)
      end
      yield directory
    end
  end

  def runtime_script
    <<~RUBY
      load File.expand_path("parser.rb", Dir.pwd)
      abort "frontend leaked" if defined?(Ibex::Frontend)
      parser = RuntimeOnlyParser.new
      abort "push failed" unless parser.push(:VALUE, 42) == :need_more
      abort "parse failed" unless parser.finish == 42
      abort "runtime version missing" unless Ibex::Runtime::VERSION == "0.1.0"
    RUBY
  end
end
