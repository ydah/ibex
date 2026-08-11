# frozen_string_literal: true

module Ibex
  module ErrorUXRound2
    # Collects the repository-owned Ruby sources reachable from the H003 generator.
    class ImplementationClosure
      ENTRYPOINTS = ["tool/error_ux_round2.rb"].freeze
      # Release metadata is loaded by the aggregate entrypoint but cannot alter
      # the diagnostic behavior captured by H003. Excluding it keeps a version
      # bump from invalidating a behavioral evidence snapshot.
      RELEASE_METADATA_PATHS = %w[lib/ibex/version.rb lib/ibex/runtime/version.rb].freeze
      REQUIRE = /^\s*require(_relative)?\s+["']([^"']+)["']/

      def initialize(root:)
        @root = File.expand_path(root)
      end

      def paths
        @paths ||= collect.freeze
      end

      private

      def collect
        pending = ENTRYPOINTS.dup
        visited = {}
        until pending.empty?
          path = pending.shift
          next if visited.key?(path)

          visited[path] = true
          next if RELEASE_METADATA_PATHS.include?(path)

          pending.concat(dependencies(path))
        end
        visited.keys.reject { |path| RELEASE_METADATA_PATHS.include?(path) }.sort
      end

      def dependencies(path)
        absolute = File.join(@root, path)
        raise "H003 implementation source is missing: #{path}" unless File.file?(absolute)

        File.foreach(absolute).filter_map do |line|
          match = REQUIRE.match(line)
          next unless match

          resolve(path, relative: !match[1].nil?, feature: match[2])
        end
      end

      def resolve(owner, relative:, feature:)
        candidate = if relative
                      File.expand_path(feature, File.dirname(File.join(@root, owner)))
                    elsif feature == "ibex" || feature.start_with?("ibex/")
                      File.join(@root, "lib", feature)
                    end
        return unless candidate

        candidate = "#{candidate}.rb" unless candidate.end_with?(".rb")
        relative_path(candidate)
      end

      def relative_path(absolute)
        prefix = "#{@root}/"
        raise "H003 implementation dependency escapes the repository: #{absolute}" unless absolute.start_with?(prefix)

        path = absolute.delete_prefix(prefix)
        allowed = path == "lib/ibex.rb" || path.start_with?("lib/ibex/") ||
                  path == "tool/error_ux_round2.rb" || path.start_with?("tool/error_ux_round2/")
        raise "H003 implementation dependency is outside the trusted closure: #{path}" unless allowed
        raise "H003 implementation dependency is missing: #{path}" unless File.file?(absolute)

        path
      end
    end
  end
end
