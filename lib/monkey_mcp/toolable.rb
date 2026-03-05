# frozen_string_literal: true

module MonkeyMcp
  # Include this concern in any Rails controller to auto-register its actions as MCP tools.
  #
  # All public methods defined directly in the including class are auto-registered.
  # Use `mcp_desc` immediately before a method definition to attach a description.
  #
  # Example:
  #   class Api::V1::TasksController < ApplicationController
  #     include MonkeyMcp::Toolable
  #
  #     mcp_desc "List all tasks"
  #     def index; end   # registered as "task_index" with description
  #
  #     def show; end    # registered as "task_show" with empty description
  #   end
  #
  # Tool name format: demodulized, singularized controller name + action
  #   Api::V1::TasksController#index => "task_index"
  #
  # input_schema is built lazily (avoids DB access at class load time).
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
      # Skips inherited methods and non-public methods.
      def method_added(method_name)
        super

        desc = @_pending_mcp_desc
        @_pending_mcp_desc = nil

        # Only register public methods defined in this class (not inherited)
        return unless public_method_defined?(method_name)
        return if superclass.method_defined?(method_name)

        _register_mcp_tool(action: method_name.to_sym, description: desc || "")
      end

      private

      def _register_mcp_tool(action:, description:)
        tool_name   = _mcp_tool_name(action)
        model_class = _infer_model
        action_sym  = action

        # Build schema lazily to avoid DB connection at class load time
        schema_builder = -> {
          model_class ? MonkeyMcp::SchemaBuilder.build(model: model_class, action: action_sym) : _empty_schema
        }

        MonkeyMcp::Registry.register(
          name:         tool_name,
          description:  description,
          input_schema: schema_builder,
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
