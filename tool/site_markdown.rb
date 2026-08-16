# frozen_string_literal: true

require "cgi"
require "pathname"

module Ibex
  module SiteMarkdown
    Document = Struct.new(:title, :description, :body, keyword_init: true)

    class Renderer
      def initialize(markdown, current_slug:, current_document_path: nil, document_slugs: {}, asset_hrefs: {})
        @markdown = markdown
        @current_slug = current_slug
        @current_document_path = current_document_path
        @document_slugs = document_slugs
        @asset_hrefs = asset_hrefs
        @headings = Hash.new(0)
      end

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity -- the dependency-free renderer keeps Markdown constructs auditable in one parser.
      def render
        lines = @markdown.lines.map(&:chomp)
        blocks = []
        index = 0
        while index < lines.length
          line = lines[index]
          if line.empty? || line.match?(/\A\s*<!--.*-->\s*\z/)
            index += 1
            next
          end

          if line.start_with?("```") || line.start_with?("~~~")
            fence = line[0, 3]
            language = line.delete_prefix(fence).strip
            code = []
            index += 1
            while index < lines.length && !lines[index].start_with?(fence)
              code << lines[index]
              index += 1
            end
            index += 1 if index < lines.length
            class_name = language.empty? ? "" : %( class="language-#{escape_attribute(language)}")
            blocks << %(<pre><code#{class_name}>#{CGI.escapeHTML(code.join("\n"))}</code></pre>)
            next
          end

          if (heading = line.match(/\A(#+)\s+(.+?)\s*#*\z/)) && heading[1].length <= 6
            level = heading[1].length
            text = heading[2]
            id = heading_id(text)
            blocks << %(<h#{level} id="#{escape_attribute(id)}">#{inline(text)}</h#{level}>)
            index += 1
            next
          end

          if line.match?(/\A\s*[-*_](?:\s*[-*_]){2,}\s*\z/)
            blocks << "<hr>"
            index += 1
            next
          end

          if line.start_with?("> ") || line == ">"
            quote = []
            while index < lines.length && (lines[index].start_with?("> ") || lines[index] == ">")
              quote << lines[index].sub(/\A> ?/, "")
              index += 1
            end
            blocks << %(<blockquote>#{render_fragment(quote)}</blockquote>)
            next
          end

          if line.match?(/\A\s*[-*+]\s+/)
            items = []
            while index < lines.length && lines[index].match?(/\A\s*[-*+]\s+/)
              items << lines[index].sub(/\A\s*[-*+]\s+/, "")
              index += 1
            end
            blocks << "<ul>#{items.map { |item| "<li>#{inline(item)}</li>" }.join}</ul>"
            next
          end

          if line.match?(/\A\s*\d+[.)]\s+/)
            items = []
            while index < lines.length && lines[index].match?(/\A\s*\d+[.)]\s+/)
              items << lines[index].sub(/\A\s*\d+[.)]\s+/, "")
              index += 1
            end
            blocks << "<ol>#{items.map { |item| "<li>#{inline(item)}</li>" }.join}</ol>"
            next
          end

          if line.include?("|") && index + 1 < lines.length && lines[index + 1].match?(/\A\s*\|?\s*:?-{3,}/)
            header = split_table_row(line)
            index += 2
            rows = []
            while index < lines.length && lines[index].include?("|") && !lines[index].empty?
              rows << split_table_row(lines[index])
              index += 1
            end
            thead = header.map { |cell| "<th>#{inline(cell)}</th>" }.join
            tbody = rows.map do |row|
              "<tr>#{row.map { |cell| "<td>#{inline(cell)}</td>" }.join}</tr>"
            end.join
            blocks << %(<div class="table-wrap"><table><thead><tr>#{thead}</tr></thead>
              <tbody>#{tbody}</tbody></table></div>)
            next
          end

          paragraph = [line]
          index += 1
          while index < lines.length && !lines[index].empty? && !block_start?(lines[index])
            paragraph << lines[index]
            index += 1
          end
          blocks << "<p>#{inline(paragraph.join(' '))}</p>"
        end
        blocks.join("\n")
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

      private

      def render_fragment(lines)
        self.class.new(
          lines.join("\n"),
          current_slug: @current_slug,
          current_document_path: @current_document_path,
          document_slugs: @document_slugs,
          asset_hrefs: @asset_hrefs
        ).render
      end

      def block_start?(line)
        line.start_with?("```") || line.start_with?("~~~") ||
          line.match?(/\A(?:#+\s+|\s*[-*+]\s+|\s*\d+[.)]\s+|> ?|\s*[-*_](?:\s*[-*_]){2,}\s*)/)
      end

      def split_table_row(line)
        line.strip.sub(/\A\|/, "").sub(/\|\z/, "").split("|").map(&:strip)
      end

      def heading_id(text)
        base = text.downcase.gsub(/[`*_]/, "").gsub(/[^\p{Alnum}\s-]/, "").strip.gsub(/\s+/, "-")
        base = "section" if base.empty?
        @headings[base] += 1
        @headings[base] == 1 ? base : "#{base}-#{@headings[base]}"
      end

      def inline(text)
        escaped = CGI.escapeHTML(text)
        escaped = escaped.gsub(/`([^`]+)`/) { "<code>#{Regexp.last_match(1)}</code>" }
        escaped = escaped.gsub(/\*\*([^*]+)\*\*/) { "<strong>#{Regexp.last_match(1)}</strong>" }
        escaped = escaped.gsub(/\[([^\]]+)\]\(([^)]+)\)/) do
          label = Regexp.last_match(1)
          href = normalize_href(Regexp.last_match(2))
          %(<a href="#{escape_attribute(href)}">#{label}</a>)
        end
        escaped.gsub(%r{(?<!["=])(https?://[^\s<]+)}) do
          href = Regexp.last_match(1).sub(/[.,]\z/, "")
          %(<a href="#{escape_attribute(href)}">#{href}</a>)
        end
      end

      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- link policy is deliberately fail-closed and explicit.
      def normalize_href(href)
        return href if href.start_with?("http:", "https:", "#")

        path, fragment = href.split("#", 2)
        target = documentation_target(path)
        if (slug = @document_slugs[target])
          path = "../#{slug}/"
        elsif (asset = @asset_hrefs[target])
          path = "../#{asset}"
        elsif path.end_with?(".md")
          repository_path = target&.start_with?("docs/") ? target : "docs/#{target || path.delete_prefix('../')}"
          path = github_href(repository_path)
        elsif path.start_with?("../")
          repository_path = path.sub(%r{\A(?:\.\./)+}, "")
          if repository_path.match?(%r{\A(?:schema|test|tool|examples|benchmark|gallery)/})
            path = github_href(repository_path)
          end
        elsif path.end_with?(".yml", ".json")
          path = "../#{path}"
        end
        fragment ? "#{path}##{fragment}" : path
      end

      def documentation_target(path)
        return unless @current_document_path

        Pathname(@current_document_path).dirname.join(path).cleanpath.to_s
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      def github_href(path)
        "https://github.com/ydah/ibex/blob/main/#{path}"
      end

      def escape_attribute(value)
        CGI.escapeHTML(value.to_s)
      end
    end

    module_function

    def load(path)
      text = path.read
      metadata = {}
      if text.start_with?("---\n")
        lines = text.lines
        closing = lines[1..].index { |line| line.chomp == "---" }
        raise "unterminated documentation front matter: #{path}" unless closing

        front_matter = lines[1, closing]
        body = lines[(closing + 2)..]&.join
        metadata = front_matter.each_with_object({}) do |line, result|
          key, value = line.chomp.split(":", 2)
          result[key] = value.to_s.strip.gsub(/\A["']|["']\z/, "") if key && value
        end
        text = body.to_s.sub(/\A\n/, "")
      end
      title = metadata["title"] || text[/\A#\s+(.+?)(?:\s+#)?\s*$/,
                                        1] || path.basename(".md").to_s.tr("-", " ").capitalize
      description = metadata["description"] || "Ibex documentation for #{title}."
      Document.new(title: title, description: description, body: text)
    end
  end
end
