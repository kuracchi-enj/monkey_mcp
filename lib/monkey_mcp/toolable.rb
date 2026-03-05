# frozen_string_literal: true

module MonkeyMcp
  # Include this concern in any Rails controller to auto-register its actions as MCP tools.
  #
  # Usage:
  #   class Api::V1::TasksController < ApplicationController
  #     include MonkeyMcp::Toolable
  #
  #     mcp_desc "List all tasks"
  #     def index; end
  #   end
  #
  # The generated tool name uses the demodulized, singularized controller name:
  #   Api::V1::TasksController#index => "task_index"
  module Toolable
    extend ActiveSupport::Concern

    included do
      @_pending_mcp_desc = nil

      # Fires after each method definition — captures the pending description
      def self.method_added(method_name)
        super
        return unless @_pending_mcp_desc

        desc = @_pending_mcp_desc
        @_pending_mcp_desc = nil

        _register_mcp_tool(action: method_name.to_sym, description: desc)
      end
    end

    class_methods do
      # Decorator: attach a description to the next method defined.
      # Call immediately before `def action_name`.
      def mcp_desc(text)
        @_pending_mcp_desc = text
      end

      private

      def _register_mcp_tool(action:, description:)
        tool_name = _mcp_tool_name(action)
        model     = _infer_model
        schema    = model ? MonkeyMcp::SchemaBuilder.build(model: model, action: action) : _empty_schema

        MonkeyMcp::Registry.register(
          name:         tool_name,
          description:  description,
          input_schema: schema,
          controller:   name,
          action:       action.to_s
        )
      end

      # "Api::V1::TasksController#index" => "task_index"
      # Uses the demodulized, singularized controller segment as prefix.
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
