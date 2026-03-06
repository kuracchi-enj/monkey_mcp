# MonkeyMcp

`monkey_mcp` は、Rails アプリを MCP サーバとして公開するための Gem です。  
`POST /mcp` エンドポイント（JSON-RPC 2.0）を提供し、Rails コントローラのアクションを MCP ツールとして呼び出せるようにします。

## 概要

- Rails コントローラに `include MonkeyMcp::Toolable` を追加すると、ツール登録を自動化
- MCP リクエスト（`initialize` / `tools/list` / `tools/call`）を Gem 側で処理
- `tools/call` は Rails アプリ内へ内部サブリクエストし、既存のコントローラロジックを再利用
- ActiveRecord のカラム情報から `inputSchema` を自動生成

## できること

- routes に実在する public アクションだけを MCP ツールとして公開
- `mcp_desc` でツール説明を宣言（省略時は空文字）
- `create/update` のときは Strong Parameters 互換のペイロードを自動生成
- 非 CRUD アクションでも route があれば呼び出し可能
- `ControllerHelpers` による内部リクエスト認証バイパス
- `mount_path` / `auto_append_route` / `excluded_tool_methods` などの設定変更

## 前提

- Ruby: `>= 3.1`
- Rails: `>= 7.0`
- MCP クライアントから到達可能な HTTP エンドポイント（例: `http://localhost:3000/mcp`）

## インストール

### GitHub タグから導入（推奨）

```ruby
# Gemfile
gem "monkey_mcp", github: "kuracchi-enj/monkey_mcp", tag: "v0.1.0"
```

```bash
bundle install
```

## Rails 側の設定手順

### 1. MCP ツール化したいコントローラに include

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

補足:
- `mcp_desc` を付けなくても route に一致する action は登録されます（description は空）
- route にない utility メソッドは自動的に除外されます

### 2. 内部サブリクエスト用の認証バイパスを設定

`ApplicationController` などの基底コントローラで `ControllerHelpers` を利用します。

```ruby
class ApplicationController < ActionController::Base
  include MonkeyMcp::ControllerHelpers

  before_action :require_login
  protect_with_internal_token! :require_login

  private

  def require_login
    redirect_to login_path unless logged_in?
  end
end
```

### 3. 初期化設定（任意）

`config/initializers/monkey_mcp.rb`

```ruby
MonkeyMcp.configure do |config|
  # 内部リクエスト認証トークン（未指定ならランダム生成）
  config.internal_token = ENV.fetch("MCP_INTERNAL_TOKEN") { SecureRandom.hex(32) }

  # inputSchema 生成時に除外する AR カラム
  config.excluded_columns = %w[created_at updated_at]

  # MCP エンドポイントのパス
  config.mount_path = "/mcp"

  # true: Engine が route を自動追加 / false: 手動で routes.rb に定義
  config.auto_append_route = true

  # ツール登録から除外する action 名
  config.excluded_tool_methods = %i[healthcheck debug_action]
end
```

### 4. development/test 向けの事前ロード

`eager_load: false` の環境では、`to_prepare` で対象コントローラを参照してください。

```ruby
Rails.application.config.to_prepare do
  Api::V1::TasksController
end
```

### 5. `auto_append_route = false` の場合だけ手動ルーティング

```ruby
# config/routes.rb
post "/mcp", to: "monkey_mcp/mcp#handle"
```

## MCP クライアント側の設定 JSON 例

MCP クライアントごとに設定キー名は異なります。  
以下は「HTTP エンドポイント `http://localhost:3000/mcp` を使う」場合の代表例です。

### 例1: `mcpServers` 形式の設定

```json
{
  "mcpServers": {
    "my_task_app": {
      "url": "http://localhost:3000/mcp"
    }
  }
}
```

### 例2: transport を明示する形式

```json
{
  "servers": {
    "my_task_app": {
      "transport": "http",
      "url": "http://localhost:3000/mcp"
    }
  }
}
```

注意:
- 実際のキー名（`mcpServers` / `servers` / `transport` など）はクライアント実装に合わせて読み替えてください
- 認証やリバースプロキシを挟む場合は、クライアント側の header 設定も追加してください

## 動作確認（curl）

### initialize

```bash
curl -s -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
```

### tools/list

```bash
curl -s -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
```

### tools/call

```bash
curl -s -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"task_index","arguments":{}}}'
```

## ツール名の命名規則

`<単数化コントローラ名>_<action>` 形式で生成されます。

| Controller | Action | Tool Name |
|---|---|---|
| `Api::V1::TasksController` | `index` | `task_index` |
| `Api::V1::TasksController` | `show` | `task_show` |
| `Api::V1::CategoriesController` | `create` | `category_create` |

## inputSchema 生成ルール（概要）

- `show` / `update` / `destroy`: `id` を required
- `create`: モデルカラムをもとに schema 生成（`excluded_columns` は除外）
- `update`: モデルカラムをもとに optional schema 生成
- enum カラムは `enum` 配列として出力

## トラブルシュート

- `tools/list` が空になる  
  - 対象コントローラが `to_prepare` でロードされているか確認
  - action が routes に存在するか確認
- `Unknown tool` が返る  
  - ツール名の命名規則と `excluded_tool_methods` を確認
- `No route found for ...` が返る  
  - `config/routes.rb` に action が定義されているか確認
- ログイン必須アプリで `tools/call` が 302/401 になる  
  - `ControllerHelpers` と `protect_with_internal_token!` の設定を確認

## 開発

```bash
git clone https://github.com/kuracchi-enj/monkey_mcp
cd monkey_mcp
rbenv exec bundle install
rbenv exec bundle exec rspec
```
