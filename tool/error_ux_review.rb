# frozen_string_literal: true

require_relative "quality/error_ux_review"

module ErrorUXReviewCLI
  module_function

  def run(arguments)
    review = Ibex::Quality::ErrorUXReview.new
    if arguments.length == 2 && arguments.first == "template"
      path = arguments.last
      review.write_template!(path)
      puts "wrote draft #{File.expand_path(path)}"
      return 0
    end

    case arguments
    when ["check"]
      review.verify_kit!
      puts "error UX independent review kit is ready"
    when ["status"]
      puts review.status_line
    when ["release"]
      puts review.release_gate!
    else
      raise ArgumentError,
            "usage: ruby tool/error_ux_review.rb check|status|release|template OUTPUT.json"
    end
    0
  rescue ArgumentError, RuntimeError => e
    warn e.message
    1
  end
end

exit(ErrorUXReviewCLI.run(ARGV)) if $PROGRAM_NAME == __FILE__
