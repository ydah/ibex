# frozen_string_literal: true

require "yaml"

module Ibex
  module Quality
    # Extracts one strictly delimited YAML contract from a Markdown document.
    module RuntimeABIDocument
      def load_contract(path, name)
        load_contract_source(File.binread(path), name, relative(path))
      end

      def load_contract_source(source, name, label)
        start_marker = "<!-- ibex-#{name}-contract:start -->"
        end_marker = "<!-- ibex-#{name}-contract:end -->"
        pattern = /#{Regexp.escape(start_marker)}\s*```yaml\s*\n(.*?)```\s*#{Regexp.escape(end_marker)}/m
        matches = source.scan(pattern)
        raise "#{label} must contain exactly one #{name} contract" unless matches.length == 1

        value = YAML.safe_load(matches.fetch(0).fetch(0), permitted_classes: [], aliases: false)
        raise "#{label} #{name} contract must be a mapping" unless value.is_a?(Hash)

        value
      rescue Psych::Exception => e
        raise "#{label} #{name} contract is invalid YAML: #{e.message}"
      end

      def exact_keys!(value, keys, label)
        actual = value.keys.sort
        expected = keys.sort
        raise "#{label} keys must be #{expected.join(', ')}; got #{actual.join(', ')}" unless actual == expected
      end

      def relative(path)
        path.delete_prefix("#{@root}/")
      end
    end
  end
end
