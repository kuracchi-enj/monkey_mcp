# frozen_string_literal: true

RSpec.describe MonkeyMcp::Configuration do
  subject(:config) { described_class.new }

  describe "dynamic mode defaults" do
    it "defaults tool_listing_mode to :full" do
      expect(config.tool_listing_mode).to eq(:full)
    end

    it "defaults max_search_results to 10" do
      expect(config.max_search_results).to eq(10)
    end

    it "defaults max_tool_search_results to 100" do
      expect(config.max_tool_search_results).to eq(100)
    end

    it "defaults search_timeout_ms to 1000" do
      expect(config.search_timeout_ms).to eq(1000)
    end

  end

  describe "tool_listing_mode=" do
    it "accepts :full" do
      config.tool_listing_mode = :full
      expect(config.tool_listing_mode).to eq(:full)
    end

    it "accepts :dynamic" do
      config.tool_listing_mode = :dynamic
      expect(config.tool_listing_mode).to eq(:dynamic)
    end

    it "raises ArgumentError for invalid values" do
      expect { config.tool_listing_mode = :invalid }.to raise_error(ArgumentError)
      expect { config.tool_listing_mode = "full" }.to raise_error(ArgumentError)
      expect { config.tool_listing_mode = nil }.to raise_error(ArgumentError)
    end
  end

  describe "max_search_results=" do
    it "accepts a positive integer" do
      config.max_search_results = 20
      expect(config.max_search_results).to eq(20)
    end

    it "raises ArgumentError for 0" do
      expect { config.max_search_results = 0 }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError for negative" do
      expect { config.max_search_results = -1 }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError for non-integer" do
      expect { config.max_search_results = "10" }.to raise_error(ArgumentError)
      expect { config.max_search_results = nil }.to raise_error(ArgumentError)
    end
  end

  describe "max_tool_search_results=" do
    it "accepts a positive integer" do
      config.max_tool_search_results = 50
      expect(config.max_tool_search_results).to eq(50)
    end

    it "raises ArgumentError for invalid values" do
      expect { config.max_tool_search_results = 0 }.to raise_error(ArgumentError)
      expect { config.max_tool_search_results = nil }.to raise_error(ArgumentError)
    end
  end

  describe "search_timeout_ms=" do
    it "accepts a positive integer" do
      config.search_timeout_ms = 500
      expect(config.search_timeout_ms).to eq(500)
    end

    it "raises ArgumentError for invalid values" do
      expect { config.search_timeout_ms = 0 }.to raise_error(ArgumentError)
      expect { config.search_timeout_ms = -100 }.to raise_error(ArgumentError)
    end
  end

end

RSpec.describe MonkeyMcp::ToolSearcher do
  let(:tools) do
    [
      { name: "task_index",  description: "List all tasks",        controller: "Api::V1::TasksController",    action: "index",  input_schema: {} },
      { name: "task_show",   description: "Get a single task",     controller: "Api::V1::TasksController",    action: "show",   input_schema: {} },
      { name: "task_create", description: "Create a new task",     controller: "Api::V1::TasksController",    action: "create", input_schema: {} },
      { name: "user_index",  description: "List all users",        controller: "Api::V1::UsersController",    action: "index",  input_schema: {} },
      { name: "order_index", description: "List purchase orders",  controller: "Api::V2::OrdersController",   action: "index",  input_schema: {} }
    ]
  end

  subject(:searcher) { described_class.new(tools) }

  describe "#search" do
    it "returns tools matching the query" do
      results = searcher.search(query: "task")
      names = results.map { |t| t[:name] }
      expect(names).to include("task_index", "task_show", "task_create")
    end

    it "does not return non-matching tools" do
      results = searcher.search(query: "task")
      names = results.map { |t| t[:name] }
      expect(names).not_to include("user_index")
    end

    it "returns results sorted by descending score" do
      results = searcher.search(query: "task list")
      expect(results.first[:name]).to eq("task_index")
    end

    it "respects max_results limit" do
      results = searcher.search(query: "task", max_results: 2)
      expect(results.length).to be <= 2
    end

    it "returns empty array when nothing matches" do
      results = searcher.search(query: "nonexistent_xyz_abc")
      expect(results).to be_empty
    end

    it "is case-insensitive" do
      results = searcher.search(query: "TASK")
      expect(results).not_to be_empty
    end

    it "returns name, description, and inputSchema in results" do
      results = searcher.search(query: "task")
      result = results.first
      expect(result.keys).to include(:name, :description, :inputSchema)
    end

    context "with namespace filter" do
      it "filters by controller namespace prefix" do
        results = searcher.search(query: "list", filters: { namespace: "api/v1" })
        names = results.map { |t| t[:name] }
        expect(names).to include("task_index", "user_index")
        expect(names).not_to include("order_index")
      end

      it "returns results across multiple controllers within the namespace" do
        results = searcher.search(query: "list", filters: { namespace: "api/v2" })
        names = results.map { |t| t[:name] }
        expect(names).to include("order_index")
        expect(names).not_to include("task_index")
      end
    end
  end
