# frozen_string_literal: true

require_relative "lib/ibex/version"

Gem::Specification.new do |spec|
  spec.name = "ibex"
  spec.version = Ibex::VERSION
  spec.authors = ["Yudai Takada"]
  spec.email = ["t.yudai92@gmail.com"]

  spec.summary = "A Pure Ruby LR parser generator"
  spec.description = "Ibex generates LR parsers from racc-compatible grammars without native extensions."
  spec.homepage = "https://github.com/ydah/ibex"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/main"
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  development_files = %w[
    .gitignore
    .yardopts
    Gemfile
    Gemfile.lock
    package.json
    package-lock.json
  ]
  development_directories = %w[
    .github/
    .idea/
    benchmark/
    docs/decisions/
    gemfiles/
    site/
    test/
    tool/
  ]
  tracked_files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      f == gemspec || development_files.include?(f) || f.start_with?(*development_directories)
    end
  end
  schema_files = %w[
    schema/grammar-ir-v1.schema.json
    schema/automaton-ir-v1.schema.json
    schema/grammar-ir-v2.schema.json
    schema/automaton-ir-v2.schema.json
    schema/explain-v1.schema.json
    schema/benchmark-v1.schema.json
    schema/benchmark-v2.schema.json
    schema/generation-manifest-v1.schema.json
    schema/runtime-event-v1.schema.json
    schema/runtime-coverage-v1.schema.json
    schema/table-simulation-v1.schema.json
    schema/migration-check-v1.schema.json
  ]
  spec.files = (tracked_files + schema_files).uniq.sort
  spec.bindir = "exe"
  spec.executables = ["ibex"]
  spec.require_paths = ["lib"]
end
