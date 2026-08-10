# frozen_string_literal: true

require_relative "lib/ibex/version"
require_relative "lib/ibex/runtime/version"

Gem::Specification.new do |spec|
  spec.name = "ibex"
  spec.version = Ibex::VERSION
  spec.authors = ["Yudai Takada"]
  spec.email = ["t.yudai92@gmail.com"]

  spec.summary = "A Pure Ruby LR parser generator"
  spec.description = "Ibex generates LR parsers from racc-compatible grammars without native extensions."
  spec.homepage = "https://ydah.github.io/ibex/"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/ydah/ibex"
  spec.metadata["documentation_uri"] = "https://ydah.github.io/ibex/api/"
  spec.metadata["changelog_uri"] = "https://github.com/ydah/ibex/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/ydah/ibex/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  package_files = Dir.chdir(__dir__) do
    [
      "LICENSE.txt",
      "README.md",
      "exe/ibex",
      *Dir.glob("lib/**/*.rb"),
      *Dir.glob("lib/**/*.yml"),
      *Dir.glob("sig/**/*.rbs"),
      *Dir.glob("schema/*.json"),
      *Dir.glob("docs/**/*.md").reject { |path| path.start_with?("docs/investigations/") },
      "docs/error-ux-round2-v1.json",
      "docs/error-ux-round2-review-status-v1.json",
      *Dir.glob("examples/**/*").select { |path| File.file?(path) }
    ]
  end
  spec.files = package_files.reject do |path|
    path == "lib/ibex/runtime.rb" ||
      path.start_with?("lib/ibex/runtime/", "sig/ibex/runtime") ||
      path.start_with?("lib/ibex/tables/compact", "sig/ibex/tables/compact")
  end.uniq.sort
  spec.bindir = "exe"
  spec.executables = ["ibex"]
  spec.require_paths = ["lib"]
  spec.add_dependency "ibex-runtime", "~> #{Ibex::Runtime::VERSION}"
end
