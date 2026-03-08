# frozen_string_literal: true

module MonkeyMcp
  # Searches registered MCP tools by keyword matching.
  #
  # The default implementation scores each tool by counting how many query tokens
  # appear in the tool's name and description (case-insensitive), then returns the
  # top results sorted by descending score.
  #
  # This interface is intentionally minimal so that it can be replaced with an
  # embedding-based implementation in the future without changing callers.
  class ToolSearcher
    META_TOOL_NAMES = %w[tool_search call_proxy].freeze

    # @param tools [Array<Hash>] resolved tool hashes from Registry.all
    def initialize(tools)
      @tools = tools
    end

    # @param query [String] non-empty search query (caller must validate)
    # @param filters [Hash] optional filters; supports :namespace (String)
    # @param max_results [Integer] maximum number of results to return
    # @return [Array<Hash>] matching tools with :name, :description, :inputSchema
    def search(query:, filters: {}, max_results: 10)
      candidates = apply_filters(@tools, filters)
      tokens     = tokenize(query)

      scored = candidates.filter_map do |tool|
        score = score_tool(tool, tokens)
        { tool: tool, score: score } if score > 0
      end

      scored
        .sort_by { |entry| -entry[:score] }
        .first(max_results)
        .map { |entry| format_tool(entry[:tool]) }
    end

    private

    def apply_filters(tools, filters)
      ns = filters[:namespace].to_s.strip
      return tools if ns.empty?

      tools.select do |tool|
        normalize_controller(tool[:controller]).start_with?(ns)
      end
    end

    # Normalize controller class name to a path prefix matching Toolable conventions.
    # e.g. "Api::V1::TasksController" => "api/v1/tasks"
    def normalize_controller(controller)
      controller
        .gsub("::", "/")
        .gsub(/Controller$/, "")
        .then { |s| s.respond_to?(:underscore) ? s.underscore : s.downcase }
    end

    def tokenize(query)
      query.to_s.downcase.split(/\s+/).reject(&:empty?)
    end

    def score_tool(tool, tokens)
      text = "#{tool[:name]} #{tool[:description]}".downcase
      tokens.sum { |token| text.scan(token).length }
    end

    def format_tool(tool)
      {
        name:        tool[:name],
        description: tool[:description],
        inputSchema: tool[:input_schema]
      }
    end
  end
end
