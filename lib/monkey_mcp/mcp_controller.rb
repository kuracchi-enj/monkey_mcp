# frozen_string_literal: true

require "rack"
require "json"

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
        handle_tools_call(id, params)
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
      tools = MonkeyMcp::Registry.all.map do |t|
        { name: t[:name], description: t[:description], inputSchema: t[:input_schema] }
      end
      jsonrpc_result(id, { tools: tools })
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
    end

    # Dispatch to the host application via Rack::MockRequest
    def internal_dispatch(tool, arguments)
      action = tool[:action]
      controller_path = tool[:controller].gsub("::", "/").gsub(/Controller$/, "").underscore

      http_method = action_to_http_method(action)
      path, params = build_path_and_params(controller_path, action, arguments)

      env_opts = {
        method: http_method,
        "HTTP_ACCEPT"  => "application/json",
        "HTTP_X_MCP_INTERNAL_TOKEN" => MonkeyMcp.configuration.internal_token
      }

      if %w[POST PATCH PUT].include?(http_method)
        env_opts[:input] = params.to_json
        env_opts["CONTENT_TYPE"] = "application/json"
      else
        env_opts["QUERY_STRING"] = params.to_query if params.any?
      end

      env = Rack::MockRequest.env_for(path, **env_opts)
      status, _headers, body_parts = Rails.application.call(env)

      body_str = body_parts.each.to_a.join
      body_parts.close if body_parts.respond_to?(:close)

      [status, body_str]
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

    def build_path_and_params(controller_path, action, arguments)
      base_path = "/#{controller_path}"
      id = arguments["id"]

      path = id ? "#{base_path}/#{id}" : base_path

      params = case action
               when "create"
                 resource_key = controller_path.split("/").last.singularize
                 { resource_key => arguments.except("id") }
               when "update"
                 resource_key = controller_path.split("/").last.singularize
                 { resource_key => arguments.except("id") }
               when "index"
                 arguments
               else
                 {}
               end

      [path, params]
    end

    def jsonrpc_result(id, result)
      { jsonrpc: JSONRPC_VERSION, id: id, result: result }
    end

    def jsonrpc_error(id, code, message)
      { jsonrpc: JSONRPC_VERSION, id: id, error: { code: code, message: message } }
    end
  end
end
