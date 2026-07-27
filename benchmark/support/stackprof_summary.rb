# frozen_string_literal: true

require "digest"

module BenchmarkSupport
  # Projects a StackProf raw dump into a small, stable diagnostic summary.
  module StackprofSummary
    module_function

    def build(path, top:)
      profile = Marshal.load(File.binread(path)) # rubocop:disable Security/MarshalLoad
      frames = profile.fetch(:frames, {}).values
      {
        "raw_profile_sha256" => Digest::SHA256.file(path).hexdigest,
        "samples" => profile.fetch(:samples, 0),
        "missed_samples" => profile.fetch(:missed_samples, 0),
        "gc_samples" => profile.fetch(:gc_samples, 0),
        "top_frames" => frames.sort_by { |frame| [-frame.fetch(:total_samples, 0), frame.fetch(:name, "")] }
                              .first(top)
                              .map { |frame| frame_summary(frame) }
      }
    end

    def frame_summary(frame)
      {
        "name" => frame.fetch(:name, "(unknown)"),
        "file" => frame[:file],
        "line" => frame[:line],
        "total_samples" => frame.fetch(:total_samples, 0),
        "self_samples" => frame.fetch(:samples, 0)
      }
    end
    private_class_method :frame_summary
  end
end