end

RSpec.describe "MonkeyMcp dynamic mode integration" do
  # Minimal stub of a Rails app for controller dispatch tests
  let(:config) { MonkeyMcp::Configuration.new }

  before do
    MonkeyMcp::Registry.reset!
    allow(MonkeyMcp).to receive(:configuration).and_return(config)
  end

  after do
    MonkeyMcp::Registry.reset!
  end

  def register_tool(name:, description: "desc", controller: "TestController", action: "index")
    MonkeyMcp::Registry.register(
      name:         name,
      description:  description,
      input_schema: { "type" => "object", "properties" => {}, "required" => [] },
      route_check:  -> { true },
      controller:   controller,
      action:       action
    )
  end

  # Simulate McpController dispatch without a full Rack stack
  def dispatch(controller_instance, body_hash)
    controller_instance.send(:dispatch_method, body_hash)
  end

  let(:controller) do
    MonkeyMcp::McpController.new.tap do |c|
      # Stub request for the controller (not doing actual HTTP here)
    end
  end

  describe "tools/list" do
    context "with tool_listing_mode: :full (default)" do
      before { register_tool(name: "task_index", description: "List tasks") }

      it "returns all registered tools" do
        result = dispatch(controller, { "method" => "tools/list", "id" => 1, "params" => {} })
        names = result[:result][:tools].map { |t| t[:name] }
        expect(names).to include("task_index")
      end

      it "does not include tool_search or call_proxy" do
        result = dispatch(controller, { "method" => "tools/list", "id" => 1, "params" => {} })
        names = result[:result][:tools].map { |t| t[:name] }
        expect(names).not_to include("tool_search", "call_proxy")
      end
    end

    context "with tool_listing_mode: :dynamic" do
      before { config.tool_listing_mode = :dynamic }

      it "returns only tool_search and call_proxy" do
        register_tool(name: "task_index")
        result = dispatch(controller, { "method" => "tools/list", "id" => 1, "params" => {} })
        names = result[:result][:tools].map { |t| t[:name] }
        expect(names).to contain_exactly("tool_search", "call_proxy")
      end

      it "includes inputSchema for both meta-tools" do
        result = dispatch(controller, { "method" => "tools/list", "id" => 1, "params" => {} })
        tools = result[:result][:tools]
        tools.each do |t|
          expect(t[:inputSchema]).to be_a(Hash)
          expect(t[:inputSchema]["required"]).to include("query") if t[:name] == "tool_search"
          expect(t[:inputSchema]["required"]).to include("name") if t[:name] == "call_proxy"
        end
      end
    end
  end

  describe "tool_search" do
    before do
      config.tool_listing_mode = :dynamic
      register_tool(name: "task_index", description: "List all tasks")
      register_tool(name: "user_index", description: "List all users")
    end

    it "returns matching tools as JSON text" do
      result = dispatch(controller, {
        "method" => "tools/call", "id" => 2,
        "params" => { "name" => "tool_search", "arguments" => { "query" => "task" } }
      })
      content = result[:result][:content].first[:text]
      tools = JSON.parse(content)
      names = tools.map { |t| t["name"] }
      expect(names).to include("task_index")
    end

    it "returns -32602 for empty query" do
      result = dispatch(controller, {
        "method" => "tools/call", "id" => 3,
        "params" => { "name" => "tool_search", "arguments" => { "query" => "" } }
      })
      expect(result[:error][:code]).to eq(-32_602)
    end

    it "returns -32602 for whitespace-only query" do
      result = dispatch(controller, {
        "method" => "tools/call", "id" => 4,
        "params" => { "name" => "tool_search", "arguments" => { "query" => "   " } }
      })
      expect(result[:error][:code]).to eq(-32_602)
    end

    it "returns -32602 for invalid max_results" do
      result = dispatch(controller, {
        "method" => "tools/call", "id" => 5,
        "params" => { "name" => "tool_search", "arguments" => { "query" => "task", "max_results" => 0 } }
      })
      expect(result[:error][:code]).to eq(-32_602)
    end

    it "returns -32602 for non-string query" do
      result = dispatch(controller, {
        "method" => "tools/call", "id" => 5,
        "params" => { "name" => "tool_search", "arguments" => { "query" => 123 } }
      })
      expect(result[:error][:code]).to eq(-32_602)
    end

    it "returns -32602 for invalid filters type" do
      result = dispatch(controller, {
        "method" => "tools/call", "id" => 5,
        "params" => { "name" => "tool_search", "arguments" => { "query" => "task", "filters" => "api/v1" } }
      })
      expect(result[:error][:code]).to eq(-32_602)
    end

    it "clamps max_results to max_tool_search_results" do
      config.max_tool_search_results = 2
      register_tool(name: "task_create", description: "Create task")
      register_tool(name: "task_show",   description: "Show task")
      result = dispatch(controller, {
        "method" => "tools/call", "id" => 6,
        "params" => { "name" => "tool_search", "arguments" => { "query" => "task", "max_results" => 999 } }
      })
      content = JSON.parse(result[:result][:content].first[:text])
      expect(content.length).to be <= 2
    end
  end

  describe "call_proxy" do
    before do
      config.tool_listing_mode = :dynamic
      register_tool(name: "task_index", description: "List tasks")
    end

    it "returns -32602 for empty name" do
      result = dispatch(controller, {
        "method" => "tools/call", "id" => 7,
        "params" => { "name" => "call_proxy", "arguments" => { "name" => "" } }
      })
      expect(result[:error][:code]).to eq(-32_602)
    end

    it "returns -32602 for unknown tool name" do
      result = dispatch(controller, {
        "method" => "tools/call", "id" => 8,
        "params" => { "name" => "call_proxy", "arguments" => { "name" => "nonexistent_tool" } }
      })
      expect(result[:error][:code]).to eq(-32_602)
    end

    it "returns -32602 for non-string name" do
      result = dispatch(controller, {
        "method" => "tools/call", "id" => 8,
        "params" => { "name" => "call_proxy", "arguments" => { "name" => 100 } }
      })
      expect(result[:error][:code]).to eq(-32_602)
    end

    it "returns -32602 for invalid arguments type" do
      result = dispatch(controller, {
        "method" => "tools/call", "id" => 8,
        "params" => { "name" => "call_proxy", "arguments" => { "name" => "task_index", "arguments" => "bad" } }
      })
      expect(result[:error][:code]).to eq(-32_602)
    end
  end

  describe "backward compatibility" do
    before { register_tool(name: "task_index", description: "List tasks") }

    context "with default (full) mode" do
      it "existing tools/call routes to handle_tools_call (not meta-tool handlers)" do
        allow(controller).to receive(:internal_dispatch).and_return([200, '{"items":[]}'])
        result = dispatch(controller, {
          "method" => "tools/call", "id" => 9,
          "params" => { "name" => "task_index", "arguments" => {} }
        })
        expect(result[:result][:content].first[:text]).to eq('{"items":[]}')
      end
    end

    context "with dynamic mode" do
      before { config.tool_listing_mode = :dynamic }

      it "direct tools/call still works for registered tools" do
        allow(controller).to receive(:internal_dispatch).and_return([200, '{"items":[]}'])
        result = dispatch(controller, {
          "method" => "tools/call", "id" => 10,
          "params" => { "name" => "task_index", "arguments" => {} }
        })
        expect(result[:result][:content].first[:text]).to eq('{"items":[]}')
      end
    end
  end
end

RSpec.describe "MonkeyMcp reserved word protection" do
  # ToolsController with action :search generates tool name "tool_search"
  # CallsController with action :proxy generates tool name "call_proxy"
  before do
    MonkeyMcp::Registry.reset!
    allow(MonkeyMcp).to receive(:configuration).and_return(MonkeyMcp::Configuration.new)
    stub_const("ToolsController", Class.new { include MonkeyMcp::Toolable })
    stub_const("CallsController", Class.new { include MonkeyMcp::Toolable })
  end

  after { MonkeyMcp::Registry.reset! }

  it "does not register a tool named tool_search by default" do
    ToolsController.send(:_register_mcp_tool, action: :search, description: "should be blocked")
    expect(MonkeyMcp::Registry.find("tool_search")).to be_nil
  end

  it "does not register a tool named call_proxy by default" do
    CallsController.send(:_register_mcp_tool, action: :proxy, description: "should be blocked")
    expect(MonkeyMcp::Registry.find("call_proxy")).to be_nil
  end
end
