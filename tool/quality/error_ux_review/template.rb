# frozen_string_literal: true

require "etc"
require "json"
require "open3"
require "rbconfig"
require_relative "identity"

module Ibex
  module Quality
    class ErrorUXReviewTemplate
      include ErrorUXReviewIdentity

      def initialize(root:, kit:, revision: nil)
        @root = root
        @kit = kit
        @revision = revision
      end

      def write!(path)
        raise "refusing to overwrite existing review draft #{path}" if File.exist?(path)

        File.binwrite(path, "#{JSON.pretty_generate(build)}\n")
      end

      def build
        revision = source_revision
        {
          "schema_version" => 1,
          "record_id" => "REPLACE_WITH_STABLE_RECORD_ID",
          "record_state" => "draft",
          "kit" => kit_identity,
          "evidence" => evidence(revision),
          "reproduction" => reproduction,
          "reviewer" => reviewer,
          "independence" => independence,
          "consent" => consent,
          "assessments" => CASE_IDS.map { |id| assessment(id) },
          "overall_rationale" => "REPLACE_WITH_OVERALL_RATIONALE"
        }
      end

      private

      def source_revision
        return @revision if @revision

        ensure_clean_tracked_checkout!
        ErrorUXReviewIdentity.git_revision(@root)
      end

      def ensure_clean_tracked_checkout!
        output, error, status = Open3.capture3(
          "git", "-C", @root, "status", "--porcelain=v1"
        )
        raise "cannot inspect repository status: #{error.strip}" unless status.success?
        return if output.empty?

        raise "tracked or untracked source changes must be committed before generating a review draft"
      end

      def kit_identity
        %w[id version rubric_path rubric_sha256 schema_path schema_sha256].to_h do |key|
          [key, @kit.fetch(key)]
        end
      end

      def evidence(revision)
        {
          "repository" => { "url" => @kit.fetch("repository_url"), "revision" => revision },
          "snapshot" => {
            "path" => @kit.dig("snapshot", "path"),
            "sha256" => source_digest(revision, @kit.dig("snapshot", "path"))
          },
          "corpus" => corpus(revision),
          "case_ids" => CASE_IDS
        }
      end

      def corpus(revision)
        introduction = @kit.fetch("corpus_at_introduction")
        ibex_path = introduction.fetch("ibex_grammar")
        racc_path = introduction.fetch("racc_grammar")
        {
          "ibex_grammar" => ibex_path,
          "ibex_grammar_sha256" => source_digest(revision, ibex_path),
          "racc_grammar" => racc_path,
          "racc_grammar_sha256" => source_digest(revision, racc_path)
        }
      end

      def reproduction
        {
          "command" => {
            "executable" => "bundle",
            "argv" => %w[exec ruby tool/error_ux_snapshot.rb]
          },
          "snapshot_result" => "passed",
          "ruby" => ruby_identity,
          "racc" => { "version" => command_output("racc", "--version") },
          "environment" => environment
        }
      end

      def ruby_identity
        {
          "description" => RUBY_DESCRIPTION,
          "engine" => RUBY_ENGINE,
          "version" => RUBY_VERSION,
          "platform" => RUBY_PLATFORM,
          "yjit_enabled" => defined?(RubyVM::YJIT) ? RubyVM::YJIT.enabled? : false
        }
      end

      def environment
        {
          "host_cpu" => RbConfig::CONFIG.fetch("host_cpu"),
          "host_os" => RbConfig::CONFIG.fetch("host_os"),
          "kernel_release" => command_output("uname", "-srvm"),
          "processors" => Etc.nprocessors
        }
      end

      def reviewer
        {
          "github_login" => "REPLACE_WITH_CANONICAL_GITHUB_LOGIN",
          "display_name" => "REPLACE_WITH_REVIEWER_DISPLAY_NAME",
          "affiliation" => "REPLACE_WITH_REVIEWER_AFFILIATION",
          "reviewed_on" => "REPLACE_WITH_YYYY-MM-DD",
          "conflicts" => "REPLACE_WITH_CONFLICT_DISCLOSURE"
        }
      end

      def independence
        {
          "reviewed_maintainer_github_logins" => @kit.fetch("maintainer_github_logins")
        }
      end

      def consent
        {
          "store_identity" => false,
          "store_labels" => false,
          "store_rationales" => false,
          "republish_review" => false
        }
      end

      def assessment(id)
        {
          "case_id" => id,
          "diagnostic" => { "label" => "unclear", "rationale" => "REPLACE_WITH_DIAGNOSTIC_RATIONALE" },
          "repair" => { "label" => "unclear", "rationale" => "REPLACE_WITH_REPAIR_RATIONALE" },
          "disagreement" => {
            "exists" => false,
            "subjects" => [],
            "rationale" => "REPLACE_WITH_DISAGREEMENT_OR_NO_DISAGREEMENT_RATIONALE"
          }
        }
      end

      def source_digest(revision, relative)
        ErrorUXReviewIdentity.digest(ErrorUXReviewIdentity.git_show(@root, revision, relative))
      end

      def command_output(*command)
        output, error, status = Open3.capture3(*command)
        raise "#{command.join(' ')} failed: #{error.strip}" unless status.success?

        output.strip
      end
    end
  end
end
