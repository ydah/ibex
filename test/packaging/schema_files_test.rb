# frozen_string_literal: true

require_relative "../test_helper"

class SchemaFilesPackagingTest < Minitest::Test
  def test_ir_schemas_are_packaged_in_the_gem
    specification = Gem::Specification.load(File.expand_path("../../ibex.gemspec", __dir__))

    expected = %w[
      schema/grammar-ir-v1.schema.json
      schema/automaton-ir-v1.schema.json
      schema/grammar-ir-v2.schema.json
      schema/automaton-ir-v2.schema.json
      schema/lexer-ir-v1.schema.json
      schema/explain-v1.schema.json
      schema/benchmark-v1.schema.json
      schema/benchmark-v2.schema.json
      schema/error-ux-v1.schema.json
      schema/migration-check-v1.schema.json
      schema/generation-manifest-v1.schema.json
      lib/ibex/codegen/action_method_source.rb
      lib/ibex/codegen/action_source.rb
      lib/ibex/cli/formatting.rb
      lib/ibex/frontend/formatter.rb
      sig/ibex/codegen/action_method_source.rbs
      sig/ibex/codegen/action_source.rbs
      sig/ibex/cli/formatting.rbs
      sig/ibex/frontend/formatter.rbs
    ]
    expected.each { |path| assert_includes specification.files, path }
  end

  def test_lsp_sources_and_signatures_are_packaged_in_the_gem
    specification = Gem::Specification.load(File.expand_path("../../ibex.gemspec", __dir__))

    assert_includes specification.files, "lib/ibex/cli/lsp.rb"
    assert_includes specification.files, "lib/ibex/frontend/source_loader.rb"
    assert_includes specification.files, "lib/ibex/lsp.rb"
    assert_includes specification.files, "lib/ibex/lsp/document_store_diagnostics.rb"
    assert_includes specification.files, "lib/ibex/lsp/server.rb"
    assert_includes specification.files, "lib/ibex/lsp/symbol_index_precedence_references.rb"
    assert_includes specification.files, "sig/ibex/cli/lsp.rbs"
    assert_includes specification.files, "sig/ibex/frontend/source_loader.rbs"
    assert_includes specification.files, "sig/ibex/lsp.rbs"
    assert_includes specification.files, "sig/ibex/lsp/document_store_diagnostics.rbs"
    assert_includes specification.files, "sig/ibex/lsp/server.rbs"
    assert_includes specification.files, "sig/ibex/lsp/symbol_index_precedence_references.rbs"
  end

  def test_transaction_and_watch_sources_and_signatures_are_packaged_in_the_gem
    specification = Gem::Specification.load(File.expand_path("../../ibex.gemspec", __dir__))
    relative_paths = %w[
      ibex/artifact_set
      ibex/cli/generation_artifacts
      ibex/cli/watch
      ibex/generation_input
      ibex/generation_manifest
      ibex/generation_transaction
      ibex/generation_transaction_recovery
      ibex/generation_transaction_validation
      ibex/watch
      ibex/watch/runner
      ibex/watch/source_snapshot
    ]

    relative_paths.each do |path|
      assert_includes specification.files, "lib/#{path}.rb"
      assert_includes specification.files, "sig/#{path}.rbs"
    end
  end

  def test_development_and_project_site_files_are_not_packaged
    specification = Gem::Specification.load(File.expand_path("../../ibex.gemspec", __dir__))
    excluded = %w[
      .yardopts
      gemfiles/docs.Gemfile
      package-lock.json
      package.json
      site/index.html
      tool/build_site.rb
    ]

    excluded.each { |path| refute_includes specification.files, path }
  end
end
