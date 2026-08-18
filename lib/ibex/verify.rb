# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Verify
  end
end

require_relative "analysis"
require_relative "tables"
require_relative "verify/reference_collection"
require_relative "verify/result"
require_relative "verify/verifier"
require_relative "verify/action_correspondence"
require_relative "verify/language_witness"
