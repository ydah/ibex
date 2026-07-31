# frozen_string_literal: true

require "digest"
require "fileutils"
require "yaml"
require_relative "../../lib/ibex"

module Ibex
  module Quality
    # Owns reviewable generated-source baselines for feature-off grammars.
    class Golden
      SOURCES = [
        "test/fixtures/compat/calculator.y",
        "benchmark/grammars/representative.y",
        "gallery/json/grammar.y"
      ].freeze

      def initialize(root: File.expand_path("../..", __dir__), output: $stdout)
        @root = root
        @output = output
        @directory = File.join(root, "test/golden/generated")
        @digest_path = File.join(root, "test/golden/digests.yml")
      end

      def record!
        raise Ibex::Error, "golden baseline already exists; use golden:update" if File.exist?(@digest_path)

        update!
      end

      def update!
        generated = generate_all
        FileUtils.mkdir_p(@directory)
        Dir.glob(File.join(@directory, "*.rb")).each do |path|
          File.delete(path) unless generated.key?(File.basename(path))
        end
        generated.each { |name, source| File.binwrite(File.join(@directory, name), source) }
        digests = generated.transform_values { |source| Digest::SHA256.hexdigest(source) }
        File.write(@digest_path, YAML.dump(digests.sort.to_h))
        @output.puts "updated #{generated.length} golden generated sources"
        generated.length
      end

      def verify!
        expected_digests = YAML.safe_load_file(@digest_path)
        generated = generate_all
        expected_names = expected_digests.keys.sort
        unless generated.keys.sort == expected_names
          raise Ibex::Error, "golden file set changed: #{generated.keys.sort.inspect}"
        end

        generated.each do |name, actual|
          path = File.join(@directory, name)
          expected = File.binread(path)
          verify_one(name, expected, actual, expected_digests.fetch(name))
        end
        @output.puts "verified #{generated.length} golden generated sources"
        generated.length
      end

      def reproducible!
        first = with_environment("C", "UTC", nil) { generate_all }
        second = with_environment("ja_JP.UTF-8", "Pacific/Honolulu", "--enable-frozen-string-literal") { generate_all }
        first.each do |name, source|
          compare_bytes(name, source, second.fetch(name), "environment-dependent generation")
        end
        @output.puts "generation is byte-reproducible across locale, TZ, and RUBYOPT inputs"
        first.length
      end

      private

      def generate_all
        SOURCES.to_h do |relative|
          path = File.join(@root, relative)
          source = File.binread(path)
          ast = Frontend::Parser.new(source, file: relative, mode: :extended).parse
          grammar = Normalizer.new(ast, mode: :extended).normalize
          automaton = LALR::Builder.new(grammar).build
          name = relative.tr("/", "-").sub(/\.y\z/, ".rb")
          [name, Codegen::Ruby.new(automaton, table: :compact).generate]
        end
      end

      def verify_one(name, expected, actual, digest)
        actual_digest = Digest::SHA256.hexdigest(actual)
        unless Digest::SHA256.hexdigest(expected) == digest
          raise Ibex::Error, "#{name}: committed generated source does not match test/golden/digests.yml"
        end
        return if actual_digest == digest && actual == expected

        compare_bytes(name, expected, actual, "golden mismatch")
      end

      def compare_bytes(name, expected, actual, description)
        return if expected == actual

        limit = [expected.bytesize, actual.bytesize].min
        offset = 0
        offset += 1 while offset < limit && expected.getbyte(offset) == actual.getbyte(offset)
        expected_byte = expected.getbyte(offset)&.to_s(16) || "EOF"
        actual_byte = actual.getbyte(offset)&.to_s(16) || "EOF"
        raise Ibex::Error,
              "#{name}: #{description} at byte #{offset} (expected #{expected_byte}, actual #{actual_byte}); " \
              "run `bundle exec rake golden:update` and review the generated-source diff"
      end

      def with_environment(locale, timezone, rubyopt)
        saved = %w[LANG LC_ALL TZ RUBYOPT].to_h { |name| [name, ENV.fetch(name, nil)] }
        ENV["LANG"] = locale
        ENV["LC_ALL"] = locale
        ENV["TZ"] = timezone
        rubyopt ? ENV["RUBYOPT"] = rubyopt : ENV.delete("RUBYOPT")
        yield
      ensure
        saved.each { |name, value| value ? ENV[name] = value : ENV.delete(name) }
      end
    end
  end
end
