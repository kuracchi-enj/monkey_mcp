# frozen_string_literal: true

RSpec.describe MonkeyMcp do
  it "has a version number" do
    expect(MonkeyMcp::VERSION).not_to be nil
  end

  describe ".configure" do
    it "yields the configuration object" do
      expect { |b| MonkeyMcp.configure(&b) }.to yield_with_args(MonkeyMcp::Configuration)
    end

    it "sets internal_token" do
      MonkeyMcp.configure { |c| c.internal_token = "test_token" }
      expect(MonkeyMcp.configuration.internal_token).to eq("test_token")
    end
  end

  describe MonkeyMcp::Registry do
    before { described_class.reset! }

    it "registers and retrieves a tool" do
      described_class.register(
        name: "test_tool", description: "A test", input_schema: {},
        controller: "TestController", action: "index"
      )
      expect(described_class.find("test_tool")[:name]).to eq("test_tool")
    end

    it "returns nil for unknown tool" do
      expect(described_class.find("nonexistent")).to be_nil
    end

    it "clears tools on reset!" do
      described_class.register(
        name: "test_tool", description: "", input_schema: {},
        controller: "TestController", action: "index"
      )
      described_class.reset!
      expect(described_class.all).to be_empty
    end

    it "evaluates a Proc input_schema lazily" do
      called = false
      described_class.register(
        name: "lazy_tool", description: "", input_schema: -> { called = true; { "type" => "object" } },
        controller: "TestController", action: "index"
      )
      expect(called).to be false
      described_class.find("lazy_tool")
      expect(called).to be true
    end
  end

  describe MonkeyMcp::Configuration do
    subject(:config) { described_class.new }

    it "has a non-nil internal_token by default" do
      expect(config.internal_token).not_to be_nil
    end

    it "excludes created_at and updated_at by default" do
      expect(config.excluded_columns).to include("created_at", "updated_at")
    end
  end
end
