# frozen_string_literal: true

require_relative "phase_guard"

module Ibex
  module Normalize
    # Compatibility name for callers that required the old internal class.
    Context = PhaseGuard #: singleton(PhaseGuard)
  end
end
