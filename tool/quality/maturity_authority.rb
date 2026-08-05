# frozen_string_literal: true

module Ibex
  module Quality
    # rubocop:disable Metrics/ModuleLength -- one closed authority maps every audited feature.
    # Human-reviewed Git authorities used by the executable maturity audit.
    module MaturityAuthority
      REVIEWED_REVISION = "7517b302c72fae926b6e0a81f1f89772971d82d4"
      RELEASES = {
        "v0.1.0" => "65d41edf381afb9c18e01e55332a293332f340e6",
        "v0.2.0" => "bd88b1203706c37bf225e837a2fe46d334d4651d"
      }.freeze
      SNAPSHOTS = RELEASES.merge("reviewed" => REVIEWED_REVISION).freeze

      INTRODUCTIONS = {
        "ebnf-groups" => {
          path: "lib/ibex/frontend/ast.rb", query: "Group = Struct",
          revision: "4ea1196c01c3dd604a42e9139a32edec0d25c7ec", first_release: "v0.1.0",
          feature_status: %w[present present present], absent_sources: [[], [], []]
        },
        "parameterized-rules" => {
          path: "lib/ibex/frontend/ast.rb", query: "ParameterizedReference",
          revision: "18f618c490c91837b97e628c178c6dd4e50abb4d", first_release: "v0.2.0",
          feature_status: %w[absent present present],
          absent_sources: [["lib/ibex/normalize/parameters.rb"], [], []]
        },
        "inline-rules" => {
          path: "lib/ibex/normalize.rb", query: "inline_rule_names",
          revision: "51234f2acc5080981c399f3821fe61d07f4b38af", first_release: "v0.2.0",
          feature_status: %w[absent present present],
          absent_sources: [["lib/ibex/normalize/inline_expansion.rb"], [], []]
        },
        "middle-actions" => {
          path: "lib/ibex/frontend/ast.rb", query: "InlineAction",
          revision: "3bf5565285cbb22eb2acee9f0f6c7ea63a85e096", first_release: "v0.1.0",
          feature_status: %w[present present present], absent_sources: [[], [], []]
        },
        "multiple-entries" => {
          path: "lib/ibex/lalr/builder.rb", query: "entry_isolation",
          revision: "af3f23e6c3fd6d9a19ce9a84c5a4655f6761a49d", first_release: "v0.2.0",
          feature_status: %w[absent present present], absent_sources: [[], [], []]
        },
        "canonical-imports" => {
          path: "lib/ibex/frontend/resolver.rb", query: "class Resolver",
          revision: "cf4fbd16fe614d48bcdb93092399352fc7917f95", first_release: "v0.2.0",
          feature_status: %w[absent present present],
          absent_sources: [["lib/ibex/frontend/resolver.rb"], [], []]
        },
        "generated-lexers" => {
          path: "lib/ibex/runtime/generated_lexer.rb", query: "module GeneratedLexer",
          revision: "d8ee14f8b80a1acc4bf27b15d52b1c3517aed5b5", first_release: "v0.2.0",
          feature_status: %w[absent present present],
          absent_sources: [["lib/ibex/runtime/generated_lexer.rb"], [], []]
        },
        "semantic-locations-types" => {
          path: "lib/ibex/frontend/generated_parser_metadata.rb", query: "build_semantic_type",
          revision: "1418a5a36c6fdeb5370a7cc2dc4ad62de2317656", first_release: "v0.2.0",
          feature_status: %w[absent present present],
          absent_sources: [["lib/ibex/frontend/generated_parser_metadata.rb"], [], []]
        },
        "ast-generation" => {
          path: "lib/ibex/codegen/ruby_ast.rb", query: "RubyAST",
          revision: "c7117a5acaa51b501b8de20b75bbac4e3675ec35", first_release: "v0.2.0",
          feature_status: %w[absent present present],
          absent_sources: [["lib/ibex/codegen/ruby_ast.rb"], [], []]
        },
        "grammar-tests" => {
          path: "lib/ibex/grammar_tests.rb", query: "GrammarTests",
          revision: "6a97c6580eb60f21bee3019dd5301898f4e927f1", first_release: "v0.2.0",
          feature_status: %w[absent present present],
          absent_sources: [["lib/ibex/grammar_tests.rb"], [], []]
        },
        "documentation-tooling" => {
          path: "lib/ibex/codegen/documentation.rb", query: "Documentation",
          revision: "81026ff3390990cad716e9953c8b485f9ac198fe", first_release: "v0.2.0",
          feature_status: %w[absent present present],
          absent_sources: [["lib/ibex/codegen/documentation.rb"], [], []]
        },
        "ielr" => {
          path: "lib/ibex/lalr/builder.rb", query: "algorithm == :ielr",
          revision: "14968f22795f4fd8ff894b0753b01b92712bd183", first_release: "v0.2.0",
          feature_status: %w[absent present present], absent_sources: [[], [], []]
        },
        "lsp" => {
          path: "lib/ibex/lsp/server.rb", query: "class Server",
          revision: "5b8151385c491366deb41c930a1132599edfb9e9", first_release: "v0.2.0",
          feature_status: %w[absent present present],
          absent_sources: [["lib/ibex/lsp/server.rb"], [], []]
        },
        "watch" => {
          path: "lib/ibex/watch/runner.rb", query: "class Runner",
          revision: "570d857f582cb61ac60840210b22a86db086cc51", first_release: "v0.2.0",
          feature_status: %w[absent present present],
          absent_sources: [["lib/ibex/watch/runner.rb"], [], []]
        },
        "debug" => {
          path: "lib/ibex/table_simulation.rb", query: "module TableSimulation",
          revision: "4aa58c5e6f013c6ad187b9a739d55147829aa42c", first_release: "v0.2.0",
          feature_status: %w[absent present present],
          absent_sources: [["lib/ibex/table_simulation.rb"], [], []]
        },
        "coverage" => {
          path: "lib/ibex/coverage/collector.rb", query: "class Collector",
          revision: "f10cb2af61566d5180724469a5498fbc7325dc2c", first_release: "v0.2.0",
          feature_status: %w[absent present present],
          absent_sources: [["lib/ibex/coverage/collector.rb"], [], []]
        },
        "browser-playground" => {
          path: "site/playground/analyzer.rb", query: "IbexPlayground",
          revision: "30c41be981e41c3fbd71e1f75afe296b329ddbd3", first_release: "v0.2.0",
          feature_status: %w[absent present present],
          absent_sources: [["site/playground/analyzer.rb"], [], []]
        },
        "action-shadow" => {
          path: "lib/ibex/codegen/action_method_source.rb", query: "class ActionMethodSource",
          revision: "3187b74d3933259a1a44deee8ed90aabf61a2efb", first_release: "v0.2.0",
          feature_status: %w[absent present present],
          absent_sources: [["lib/ibex/codegen/action_method_source.rb"], [], []]
        },
        "bounded-repair" => {
          path: "lib/ibex/runtime/repair.rb", query: "class RepairPolicy",
          revision: "df8ac82c0ed0c8862190ac88671949f0d5e8a001", first_release: "v0.2.0",
          feature_status: %w[absent present present],
          absent_sources: [["lib/ibex/runtime/repair.rb"], [], []]
        },
        "incremental-cst" => {
          path: "lib/ibex/runtime/parser.rb", query: "incremental_session",
          revision: "0b33bac2d2a2e2bfdaa31f5721d34231f23ce23e", first_release: "v0.2.0",
          feature_status: %w[absent partial present],
          absent_sources: [
            %w[
              lib/ibex/runtime/embedded_source.rb
              lib/ibex/runtime/syntax_session.rb
              lib/ibex/runtime/cst/incremental/relexer.rb
              lib/ibex/runtime/cst/incremental/session.rb
            ],
            %w[lib/ibex/runtime/embedded_source.rb lib/ibex/runtime/syntax_session.rb],
            []
          ]
        }
      }.freeze

      # Human-reviewed semantic commits. Empty boundaries are explicit so adding a
      # feature or release range cannot inherit an introduction-only default.
      SEMANTIC_COMMITS = {
        "ebnf-groups" => {
          "introduction..v0.1.0" => %w[
            4ea1196c01c3dd604a42e9139a32edec0d25c7ec
            f3bdaffde3ddb36282921954efa334b86036abd8
          ],
          "v0.1.0..v0.2.0" => [],
          "v0.2.0..reviewed" => []
        },
        "parameterized-rules" => {
          "introduction..v0.2.0" => %w[
            18f618c490c91837b97e628c178c6dd4e50abb4d
            51234f2acc5080981c399f3821fe61d07f4b38af
            3320a2a862628c14f12205575b894a604c9dffc8
          ],
          "v0.2.0..reviewed" => []
        },
        "inline-rules" => {
          "introduction..v0.2.0" => %w[
            51234f2acc5080981c399f3821fe61d07f4b38af
            3187b74d3933259a1a44deee8ed90aabf61a2efb
          ],
          "v0.2.0..reviewed" => []
        },
        "middle-actions" => {
          "introduction..v0.1.0" => %w[
            3bf5565285cbb22eb2acee9f0f6c7ea63a85e096
            cb6dc27b0a76f6023e82ba9491274fdf7a4cd42a
          ],
          "v0.1.0..v0.2.0" => [],
          "v0.2.0..reviewed" => []
        },
        "multiple-entries" => {
          "introduction..v0.2.0" => %w[
            af3f23e6c3fd6d9a19ce9a84c5a4655f6761a49d
          ],
          "v0.2.0..reviewed" => []
        },
        "canonical-imports" => {
          "introduction..v0.2.0" => %w[
            cf4fbd16fe614d48bcdb93092399352fc7917f95
            5b8151385c491366deb41c930a1132599edfb9e9
            570d857f582cb61ac60840210b22a86db086cc51
            af3f23e6c3fd6d9a19ce9a84c5a4655f6761a49d
            7bbab102d981df3c3efffba0bdab301ea4939293
            97fce7fa2476bc7ecd399c7bf30d765420dfc39a
          ],
          "v0.2.0..reviewed" => []
        },
        "generated-lexers" => {
          "introduction..v0.2.0" => %w[
            d8ee14f8b80a1acc4bf27b15d52b1c3517aed5b5
            7bbab102d981df3c3efffba0bdab301ea4939293
            86f9a7face90cc15cc988c3da36925981bdc1513
            0b33bac2d2a2e2bfdaa31f5721d34231f23ce23e
            ba5ee02b3afcb38a62618604faf6b77a53b1671e
            f3cb3826efa6bfcdb7c7ef11494a9d43c47af352
          ],
          "v0.2.0..reviewed" => []
        },
        "semantic-locations-types" => {
          "introduction..v0.2.0" => %w[
            1418a5a36c6fdeb5370a7cc2dc4ad62de2317656
            104a8b19b007201366e25ea13e17b5b8a85076e9
            978465d7996f3610e674da76718f9b2eb118f2dd
            04ded745a43e364bcb8b07f1306a0731223a32ab
            51234f2acc5080981c399f3821fe61d07f4b38af
            3187b74d3933259a1a44deee8ed90aabf61a2efb
            bb8c9a741c96ee4b53b8b63290f988a623d32aa0
            ffbfe9765ccf4da14f2e79b0435e957b1bc5bdb5
            429389ca04861fff104c4bf64e449c9266caa181
          ],
          "v0.2.0..reviewed" => []
        },
        "ast-generation" => {
          "introduction..v0.2.0" => %w[
            c7117a5acaa51b501b8de20b75bbac4e3675ec35
            ffbfe9765ccf4da14f2e79b0435e957b1bc5bdb5
          ],
          "v0.2.0..reviewed" => []
        },
        "grammar-tests" => {
          "introduction..v0.2.0" => %w[
            6a97c6580eb60f21bee3019dd5301898f4e927f1
            6d92ec6d49bf27538fcb115e26ab32c843e4187d
          ],
          "v0.2.0..reviewed" => []
        },
        "documentation-tooling" => {
          "introduction..v0.2.0" => %w[81026ff3390990cad716e9953c8b485f9ac198fe],
          "v0.2.0..reviewed" => []
        },
        "ielr" => {
          "introduction..v0.2.0" => %w[
            14968f22795f4fd8ff894b0753b01b92712bd183
            3320a2a862628c14f12205575b894a604c9dffc8
            af3f23e6c3fd6d9a19ce9a84c5a4655f6761a49d
            d589970fa588fd6a0464e6396fe2da668431aec4
          ],
          "v0.2.0..reviewed" => []
        },
        "lsp" => {
          "introduction..v0.2.0" => %w[5b8151385c491366deb41c930a1132599edfb9e9],
          "v0.2.0..reviewed" => []
        },
        "watch" => {
          "introduction..v0.2.0" => %w[570d857f582cb61ac60840210b22a86db086cc51],
          "v0.2.0..reviewed" => []
        },
        "debug" => {
          "introduction..v0.2.0" => %w[4aa58c5e6f013c6ad187b9a739d55147829aa42c],
          "v0.2.0..reviewed" => []
        },
        "coverage" => {
          "introduction..v0.2.0" => %w[f10cb2af61566d5180724469a5498fbc7325dc2c],
          "v0.2.0..reviewed" => []
        },
        "browser-playground" => {
          "introduction..v0.2.0" => %w[30c41be981e41c3fbd71e1f75afe296b329ddbd3],
          "v0.2.0..reviewed" => []
        },
        "action-shadow" => {
          "introduction..v0.2.0" => %w[
            3187b74d3933259a1a44deee8ed90aabf61a2efb
            e170cee79243d0aa975be3e107cd95cd7cc8baf0
            ee83cf3f06e1b4f7d7c1ece292d43fd7844ee3aa
            ffbfe9765ccf4da14f2e79b0435e957b1bc5bdb5
          ],
          "v0.2.0..reviewed" => []
        },
        "bounded-repair" => {
          "introduction..v0.2.0" => %w[df8ac82c0ed0c8862190ac88671949f0d5e8a001],
          "v0.2.0..reviewed" => []
        },
        "incremental-cst" => {
          "introduction..v0.2.0" => %w[
            0b33bac2d2a2e2bfdaa31f5721d34231f23ce23e
            ba5ee02b3afcb38a62618604faf6b77a53b1671e
            f3cb3826efa6bfcdb7c7ef11494a9d43c47af352
          ],
          "v0.2.0..reviewed" => %w[
            c7d02d408e1778bb8018c1876f8728949bf7aa24
            57d4d7a6e45603f3ea703121a6d45616b8c1929b
            87491f2c009fa98ffbc3a1a865c097926ef79864
          ]
        }
      }.freeze

      STABLE_OVERLAPS = {
        "middle-actions" => {
          surface_ids: ["embedded-production-action"], separable_preview_activation: "none",
          guarantee: "Compatible Racc middle-action syntax and lowering are governed by the Stable compatibility " \
                     "contract and cannot break under Preview notice."
        },
        "semantic-locations-types" => {
          surface_ids: ["semantic-locations"], separable_preview_activation: "semantic-type-declarations",
          guarantee: "Compatible semantic-location behavior is governed by the Stable compatibility contract; " \
                     "only extended semantic type declarations remain a separable Preview surface."
        }
      }.freeze
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
