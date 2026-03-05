# frozen_string_literal: true

module MonkeyMcp
  # Include this concern in any Rails controller to auto-register its actions as MCP tools.
  #
  # Only public methods that correspond to an actual route are registered.
  # Use `mcp_desc` immediately before a method definition to attach a description.
  #
  # Example:
  #   class Api::V1::TasksController < ApplicationController
  #     include MonkeyMcp::Toolable
  #
  #     mcp_desc "List all tasks"
  #     def index; end   # registered as "task_index" if route exists
  #
  #     def show; end    # registered as "task_show" with empty description if route exists
  #
  #     def helper_method; end  # NOT registered — no matching route
  #   end
  #
  # Tool name: demodulized, singularized controller name + action
  #   Api::V1::TasksController#index => "task_index"
  module Toolable
    extend ActiveSupport::Concern

    included do
      @_pending_mcp_desc = nil
    end

    class_methods do
      # Decorator: attach a description to the next method defined.
      def mcp_desc(text)
        @_pending_mcp_desc = text
      end

      # Auto-register every public method defined directly in this class.
      # Route existence is checked lazily at first access to avoid issues
      # with load order (controllers can load before routes are compiled).
      def method_added(method_name)
        super

        desc = @_pending_mcp_desc
        @_pending_mcp_desc = nil

        return unless public_method_defined?(method_name)
        return if superclass.method_defined?(method_name)

        _register_mcp_tool(action: method_name.to_sym, description: desc || "")
      end

      private

      def _register_mcp_tool(action:, description:)
        tool_name       = _mcp_tool_name(action)
        model_class     = _infer_model
        action_sym      = action
        controller_path = name.gsub("::", "/").gsub(/Controller$/, "").underscore

        # Lazily check route existence — routes are definitely loaded by the time
        # tools/list or tools/call is first invoked
        route_check = -> {
          Rails.application.routes.routes.any? do |r|
            r.defaults[:controller] == controller_path &&
              r.defaults[:action]    == action_sym.to_s
          end
        }

        # Build schema lazily to avoid DB access at class load time
        schema_builder = -> {
          model_class ? MonkeyMcp::SchemaBuilder.build(model: model_class, action: action_sym) : _empty_schema
        }

        MonkeyMcp::Registry.register(
          name:         tool_name,
          description:  description,
          input_schema: schema_builder,
          route_check:  route_check,
          controller:   name,
          action:       action.to_s
        )
      end

      # "Api::V1::TasksController#index" => "task_index"
      def _mcp_tool_name(action)
        resource = name
          .demodulize
          .delete_suffix("Controller")
          .singularize
          .underscore
        "#{resource}_#{action}"
      end

      # Guess model class from controller name (e.g. TasksController => Task)
      def _infer_model
        model_name = name.demodulize.delete_suffix("Controller").singularize
        model_name.safe_constantize
      rescue NameError
        nil
      end

      def _empty_schema
        { "type" => "object", "properties" => {}, "required" => [] }
      end
    end
  end
end
