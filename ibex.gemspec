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
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[Gemfile .gitignore test/ benchmark/ tool/ .github/ .idea/ docs/decisions/])
    end
  end
  spec.bindir = "exe"
  spec.executables = ["ibex"]
  spec.require_paths = ["lib"]
end
