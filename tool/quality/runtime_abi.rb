# frozen_string_literal: true

require_relative "runtime_abi/contract_verifier"
require_relative "runtime_abi/assessment"

module Ibex
  module Quality
    # Verifies the checked-in contract and an explicitly supplied PR event.
    class RuntimeABI
      ROOT = File.expand_path("../..", __dir__)

      def initialize(root: ROOT, event_path: nil, event_name: nil, changed_paths: nil)
        @root = File.expand_path(root)
        @event_path = event_path
        @event_name = event_name
        @changed_paths = changed_paths
      end

      def verify!
        contracts = RuntimeABIContractVerifier.new(root: @root).verify!
        RuntimeABIAssessment.new(
          root: @root, contract: contracts.abi_contract, test_contract: contracts.test_contract,
          event_path: @event_path, event_name: @event_name, changed_paths: @changed_paths
        ).verify!
      end
    end
  end
end
