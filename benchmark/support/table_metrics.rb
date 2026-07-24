# frozen_string_literal: true

module BenchmarkSupport
  # Produces a stable table representation and its physical storage counts.
  class TableMetrics
    def initialize(tables, kind)
      @tables = tables
      @kind = kind
    end

    def result
      serialized = JSON.generate(document)
      { document: serialized, summary: cell_counts.merge(bytes: serialized.bytesize) }
    end

    def document
      actions = @kind == :plain ? plain_rows(@tables.actions) : compact_rows(@tables.actions)
      gotos = @kind == :plain ? plain_rows(@tables.gotos) : compact_rows(@tables.gotos)
      {
        kind: @kind.to_s,
        actions: actions,
        gotos: gotos,
        default_actions: canonical(@tables.default_actions)
      }
    end

    private

    def cell_counts
      action = @kind == :plain ? @tables.actions.sum(&:length) : compact_cell_count(@tables.actions)
      goto = @kind == :plain ? @tables.gotos.sum(&:length) : compact_cell_count(@tables.gotos)
      default = @tables.default_actions.length
      { action_cells: action, goto_cells: goto, default_cells: default, total_cells: action + goto + default }
    end

    def compact_cell_count(table)
      table.offsets.length + table.values.length + table.checks.length
    end

    def plain_rows(rows)
      rows.map { |row| row.sort.map { |key, value| [key, canonical(value)] } }
    end

    def compact_rows(table)
      {
        offsets: table.offsets,
        values: canonical(table.values),
        checks: table.checks,
        row_count: table.row_count
      }
    end

    def canonical(value)
      case value
      when Array then value.map { |item| canonical(item) }
      when Hash then value.sort_by { |key, _| key.to_s }.to_h { |key, item| [key.to_s, canonical(item)] }
      when Symbol then value.to_s
      else value
      end
    end
  end
end
