# frozen_string_literal: true

module Ibex
  # Recovery declaration extraction and post-interning symbol validation.
  module NormalizeRecoveryDeclarations
    private

    # @rbs (Frontend::AST::Start | Frontend::AST::Recovery | Frontend::AST::OnErrorReduce declaration) -> void
    def read_parser_control_declaration(declaration)
      # @type self: Normalizer
      case declaration
      when Frontend::AST::Start then read_start_declaration(declaration)
      when Frontend::AST::Recovery then read_recovery_declaration(declaration)
      when Frontend::AST::OnErrorReduce then read_on_error_reduce_declaration(declaration)
      end
    end

    # @rbs (Frontend::AST::Recovery declaration) -> void
    def read_recovery_declaration(declaration)
      # @type self: Normalizer
      fail_at(declaration.loc, "duplicate %recover declaration") if @recovery_sync_location
      fail_at(declaration.loc, "%recover sync requires at least one token") if declaration.sync_tokens.empty?
      unless declaration.sync_tokens.uniq.length == declaration.sync_tokens.length
        fail_at(declaration.loc, "%recover sync tokens must be unique")
      end

      @recovery_sync_tokens = declaration.sync_tokens
      @recovery_sync_location = declaration.loc
    end

    # @rbs (Frontend::AST::OnErrorReduce declaration) -> void
    def read_on_error_reduce_declaration(declaration)
      # @type self: Normalizer
      fail_at(declaration.loc, "%on_error_reduce requires at least one nonterminal") if declaration.names.empty?
      declaration.names.each do |name|
        fail_at(declaration.loc, "duplicate %on_error_reduce symbol #{name}") if
          @on_error_reduce_locations.key?(name)

        @on_error_reduce_locations[name] = declaration.loc
      end
      @on_error_reduce_groups << declaration.names
    end

    # @rbs () -> void
    def validate_recovery_declarations
      # @type self: Normalizer
      @recovery_sync_tokens.each do |name|
        definition = @symbols_by_name[name]
        unless definition&.terminal? && definition.name != "error"
          fail_at(@recovery_sync_location || @ast.loc, "%recover sync references nonterminal or missing token #{name}")
        end
      end
      @on_error_reduce_groups.flatten.each do |name|
        definition = @symbols_by_name[name]
        unless definition&.nonterminal?
          location = @on_error_reduce_locations.fetch(name)
          fail_at(location, "%on_error_reduce references terminal or missing nonterminal #{name}")
        end
      end
    end
  end
end
