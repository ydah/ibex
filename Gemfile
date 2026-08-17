# frozen_string_literal: true

source "https://rubygems.org"

gemspec name: "ibex"
gemspec name: "ibex-runtime"

gem "json_schemer", "2.5.0", require: false
gem "minitest", "~> 5.0"
gem "rake", "~> 13.0"
gem "rubocop", "~> 1.0", require: false

group :types do
  gem "rbs", "4.1.2", require: false
  gem "rbs-inline", "0.14.0", require: false
  gem "steep", "2.0.0", require: false
end

group :docs do
  gem "yard", "0.9.45", require: false
end

group :mutation do
  gem "mutant-minitest", "0.16.3", require: false
end

group :profile do
  gem "stackprof", "0.2.28", require: false
end
