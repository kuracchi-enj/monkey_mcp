# frozen_string_literal: true

require "rack"
require "json"
require "action_controller/api"

module MonkeyMcp
  class McpController < ActionController::API
    JSONRPC_VERSION  = "2.0"
    PROTOCOL_VERSION = "2024-11-05"

    skip_before_action :verify_authenticity_token, raise: false

    def handle
      body = JSON.parse(request.body.read)
      result = dispatch_method(body)
      render json: result
    rescue JSON::ParserError
      render json: jsonrpc_error(nil, -32_700, "Parse error"), status: :bad_request
    end

    private

    def dispatch_method(body)
      method = body["method"]
      id     = body["id"]
      params = body["params"] || {}

      case method
      when "initialize"
        handle_initialize(id)
      when "notifications/initialized"
        nil
      when "tools/list"
        handle_tools_list(id)
      when "tools/call"
        tool_name = params["name"]
        case tool_name
        when "tool_search" then handle_tool_search(id, params["arguments"] || {})
        when "call_proxy"  then handle_call_proxy(id, params["arguments"] || {})
        else                    handle_tools_call(id, params)
        end
      else
        jsonrpc_error(id, -32_601, "Method not found: #{method}")
      end
    end

    def handle_initialize(id)
      jsonrpc_result(id, {
        protocolVersion: PROTOCOL_VERSION,
        capabilities: { tools: {} },
        serverInfo: { name: Rails.application.class.module_parent_name.underscore, version: "1.0.0" }
      })
    end

    def handle_tools_list(id)
      if MonkeyMcp.configuration.tool_listing_mode == :dynamic
        jsonrpc_result(id, { tools: dynamic_meta_tools })
      else
        tools = MonkeyMcp::Registry.all.map do |t|
          { name: t[:name], description: t[:description], inputSchema: t[:input_schema] }
        end
        jsonrpc_result(id, { tools: tools })
      end
    end

    def handle_tools_call(id, params)
      tool_name = params["name"]
      arguments = params["arguments"] || {}

      tool = MonkeyMcp::Registry.find(tool_name)
      return jsonrpc_error(id, -32_602, "Unknown tool: #{tool_name}") unless tool

      status, body_str = internal_dispatch(tool, arguments)
      result_text = status == 204 ? { success: true }.to_json : body_str
      is_error = status < 200 || status >= 300

      jsonrpc_result(id, {
        content: [{ type: "text", text: result_text }],
        **(is_error ? { isError: true } : {})
      })
    rescue MonkeyMcp::RouteNotFound => e
      jsonrpc_error(id, -32_601, e.message)
    end

    def handle_tool_search(id, arguments)
      return jsonrpc_error(id, -32_602, "Invalid params: arguments must be an object") unless arguments.is_a?(Hash)

      raw_query = arguments["query"]
      return jsonrpc_error(id, -32_602, "Invalid params: query must be a string") unless raw_query.is_a?(String)

      query = raw_query.strip
      return jsonrpc_error(id, -32_602, "Invalid params: query must be a non-empty string") if query.empty?

      raw_max = arguments["max_results"]
      if !raw_max.nil?
        unless raw_max.is_a?(Integer) && raw_max > 0
          return jsonrpc_error(id, -32_602, "Invalid params: max_results must be a positive integer")
        end
      end

      config      = MonkeyMcp.configuration
      max_results = (raw_max || config.max_search_results).clamp(1, config.max_tool_search_results)

      raw_filters = arguments["filters"] || {}
      unless raw_filters.is_a?(Hash)
        return jsonrpc_error(id, -32_602, "Invalid params: filters must be an object")
      end
      filters     = raw_filters.transform_keys(&:to_sym)

      results = MonkeyMcp::ToolSearcher.new(MonkeyMcp::Registry.all).search(
        query:       query,
        filters:     filters,
        max_results: max_results
      )

      jsonrpc_result(id, {
        content: [{ type: "text", text: results.to_json }]
      })
    end

    def handle_call_proxy(id, arguments)
      return jsonrpc_error(id, -32_602, "Invalid params: arguments must be an object") unless arguments.is_a?(Hash)

      raw_name = arguments["name"]
      return jsonrpc_error(id, -32_602, "Invalid params: name must be a string") unless raw_name.is_a?(String)

      tool_name = raw_name.strip
      return jsonrpc_error(id, -32_602, "Invalid params: name must be a non-empty string") if tool_name.empty?

      tool = MonkeyMcp::Registry.find(tool_name)
      return jsonrpc_error(id, -32_602, "Unknown tool: #{tool_name}") unless tool

      args = arguments["arguments"] || {}
      return jsonrpc_error(id, -32_602, "Invalid params: arguments must be an object") unless args.is_a?(Hash)

      status, body_str = internal_dispatch(tool, args)
      result_text = status == 204 ? { success: true }.to_json : body_str
      is_error = status < 200 || status >= 300

      jsonrpc_result(id, {
        content: [{ type: "text", text: result_text }],
        **(is_error ? { isError: true } : {})
      })
    rescue MonkeyMcp::RouteNotFound => e
      jsonrpc_error(id, -32_601, e.message)
    end

    def dynamic_meta_tools
      [
        {
          name:        "tool_search",
          description: "Search for available tools by keyword. Returns matching tools with their name, description, and input schema.",
          inputSchema: {
            "type"       => "object",
            "properties" => {
              "query"       => {
                "type"        => "string",
                "description" => "Natural language description of the tool you are looking for"
              },
              "filters"     => {
                "type"        => "object",
                "description" => "Optional filters to narrow results",
                "properties"  => {
                  "namespace" => {
                    "type"        => "string",
                    "description" => "Controller path prefix to filter by (e.g. \"api/v1\")"
                  }
                }
              },
              "max_results" => {
                "type"        => "integer",
                "description" => "Maximum number of results to return (defaults to server setting)"
              }
            },
            "required"   => ["query"]
          }
        },
        {
          name:        "call_proxy",
          description: "Execute a tool by name. Use tool_search first to discover the tool name and required arguments.",
          inputSchema: {
            "type"       => "object",
            "properties" => {
              "name"      => {
                "type"        => "string",
                "description" => "The tool name to execute (as returned by tool_search)"
              },
              "arguments" => {
                "type"        => "object",
                "description" => "Arguments to pass to the tool"
              }
            },
            "required"   => ["name"]
          }
        }
      ]
    end

    # Dispatch to the host application via Rack::MockRequest.
    # Uses the Rails router to resolve path and HTTP verb.
    # Raises MonkeyMcp::RouteNotFound if the route cannot be resolved.
    def internal_dispatch(tool, arguments)
      action          = tool[:action]
      controller_path = tool[:controller].gsub("::", "/").gsub(/Controller$/, "").underscore
      id              = arguments["id"]&.to_s

      path, http_method = resolve_route(controller_path, action, id)
      body_params       = build_body_params(controller_path, action, arguments)

      env_opts = {
        method: http_method,
        "HTTP_ACCEPT"               => "application/json",
        "HTTP_X_MCP_INTERNAL_TOKEN" => MonkeyMcp.configuration.internal_token
      }

      if %w[POST PATCH PUT].include?(http_method)
        env_opts[:input]         = body_params.to_json
        env_opts["CONTENT_TYPE"] = "application/json"
      elsif body_params.any?
        env_opts["QUERY_STRING"] = body_params.to_query
      end

      env = Rack::MockRequest.env_for(path, **env_opts)
      status, _headers, body_parts = Rails.application.call(env)

      body_str = body_parts.each.to_a.join
      body_parts.close if body_parts.respond_to?(:close)

      [status, body_str]
    end

    # Resolve path and HTTP verb from the Rails route table.
    # Raises RouteNotFound if no matching route exists — no silent fallback.
    def resolve_route(controller_path, action, id)
      route_params = { controller: controller_path, action: action, only_path: true }
      route_params[:id] = id if id

      path = Rails.application.routes.url_for(route_params)

      # When multiple routes share the same controller#action (e.g. `match ... via: [:get, :post]`),
      # prefer the route whose verb matches the RESTful convention for this action.
      matching_routes = Rails.application.routes.routes
        .select { |r| r.defaults[:controller] == controller_path && r.defaults[:action] == action }

      expected_verb = action_to_http_method(action)
      matched_route = matching_routes.find { |r| r.verb.upcase == expected_verb } ||
                      matching_routes.first

      http_method = matched_route&.verb&.upcase || expected_verb

      [path, http_method]
    rescue ActionController::UrlGenerationError
      raise MonkeyMcp::RouteNotFound,
        "No route found for #{controller_path}##{action}. " \
        "Ensure the action is mapped in config/routes.rb."
    end

    # Build params hash for the request body / query string.
    # For create/update: wrap in the resource key for Strong Parameters.
    # For all other actions: pass arguments directly (excluding :id which goes in the URL path).
    def build_body_params(controller_path, action, arguments)
      non_id_args = arguments.except("id")

      case action
      when "create", "update"
        resource_key = controller_path.split("/").last.singularize
        { resource_key => non_id_args }
      else
        non_id_args
      end
    end

    def action_to_http_method(action)
      case action
      when "index", "show" then "GET"
      when "create"        then "POST"
      when "update"        then "PATCH"
      when "destroy"       then "DELETE"
      else "GET"
      end
    end

    def jsonrpc_result(id, result)
      { jsonrpc: JSONRPC_VERSION, id: id, result: result }
    end

    def jsonrpc_error(id, code, message)
      { jsonrpc: JSONRPC_VERSION, id: id, error: { code: code, message: message } }
    end
  end
end
