# frozen_string_literal: true

module BenchmarkSupport
  # Deterministic descriptive and bootstrap statistics for process-isolated samples.
  module ComparisonStatistics
    CONFIDENCE_LEVEL = 0.95

    module_function

    def describe(values)
      {
        median: rounded(median(values)),
        mad: rounded(median_absolute_deviation(values)),
        minimum: rounded(values.min),
        maximum: rounded(values.max)
      }
    end

    def compare(ibex_values, racc_values, seed:, samples:)
      ratios = bootstrap_ratios(ibex_values, racc_values, seed: seed, samples: samples)
      {
        ibex: describe(ibex_values),
        racc: describe(racc_values),
        ibex_to_racc_ratio: rounded(median(ibex_values) / median(racc_values)),
        bootstrap_95_percent: {
          lower: rounded(percentile(ratios, 0.025)),
          upper: rounded(percentile(ratios, 0.975)),
          samples: samples,
          seed: seed
        },
        target_met: percentile(ratios, 0.975) <= 1.0
      }
    end

    def median(values)
      raise ArgumentError, "sample must not be empty" if values.empty?

      sorted = values.sort
      middle = sorted.length / 2
      return sorted.fetch(middle).to_f if sorted.length.odd?

      (sorted.fetch(middle - 1) + sorted.fetch(middle)) / 2.0
    end

    def median_absolute_deviation(values)
      center = median(values)
      median(values.map { |value| (value - center).abs })
    end

    def bootstrap_ratios(ibex_values, racc_values, seed:, samples:)
      random = Random.new(seed)
      Array.new(samples) do
        ibex_sample = Array.new(ibex_values.length) { ibex_values.fetch(random.rand(ibex_values.length)) }
        racc_sample = Array.new(racc_values.length) { racc_values.fetch(random.rand(racc_values.length)) }
        median(ibex_sample) / median(racc_sample)
      end.sort
    end

    def percentile(sorted, fraction)
      sorted.fetch((fraction * (sorted.length - 1)).round)
    end

    def rounded(value)
      value.round(6)
    end
  end
end
