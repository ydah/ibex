# frozen_string_literal: true

require_relative "runtime_abi/contract_verifier"
require_relative "runtime_abi/assessment"

module Ibex
  module Quality
    # Verifies the checked-in runtime ABI policy and, on pull requests, the
    # structured assessment for runtime-facing changes.
    class RuntimeABI
      ROOT = File.expand_path("../..", __dir__)

      def initialize(root: ROOT, event_path: ENV.fetch("GITHUB_EVENT_PATH", nil),
                     event_name: ENV.fetch("GITHUB_EVENT_NAME", nil), changed_paths: nil)
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
