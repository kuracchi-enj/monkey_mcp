# MonkeyMcp

`monkey_mcp` は Rails コントローラのアクションを [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) ツールとして自動公開する Rails Gem です。  
JSON-RPC 2.0 準拠の `POST /mcp` エンドポイントを提供し、AI エージェントから直接 Rails アプリの機能を呼び出せるようにします。

## 特徴

- **自動ツール登録**: `include MonkeyMcp::Toolable` を追加するだけで、コントローラの public メソッドのうち、routes に実在するアクションのみ MCP ツールとして登録される
- **input_schema 自動生成**: ActiveRecord の `columns_hash` からリクエストスキーマを自動生成
- **mcp_desc デコレータ**: アクション直前に `mcp_desc "説明文"` を書くだけでツールの説明を設定
- **Rails Engine**: `POST /mcp` ルートを自動でマウント
- **内部認証**: ランダムトークンによるサブリクエスト認証でセキュリティを確保

## インストール

Gemfile に以下を追加:

```ruby
gem "monkey_mcp", github: "kuracchi-enj/monkey_mcp"
```

ローカル開発の場合:

```ruby
gem "monkey_mcp", path: "../monkey_mcp"
```

## 使い方

### 1. コントローラに Toolable を include する

```ruby
class Api::V1::TasksController < ApplicationController
  include MonkeyMcp::Toolable

  mcp_desc "タスク一覧を取得する"
  def index
    render json: Task.all
  end

  mcp_desc "タスクを作成する"
  def create
    task = Task.create!(task_params)
    render json: task, status: :created
  end
end
```

`mcp_desc` を省略した場合も routes に一致するアクションは自動登録されます（description は空文字列）。routes に存在しない utility メソッドは登録されません。

### 2. ApplicationController で内部トークンを認証する

```ruby
class ApplicationController < ActionController::Base
  before_action :require_login

  private

  def require_login
    # MonkeyMcp の内部サブリクエストはログイン不要にする
    return if request.headers["X-Mcp-Internal-Token"] == MonkeyMcp.configuration.internal_token
    redirect_to login_path unless logged_in?
  end
end
```

### 3. 設定（任意）

`config/initializers/monkey_mcp.rb`:

```ruby
MonkeyMcp.configure do |config|
  # サブリクエスト認証用トークン（デフォルト: 起動時にランダム生成）
  config.internal_token = ENV.fetch("MCP_INTERNAL_TOKEN") { SecureRandom.hex(32) }

  # input_schema から除外するカラム（デフォルト: created_at, updated_at）
  config.excluded_columns = %w[created_at updated_at]
end
```

### 4. 事前ロード設定

`eager_load: false` な環境（development, test）でも MCP ツールが確実に登録されるよう、initializer でコントローラを参照:

```ruby
Rails.application.config.to_prepare do
  Api::V1::TasksController
end
```

## MCP ツールの動作

### ツール一覧 (tools/list)

```bash
curl -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

### ツール呼び出し (tools/call)

```bash
curl -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"task_index","arguments":{}}}'
```

## ツール名の命名規則

コントローラ名とアクション名から自動生成されます:

| コントローラ | アクション | ツール名 |
|---|---|---|
| `Api::V1::TasksController` | `index` | `task_index` |
| `Api::V1::TasksController` | `show` | `task_show` |
| `Api::V1::CategoriesController` | `create` | `category_create` |

## 開発

```bash
git clone https://github.com/kuracchi-enj/monkey_mcp
cd monkey_mcp
bundle install
bundle exec rspec
```
