# frozen_string_literal: true
# rbs_inline: enabled

require "json"

module Ibex
  # Immutable built-in diagnostic translations, separate from user E00xx
  # sentence-keyed parser error catalogs.
  module Messages
    ROOT = File.expand_path("messages", __dir__ || raise("message catalog directory is unavailable")) #: String
    LANGUAGES = %w[en ja].freeze #: Array[String]

    # @rbs (String? requested) -> String
    def language(requested)
      candidate = requested.to_s.downcase.tr("_", "-").split("-").first
      LANGUAGES.include?(candidate) ? candidate : "en"
    end
    module_function :language

    # @rbs (String id, ?language: String, **Object? values) -> String
    def translate(id, language: "en", **values)
      selected = catalog(self.language(language))
      template = selected[id] || catalog("en").fetch(id) do
        raise Ibex::Error, "(messages):1:1: unknown built-in message id #{id.inspect}"
      end
      template % values.transform_keys(&:to_sym)
    rescue KeyError => e
      raise Ibex::Error, "(messages):1:1: missing interpolation for #{id.inspect}: #{e.message}"
    end
    module_function :translate

    # @rbs (String id) -> bool
    def known?(id)
      catalog("en").key?(id)
    end
    module_function :known?

    # @rbs (String language) -> Hash[String, String]
    def catalog(language)
      @catalogs ||= {} #: Hash[String, Hash[String, String]]
      @catalogs[language] ||= load_catalog(language)
    end
    module_function :catalog

    # @rbs (String language) -> Hash[String, String]
    def load_catalog(language)
      path = File.join(ROOT, "#{language}.yml")
      document = JSON.parse(File.binread(path))
      unless document.is_a?(Hash) && document["version"] == 1 && document["messages"].is_a?(Hash)
        raise Ibex::Error, "#{path}:1:1: invalid built-in message catalog"
      end

      document.fetch("messages").to_h do |id, value|
        unless id.is_a?(String) && value.is_a?(String)
          raise Ibex::Error, "#{path}:1:1: message ids and templates must be strings"
        end

        [id.freeze, value.freeze]
      end.freeze
    rescue Errno::ENOENT => e
      raise Ibex::Error, "#{path}:1:1: cannot read built-in message catalog: #{e.message}"
    rescue JSON::ParserError => e
      raise Ibex::Error, "#{path}:1:1: invalid JSON-compatible YAML: #{e.message}"
    end
    module_function :load_catalog
    private_class_method :load_catalog
  end
end
