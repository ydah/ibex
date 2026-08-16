# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"

class ImpactBaselineTest < Minitest::Test
  def test_missing_baseline_is_empty_and_write_is_sorted
    Dir.mktmpdir("ibex-impact-baseline") do |directory|
      path = File.join(directory, "baseline.json")
      baseline = Ibex::Impact::Baseline.new(path)

      assert_empty baseline.conflicts
      baseline.write(%w[zeta alpha alpha])

      assert_equal %w[alpha zeta], baseline.conflicts
    end
  end

  def test_invalid_baseline_documents_are_rejected
    Dir.mktmpdir("ibex-impact-baseline") do |directory|
      path = File.join(directory, "baseline.json")
      baseline = Ibex::Impact::Baseline.new(path)

      ["[]", "null", "{}", '{"schema_version":1,"conflicts":null}',
       '{"schema_version":1,"conflicts":[1]}'].each do |document|
        File.binwrite(path, document)
        error = assert_raises(Ibex::Error) { baseline.conflicts }
        assert_includes error.message, "invalid impact baseline"
      end
    end
  end
end
