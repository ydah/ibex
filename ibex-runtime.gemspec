# frozen_string_literal: true

require_relative "lib/ibex/runtime/version"

Gem::Specification.new do |spec|
  spec.name = "ibex-runtime"
  spec.version = Ibex::Runtime::VERSION
  spec.authors = ["Yudai Takada"]
  spec.email = ["t.yudai92@gmail.com"]

  spec.summary = "The Pure Ruby runtime for generated Ibex parsers"
  spec.description = "Ibex Runtime executes generated LR parsers without installing the parser generator."
  spec.homepage = "https://github.com/ydah/ibex"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/main"
  spec.metadata["rubygems_mfa_required"] = "true"

  source_files = [
    "lib/ibex/runtime.rb",
    "lib/ibex/tables/compact.rb",
    "lib/ibex/tables/compact_actions.rb",
    *Dir.glob("lib/ibex/runtime/**/*.rb")
  ]
  signature_files = [
    "sig/ibex/runtime.rbs",
    "sig/ibex/tables/compact.rbs",
    "sig/ibex/tables/compact_actions.rbs",
    *Dir.glob("sig/ibex/runtime/**/*.rbs")
  ]
  spec.files = (%w[LICENSE.txt README.md] + source_files + signature_files).uniq.sort
  spec.require_paths = ["lib"]
end
