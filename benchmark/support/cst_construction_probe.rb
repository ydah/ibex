# frozen_string_literal: true

module CSTConstructionProbe
  module_function

  def measure(cst_parser, input)
    legacy = CSTRecoveryBenchmark.legacy_parser(cst_parser)
    legacy_counts = construction_counts(legacy, input, suppress_legacy_warning: true)
    red_green_counts = construction_counts(cst_parser, input)
    legacy_total = legacy_counts.fetch(:node_and_token_constructions)
    red_green_total = red_green_counts.fetch(:node_and_token_constructions)
    {
      legacy_cst: legacy_counts,
      red_green_cst: red_green_counts,
      reduction_ratio: 1.0 - red_green_total.fdiv(legacy_total)
    }
  end

  def construction_counts(parser_class, input, suppress_legacy_warning: false)
    classes = {
      Ibex::Runtime::CST::Node => :nodes,
      Ibex::Runtime::CST::Token => :tokens,
      Ibex::Runtime::CST::GreenNode => :nodes,
      Ibex::Runtime::CST::GreenToken => :tokens
    }
    counts = { nodes: 0, tokens: 0 }
    trace = TracePoint.new(:call) do |point|
      name = classes[point.defined_class]
      counts[name] += 1 if name && point.method_id == :initialize
    end
    trace.enable do
      CSTBenchmark.parse_once(parser_class, input, suppress_legacy_warning: suppress_legacy_warning)
    end
    counts.merge(node_and_token_constructions: counts.fetch(:nodes) + counts.fetch(:tokens))
  end
end
