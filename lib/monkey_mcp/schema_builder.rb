# frozen_string_literal: true

module MonkeyMcp
  # Builds JSON Schema (draft-07 subset) from an ActiveRecord model's column metadata.
  class SchemaBuilder
    # @param model [Class] ActiveRecord model class
    # @param action [Symbol] :index, :show, :create, :update, :destroy
    # @param excluded [Array<String>] column names to skip
    def self.build(model:, action:, excluded: MonkeyMcp.configuration.excluded_columns)
      new(model: model, action: action, excluded: excluded).build
    end

    AR_TYPE_MAP = {
      "string"   => "string",
      "text"     => "string",
      "integer"  => "integer",
      "boolean"  => "boolean",
      "decimal"  => "number",
      "float"    => "number",
      "datetime" => "string",
      "date"     => "string",
      "time"     => "string"
    }.freeze

    WRITE_ACTIONS = %i[create update].freeze
    ID_ACTIONS    = %i[show update destroy].freeze

    def initialize(model:, action:, excluded:)
      @model    = model
      @action   = action.to_sym
      @excluded = excluded
    end

    def build
      properties = {}
      required   = []

      if ID_ACTIONS.include?(@action)
        properties["id"] = { "type" => "integer", "description" => "Resource ID" }
        required << "id"
      end

      if WRITE_ACTIONS.include?(@action)
        column_properties.each do |name, schema|
          properties[name] = schema
          required << name if @action == :create
        end
      end

      {
        "type"       => "object",
        "properties" => properties,
        "required"   => required
      }
    end

    private

    def column_properties
      enum_columns = @model.try(:defined_enums)&.keys&.map(&:to_s) || []

      @model.columns_hash.each_with_object({}) do |(name, col), props|
        next if @excluded.include?(name)
        next if name == "id"

        if enum_columns.include?(name)
          values = @model.defined_enums[name].keys
          props[name] = { "type" => "string", "enum" => values }
        else
          json_type = AR_TYPE_MAP[col.sql_type_metadata.type.to_s] || "string"
          props[name] = { "type" => json_type }
        end
      end
    end
  end
end
