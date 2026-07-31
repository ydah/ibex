# frozen_string_literal: true

require "digest"
require "open3"
require "pathname"
require "rbconfig"
require "rubygems/package"
require "stringio"
require "tmpdir"
require "yaml"
require_relative "../../lib/ibex/error"

module Ibex
  module Quality
    # Verifies the source-level Stable API lock and byte-reproducible gem
    # packages without publishing either package.
    class Release
      ROOT = File.expand_path("../..", __dir__)
      MANIFEST = File.join(ROOT, "tool/quality/stable-api-v1.yml")
      GEMSPEC_PATHS = {
        "ibex-runtime" => "ibex-runtime.gemspec",
        "ibex" => "ibex.gemspec"
      }.freeze
      BUILD_ENVIRONMENTS = [
        { "LANG" => "C", "LC_ALL" => "C", "TZ" => "UTC", "RUBYOPT" => nil },
        {
          "LANG" => "C.UTF-8",
          "LC_ALL" => "C.UTF-8",
          "TZ" => "Pacific/Honolulu",
          "RUBYOPT" => "--enable-frozen-string-literal"
        }
      ].freeze
      FORBIDDEN_PACKAGE_PREFIXES = %w[
        .git/ .idea/ benchmark/ docs/investigations/ gallery/ test/ tool/
      ].freeze

      def initialize(root: ROOT, manifest: MANIFEST, output: $stdout)
        @root = File.expand_path(root)
        @manifest = File.expand_path(manifest)
        @output = output
      end

      # @rbs () -> Hash[String, String]
      def verify!
        verify_stable_api!
        verify_packages!
      end

      # @rbs () -> Integer
      def verify_stable_api!
        document = load_manifest
        files = document.fetch("files")
        raise Ibex::Error, "Stable API lock must not be empty" if files.empty?
        raise Ibex::Error, "Stable API lock paths must be sorted" unless files.keys == files.keys.sort

        files.each do |relative, expected|
          validate_locked_path!(relative, expected)
          actual = signature_digest(File.binread(File.join(@root, relative)))
          next if actual == expected

          raise Ibex::Error,
                "#{relative}: Stable API differs from #{document.fetch('baseline')}; " \
                "review compatibility before changing the v1 lock"
        end
        @output.puts "Stable API: 0 normalized declaration differences across #{files.length} files"
        files.length
      end

      # @rbs () -> Hash[String, String]
      def verify_packages!
        builds = BUILD_ENVIRONMENTS.each_index.map { |index| build_packages(index) }
        first = builds.fetch(0)
        second = builds.fetch(1)

        first.each do |name, artifact|
          other = second.fetch(name)
          compare_artifacts!(name, artifact, other)
          @output.puts "#{name}: byte-reproducible sha256=#{artifact.fetch(:digest)}"
        end
        first.transform_values { |artifact| artifact.fetch(:digest) }
      end

      private

      # @rbs () -> Hash[String, untyped]
      def load_manifest
        document = YAML.safe_load_file(@manifest, permitted_classes: [], aliases: false)
        unless document.is_a?(Hash) && document.keys.sort == %w[baseline files version]
          raise Ibex::Error, "Stable API lock must contain exactly baseline, files, and version"
        end
        raise Ibex::Error, "unsupported Stable API lock version" unless document["version"] == 1
        raise Ibex::Error, "Stable API lock baseline must be a release tag" unless
          document["baseline"].is_a?(String) && document["baseline"].match?(/\Av\d+\.\d+\.\d+\z/)
        raise Ibex::Error, "Stable API lock files must be a mapping" unless document["files"].is_a?(Hash)

        document
      end

      # @rbs (String relative, String expected) -> void
      def validate_locked_path!(relative, expected)
        path = Pathname.new(relative)
        unless relative.end_with?(".rbs") && !path.absolute? && path.cleanpath.to_s == relative
          raise Ibex::Error, "invalid Stable API lock path: #{relative.inspect}"
        end
        raise Ibex::Error, "missing Stable API declaration: #{relative}" unless
          File.file?(File.join(@root, relative))
        return if expected.match?(/\A[0-9a-f]{64}\z/)

        raise Ibex::Error, "#{relative}: invalid Stable API digest"
      end

      # @rbs (String source) -> String
      def signature_digest(source)
        normalized = source.lines.reject do |line|
          line.lstrip.start_with?("#") || line.strip.empty?
        end.map(&:rstrip).join("\n")
        Digest::SHA256.hexdigest("#{normalized}\n")
      end

      # @rbs (Integer index) -> Hash[String, Hash[Symbol, untyped]]
      def build_packages(index)
        Dir.mktmpdir("ibex-release-#{index + 1}") do |directory|
          GEMSPEC_PATHS.to_h do |name, relative_gemspec|
            output = File.join(directory, "#{name}.gem")
            build_package(relative_gemspec, output, BUILD_ENVIRONMENTS.fetch(index))
            [name, package_artifact(output, name)]
          end
        end
      end

      # @rbs (String relative_gemspec, String output, Hash[String, String?] environment) -> void
      def build_package(relative_gemspec, output, environment)
        build_environment = environment.merge("SOURCE_DATE_EPOCH" => "0")
        command = [
          RbConfig.ruby, "-S", "gem", "build", File.join(@root, relative_gemspec),
          "--output", output
        ]
        _stdout, stderr, status = Open3.capture3(build_environment, *command, chdir: @root)
        return if status.success? && File.file?(output)

        raise Ibex::Error, "#{relative_gemspec}: reproducible package build failed: #{stderr.strip}"
      end

      # @rbs (String path, String expected_name) -> Hash[Symbol, untyped]
      def package_artifact(path, expected_name)
        bytes = File.binread(path)
        specification = Gem::Package.new(path).spec
        raise Ibex::Error, "#{path}: built unexpected gem #{specification.name}" unless
          specification.name == expected_name

        validate_package_files!(expected_name, specification.files)
        {
          bytes: bytes,
          digest: Digest::SHA256.hexdigest(bytes),
          files: specification.files.sort
        }
      end

      # @rbs (String name, Array[String] files) -> void
      def validate_package_files!(name, files)
        raise Ibex::Error, "#{name}: package file list must not be empty" if files.empty?

        unsafe = files.select do |relative|
          path = Pathname.new(relative)
          path.absolute? || path.cleanpath.to_s != relative || FORBIDDEN_PACKAGE_PREFIXES.any? do |prefix|
            relative.start_with?(prefix)
          end
        end
        return if unsafe.empty?

        raise Ibex::Error, "#{name}: package includes development-only or unsafe paths: #{unsafe.join(', ')}"
      end

      # @rbs (String name, Hash[Symbol, untyped] expected, Hash[Symbol, untyped] actual) -> void
      def compare_artifacts!(name, expected, actual)
        unless expected.fetch(:files) == actual.fetch(:files)
          raise Ibex::Error, "#{name}: package file list depends on build environment"
        end
        return if expected.fetch(:bytes) == actual.fetch(:bytes)

        raise Ibex::Error,
              "#{name}: package bytes depend on locale, timezone, or frozen-string environment " \
              "(#{expected.fetch(:digest)} != #{actual.fetch(:digest)})"
      end
    end
  end
end
