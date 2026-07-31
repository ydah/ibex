# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "stringio"
require "tempfile"

class MessagesTest < Minitest::Test
  BUILT_IN_ID_PATTERN = /["']((?:cli|diagnostic|label|warning|conflict|note)\.[a-z_.]+)["']/

  def test_all_catalogs_have_exactly_the_same_ids_and_valid_interpolations
    english = Ibex::Messages.catalog("en")
    japanese = Ibex::Messages.catalog("ja")

    assert_equal english.keys.sort, japanese.keys.sort
    english.each_key do |id|
      placeholders = english.fetch(id).scan(/%{([^}]+)}/).flatten.sort
      assert_equal placeholders, japanese.fetch(id).scan(/%{([^}]+)}/).flatten.sort, id
    end
  end

  def test_every_message_id_used_by_code_exists_in_every_catalog
    root = File.expand_path("../lib", __dir__)
    literal_ids = Dir.glob(File.join(root, "**/*.rb")).flat_map do |path|
      File.binread(path).scan(BUILT_IN_ID_PATTERN).flatten
    end
    dynamic_frontend_ids = %w[
      diagnostic.frontend.lexical_error
      diagnostic.frontend.syntax_error
      diagnostic.frontend.resolution_error
    ]
    used = (literal_ids + dynamic_frontend_ids).uniq.sort

    Ibex::Messages::LANGUAGES.each do |language|
      assert_empty used - Ibex::Messages.catalog(language).keys, language
    end
  end

  def test_unknown_or_region_language_falls_back_without_a_warning
    assert_equal "ja", Ibex::Messages.language("ja_JP.UTF-8")
    assert_equal "en", Ibex::Messages.language("fr")
    assert_equal "problem", Ibex::Messages.translate("cli.error", language: "fr", detail: "problem")
  end

  def test_cli_lang_localizes_warnings_without_using_user_error_ids
    Tempfile.create(["messages", ".y"]) do |grammar|
      grammar.write("class Messages\ntoken UNUSED\nrule\nstart: %empty\nend\n")
      grammar.flush
      errors = StringIO.new

      status = Ibex::CLI.start(
        ["--lang=ja", "--mode=extended", "--warnings=all", "--check-only", grammar.path],
        stdout: StringIO.new, stderr: errors
      )

      assert_equal 0, status
      assert_includes errors.string, "警告"
      assert_includes errors.string, "未使用の終端記号 UNUSED"
      refute_match(/\bE00\d\d\b/, errors.string)
    end
  end

  def test_diagnose_localizes_text_and_json_but_keeps_stable_codes
    Tempfile.create(["diagnostic", ".y"]) do |grammar|
      grammar.write("class Broken\nrule\nstart TOKEN\nend\n")
      grammar.flush

      text = StringIO.new
      status = Ibex::CLI.start(
        ["diagnose", "--lang=ja", grammar.path], stdout: text, stderr: StringIO.new
      )
      assert_equal 1, status
      assert_includes text.string, "構文エラー"

      json = StringIO.new
      status = Ibex::CLI.start(
        ["diagnose", "--lang=ja", "--format=json", grammar.path],
        stdout: json, stderr: StringIO.new
      )
      diagnostic = JSON.parse(json.string).fetch("diagnostics").fetch(0)
      assert_equal 1, status
      assert_equal "frontend.syntax_error", diagnostic.fetch("code")
      assert_includes diagnostic.fetch("message"), "構文エラー"
    end
  end

  def test_environment_selects_language_and_explicit_option_wins
    previous = ENV.fetch("IBEX_LANG", nil)
    ENV["IBEX_LANG"] = "ja"
    japanese = StringIO.new
    english = StringIO.new

    Ibex::CLI.start(["missing.y"], stdout: StringIO.new, stderr: japanese)
    Ibex::CLI.start(["--lang=en", "missing.y"], stdout: StringIO.new, stderr: english)

    assert_includes japanese.string, "エラー:"
    refute_includes english.string, "エラー:"
  ensure
    previous ? ENV["IBEX_LANG"] = previous : ENV.delete("IBEX_LANG")
  end
end
