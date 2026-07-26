# frozen_string_literal: true

module Ibex
  # Static validation and collection for rules eliminated by inline expansion.
  module NormalizeInlineValidation
    private

    # @rbs () -> void
    def gather_inline_rules
      # @type self: Normalizer
      @inline_rule_names = Set.new #: Set[String]
      markings = {} #: Hash[String, bool]
      @ast.rules.each do |rule|
        previous = markings[rule.lhs]
        if !previous.nil? && previous != rule.inline
          fail_at(rule.loc, "rule #{rule.lhs} has both inline and ordinary definitions")
        end
        markings[rule.lhs] = rule.inline
        @inline_rule_names << rule.lhs if rule.inline
      end
      validate_inline_terminal_collisions
      validate_inline_start
      validate_inline_cycles
    end

    # @rbs () -> void
    def validate_inline_terminal_collisions
      # @type self: Normalizer
      @ast.rules.each do |rule|
        next unless rule.inline
        next unless @declared_tokens.key?(rule.lhs) || @precedence.key?(rule.lhs)

        fail_at(rule.loc, "inline rule #{rule.lhs} collides with terminal #{rule.lhs}")
      end
    end

    # @rbs () -> void
    def validate_inline_start
      # @type self: Normalizer
      inline_start = @explicit_starts&.find { |name| @inline_rule_names.include?(name) }
      return unless inline_start

      fail_at(@start_location || @ast.loc, "inline rule #{inline_start} cannot be the start symbol")
    end

    # @rbs () -> void
    def validate_inline_cycles
      # @type self: Normalizer
      names = @ast.rules.to_set(&:lhs)
      liveness = parameter_formal_liveness
      graph = Hash.new { |hash, name| hash[name] = [] } #: Hash[String, Array[[String, Frontend::Location]]]
      @ast.rules.each do |rule|
        rule.alternatives.each do |alternative|
          alternative.items.each do |item|
            collect_inline_edges(item, rule.parameters, names, graph[rule.lhs], liveness)
          end
        end
      end
      states = {} #: Hash[String, Symbol]
      names.each { |name| visit_inline_cycle(name, graph, states) unless states.key?(name) }
    end

    # A formal is live for cycle analysis only when substituting its actual can
    # introduce a grammar reference. Calls propagate liveness through their
    # callee's live positions until the finite formal set reaches a fixed point.
    # @rbs () -> Hash[String, Set[Integer]]
    def parameter_formal_liveness
      # @type self: Normalizer
      liveness = @parameter_formals.to_h { |name, _formals| [name, Set.new] } #: Hash[String, Set[Integer]]
      loop do
        changed = false
        @parameter_templates.each do |name, rules|
          formals = @parameter_formals.fetch(name)
          found = Set.new #: Set[Integer]
          rules.each do |rule|
            rule.alternatives.each do |alternative|
              alternative.items.each { |item| collect_live_formals(item, formals, liveness, found) }
            end
          end
          additions = found - liveness.fetch(name)
          next if additions.empty?

          liveness.fetch(name).merge(additions)
          changed = true
        end
        return liveness unless changed
      end
    end

    # @rbs (Frontend::AST::item item, Array[String] formals,
    #   Hash[String, Set[Integer]] liveness, Set[Integer] found) -> void
    def collect_live_formals(item, formals, liveness, found)
      # @type self: Normalizer
      case item
      when Frontend::AST::SymbolReference
        index = formals.index(item.name)
        found << index if index
      when Frontend::AST::ParameterizedReference
        liveness.fetch(item.name, Set.new).each do |index|
          collect_live_formals(item.arguments.fetch(index), formals, liveness, found)
        end
      when Frontend::AST::Group
        item.alternatives.flatten.each { |child| collect_live_formals(child, formals, liveness, found) }
      when Frontend::AST::Optional, Frontend::AST::Star, Frontend::AST::Plus
        collect_live_formals(item.item, formals, liveness, found)
      when Frontend::AST::SeparatedList
        collect_live_formals(item.item, formals, liveness, found)
        collect_live_formals(item.separator, formals, liveness, found)
      end
    end

    # Structural AST traversal necessarily branches once for each public item shape.
    # rubocop:disable Metrics/CyclomaticComplexity
    # @rbs (Frontend::AST::item item, Array[String] formals, Set[String] names,
    #   Array[[String, Frontend::Location]] edges, Hash[String, Set[Integer]] liveness) -> void
    def collect_inline_edges(item, formals, names, edges, liveness)
      # @type self: Normalizer
      case item
      when Frontend::AST::SymbolReference
        edges << [item.name, item.loc] if !formals.include?(item.name) && names.include?(item.name)
      when Frontend::AST::ParameterizedReference
        edges << [item.name, item.loc] if names.include?(item.name)
        liveness.fetch(item.name, Set.new).each do |index|
          collect_inline_edges(item.arguments.fetch(index), formals, names, edges, liveness)
        end
      when Frontend::AST::Group
        item.alternatives.flatten.each do |child|
          collect_inline_edges(child, formals, names, edges, liveness)
        end
      when Frontend::AST::Optional, Frontend::AST::Star, Frontend::AST::Plus
        collect_inline_edges(item.item, formals, names, edges, liveness)
      when Frontend::AST::SeparatedList
        collect_inline_edges(item.item, formals, names, edges, liveness)
        collect_inline_edges(item.separator, formals, names, edges, liveness)
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity

    # @rbs (String name, Hash[String, Array[[String, Frontend::Location]]] graph,
    #   Hash[String, Symbol] states) -> void
    def visit_inline_cycle(name, graph, states)
      # @type self: Normalizer
      states[name] = :visiting
      path = [name] #: Array[String]
      positions = { name => 0 } #: Hash[String, Integer]
      worklist = [[name, 0]] #: Array[[String, Integer]]
      until worklist.empty?
        current, edge_index = worklist.fetch(-1)
        edges = graph[current]
        if edge_index >= edges.length
          worklist.pop
          positions.delete(path.pop || raise(Ibex::Error, "internal inline cycle path underflow"))
          states[current] = :visited
          next
        end

        worklist[-1] = [current, edge_index + 1]
        target, location = edges.fetch(edge_index)
        if states[target] == :visiting
          cycle = path.drop(positions.fetch(target))
          next unless cycle.any? { |entry| @inline_rule_names.include?(entry) }

          fail_at(location, "inline expansion cycle: #{(cycle + [target]).join(' -> ')}")
        end
        next if states.key?(target)

        states[target] = :visiting
        positions[target] = path.length
        path << target
        worklist << [target, 0]
      end
    end
  end
end
