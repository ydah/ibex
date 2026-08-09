# frozen_string_literal: true
# rbs_inline: enabled

require "digest"
require "json"

module Ibex
  # Deterministic description of one published parser generation.
  module GenerationManifest
    # @rbs!
    #   type json_value = String | Integer | Float | bool | nil | Array[json_value] | Hash[String, json_value]

    SCHEMA_VERSION = 1 #: Integer
    IDENTIFIER = "generation" #: String
    ROOT_KEYS = %w[ibex_manifest schema_version input options artifacts].freeze #: Array[String]
    INPUT_KEYS = %w[root sha256 files].freeze #: Array[String]
    FILE_KEYS = %w[path sha256 bytesize].freeze #: Array[String]
    ARTIFACT_KEYS = %w[kind path sha256 bytesize].freeze #: Array[String]

    module_function

    # @rbs (ArtifactSet artifacts, source_records: Array[GenerationInput], options: Hash[String, Object?]) -> String
    def render(artifacts, source_records:, options:)
      files = source_records.map(&:to_h)
      document = {
        "ibex_manifest" => IDENTIFIER,
        "schema_version" => SCHEMA_VERSION,
        "input" => {
          "root" => files.fetch(0).fetch("path"),
          "sha256" => input_digest(files),
          "files" => files
        },
        "options" => sorted_hash(options),
        "artifacts" => artifacts.map { |artifact| artifact_entry(artifact) }
      }
      "#{JSON.pretty_generate(document)}\n"
    end

    # Validate the manifest shape and, by default, every published artifact digest.
    # @rbs (String source, ?verify_artifacts: bool) -> Hash[String, json_value]
    def validate(source, verify_artifacts: true)
      document = JSON.parse(source) #: Object?
      validate_document(document)
      document_hash = document #: Hash[String, json_value]
      artifacts = document_hash.fetch("artifacts") #: Array[Object?]
      verify_entries(artifacts) if verify_artifacts
      document_hash
    rescue JSON::ParserError, KeyError, TypeError, ArgumentError => e
      raise Ibex::Error, "(manifest):1:1: invalid generation manifest: #{e.message}"
    end

    # @rbs (String path, ?verify_artifacts: bool) -> Hash[String, json_value]
    def validate_file(path, verify_artifacts: true)
      validate(File.binread(path), verify_artifacts: verify_artifacts)
    rescue SystemCallError, ArgumentError => e
      raise Ibex::Error, "#{path}:1:1: cannot read generation manifest: #{e.message}"
    end

    # @rbs (Artifact artifact) -> Hash[String, json_value]
    def artifact_entry(artifact)
      {
        "kind" => artifact.kind.to_s,
        "path" => File.expand_path(artifact.path),
        "sha256" => Digest::SHA256.hexdigest(artifact.content),
        "bytesize" => artifact.content.bytesize
      }
    end
    private_class_method :artifact_entry

    # @rbs (Array[Hash[String, json_value]] files) -> String
    def input_digest(files)
      digest = Digest::SHA256.new
      files.each do |entry|
        path = entry.fetch("path") # @type var path: String
        sha256 = entry.fetch("sha256") # @type var sha256: String
        bytesize = entry.fetch("bytesize") # @type var bytesize: Integer
        digest << path << "\0" << sha256 << "\0" << bytesize.to_s << "\0"
      end
      digest.hexdigest
    end
    private_class_method :input_digest

    # @rbs (Hash[String, Object?] value) -> Hash[String, Object?]
    def sorted_hash(value)
      value.keys.sort.to_h do |key|
        child = value.fetch(key)
        normalized = child.is_a?(Hash) ? sorted_hash(child) : child
        [key, normalized]
      end
    end
    private_class_method :sorted_hash

    # @rbs (Object? document) -> void
    def validate_document(document)
      raise TypeError, "document must be an object" unless document.is_a?(Hash)

      exact_keys!(document, ROOT_KEYS, "document")
      validate_identity(document)
      validate_input(document.fetch("input"))
      artifacts = document.fetch("artifacts")
      raise TypeError, "options must be an object" unless document.fetch("options").is_a?(Hash)
      raise TypeError, "artifacts must be an array" unless artifacts.is_a?(Array)
      raise TypeError, "artifacts must not be empty" if artifacts.empty?

      validate_entries(artifacts, "artifact", require_kind: true)
    end
    private_class_method :validate_document

    # @rbs (Hash[Object?, Object?] document) -> void
    def validate_identity(document)
      raise TypeError, "unsupported manifest identifier" unless document["ibex_manifest"] == IDENTIFIER
      raise TypeError, "unsupported schema_version" unless document["schema_version"] == SCHEMA_VERSION
    end
    private_class_method :validate_identity

    # @rbs (Object? input) -> void
    def validate_input(input)
      raise TypeError, "input must be an object" unless input.is_a?(Hash)

      exact_keys!(input, INPUT_KEYS, "input")

      files = input.fetch("files")
      raise TypeError, "input files must be a non-empty array" unless files.is_a?(Array) && !files.empty?

      validate_entries(files, "input file")
      expected = input_digest(files)
      root = input.fetch("root")
      raise TypeError, "input root must be a non-empty string" unless root.is_a?(String) && !root.empty?
      raise TypeError, "input digest mismatch" unless input.fetch("sha256") == expected
      raise TypeError, "input root mismatch" unless root == files.fetch(0).fetch("path")
    end
    private_class_method :validate_input

    # @rbs (Array[Object?] entries, String label, ?require_kind: bool) -> void
    def validate_entries(entries, label, require_kind: false)
      entries.each { |entry| validate_entry(entry, label, require_kind) }
    end
    private_class_method :validate_entries

    # @rbs (Object? entry, String label, bool require_kind) -> void
    def validate_entry(entry, label, require_kind)
      raise TypeError, "#{label} must be an object" unless entry.is_a?(Hash)

      exact_keys!(entry, require_kind ? ARTIFACT_KEYS : FILE_KEYS, label)
      validate_path(entry.fetch("path"), label)
      validate_kind(entry.fetch("kind"), label) if require_kind
      validate_digest(entry.fetch("sha256"), label)
      bytesize = entry.fetch("bytesize")
      return if bytesize.is_a?(Integer) && bytesize >= 0

      raise TypeError, "#{label} bytesize must be non-negative"
    end
    private_class_method :validate_entry

    # @rbs (Object? path, String label) -> void
    def validate_path(path, label)
      raise TypeError, "#{label} path must be a non-empty string" unless path.is_a?(String) && !path.empty?
      return unless path.include?("\0") || path.match?(/[[:cntrl:]]/)

      raise TypeError, "#{label} path must not contain control characters"
    end
    private_class_method :validate_path

    # @rbs (Object? kind, String label) -> void
    def validate_kind(kind, label)
      return if kind.is_a?(String) && !kind.empty?

      raise TypeError, "#{label} kind must be a non-empty string"
    end
    private_class_method :validate_kind

    # @rbs (Object? digest, String label) -> void
    def validate_digest(digest, label)
      return if digest.is_a?(String) && digest.match?(/\A[0-9a-f]{64}\z/)

      raise TypeError, "#{label} digest must be SHA-256"
    end
    private_class_method :validate_digest

    # @rbs (Hash[Object?, Object?] value, Array[String] expected, String label) -> void
    def exact_keys!(value, expected, label)
      keys = value.keys
      raise TypeError, "#{label} keys must be strings" unless keys.all?(String)

      extras = keys - expected
      missing = expected - keys
      raise TypeError, "#{label} has unknown property #{extras.fetch(0)}" unless extras.empty?
      raise KeyError, "#{label} is missing #{missing.fetch(0)}" unless missing.empty?
    end
    private_class_method :exact_keys!

    # @rbs (Array[Object?] entries) -> void
    def verify_entries(entries)
      entries.each do |entry|
        entry_hash = entry #: Hash[String, json_value]
        path = entry_hash.fetch("path") #: String
        source = File.binread(path)
        bytesize = entry_hash.fetch("bytesize") #: Integer
        sha256 = entry_hash.fetch("sha256") #: String
        raise TypeError, "artifact bytesize mismatch for #{path}" unless source.bytesize == bytesize
        raise TypeError, "artifact digest mismatch for #{path}" unless
          Digest::SHA256.hexdigest(source) == sha256
      end
    rescue SystemCallError => e
      raise TypeError, "cannot read artifact: #{e.message}"
    end
    private_class_method :verify_entries
  end
end
