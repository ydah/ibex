# frozen_string_literal: true

load ARGV.fetch(0)
tokens = [[:NUM, 2], ["+", nil], [:NUM, 3], ["*", nil], [:NUM, 4]]
puts CompatCalc.new.parse_tokens(tokens)
