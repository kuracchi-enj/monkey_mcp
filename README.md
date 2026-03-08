# MonkeyMcp

`monkey_mcp` は、Rails アプリを MCP サーバとして公開するための Gem です。  
`POST /mcp` エンドポイント（JSON-RPC 2.0）を提供し、Rails コントローラのアクションを MCP ツールとして呼び出せるようにします。

## 特徴

- コントローラに `include MonkeyMcp::Toolable` を追加するだけでツール登録を自動化
- MCP リクエスト（`initialize` / `tools/list` / `tools/call`）を Gem 側で処理
- `tools/call` は Rails アプリ内へ内部サブリクエストし、既存のコントローラロジックを再利用
- ActiveRecord のカラム情報から `inputSchema` を自動生成
- **Dynamic Mode**: `tools/list` を 2 ツールに極小化し、検索→実行フローを提供（[詳細](#dynamic-mode動的ロードモード)）

## 前提

- Ruby `>= 3.1`
- Rails `>= 7.0`
- MCP クライアントから到達可能な HTTP エンドポイント（例: `http://localhost:3000/mcp`）

## インストール

```ruby
# Gemfile
gem "monkey_mcp", github: "kuracchi-enj/monkey_mcp", tag: "v0.1.0"
```

```bash
bundle install
```

---

## クイックスタート

最小構成で Rails アプリを MCP サーバとして公開する手順です。

### Step 1. コントローラに Toolable を include

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

> **ポイント**: `mcp_desc` を省略しても routes に存在するアクションは登録されます（description が空になります）。

### Step 2. 内部リクエストの認証バイパスを設定

`tools/call` は内部サブリクエストで既存コントローラを呼び出します。  
認証が必要なアプリでは `ControllerHelpers` を使ってトークンでバイパスします。

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

### Step 3. 動作確認（curl）

```bash
# ツール一覧を取得
curl -s -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'

# ツールを実行
curl -s -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"task_index","arguments":{}}}'
```

---

## ツール登録の仕組み

### アクションの JSON レスポンス要件

`tools/call` は `Accept: application/json` ヘッダを付けて内部サブリクエストします。  
**MCP ツールとして公開するアクションは JSON レスポンスを返せる実装が必要です。**

```ruby
# ✅ OK: respond_to で format.json を定義
def index
  @tasks = Task.all
  respond_to do |format|
    format.html           # ブラウザからのアクセスでは HTML を返す
    format.json { render json: @tasks }  # MCP からのアクセスでは JSON を返す
  end
end

# ✅ OK: 常に JSON を返す（API 専用コントローラ）
def index
  render json: Task.all
end

# ⚠️ NG: format.json がない場合、406 Not Acceptable または HTML が返る
def index
  respond_to do |format|
    format.html  # format.json なし → MCP からのリクエストが失敗する
  end
end
```

`respond_to` に `format.html` と `format.json` を両方定義すれば、通常のブラウザアクセスと MCP ツール呼び出しを同一アクションで共存させることができます。

### ツール名の命名規則

`<単数化コントローラ名>_<action>` 形式で自動生成されます。

| Controller | Action | Tool Name |
|---|---|---|
| `Api::V1::TasksController` | `index` | `task_index` |
| `Api::V1::TasksController` | `show` | `task_show` |
| `Api::V1::CategoriesController` | `create` | `category_create` |

### inputSchema 自動生成ルール

| Action | 生成内容 |
|---|---|
| `index` | 空スキーマ |
| `show` / `destroy` | `id` を required |
| `create` | モデルカラムから生成（`excluded_columns` は除外）|
| `update` | `id` を required + モデルカラムから optional 生成 |

- enum カラムは `enum` 配列として出力
- `excluded_columns` のデフォルトは `["created_at", "updated_at"]`

### 予約語

`tool_search` と `call_proxy` は予約済みのツール名です。  
ユーザーが同名のツールを登録しようとすると、登録がブロックされ警告が出力されます。

---

## 設定リファレンス

`config/initializers/monkey_mcp.rb` で設定します。

```ruby
MonkeyMcp.configure do |config|
  # 内部リクエスト認証トークン（未指定ならランダム生成）
  config.internal_token = ENV.fetch("MCP_INTERNAL_TOKEN") { SecureRandom.hex(32) }

  # MCP エンドポイントのパス（デフォルト: "/mcp"）
  config.mount_path = "/mcp"

  # true: Engine が route を自動追加 / false: 手動で routes.rb に定義（デフォルト: true）
  config.auto_append_route = true

  # inputSchema 生成時に除外する AR カラム（デフォルト: ["created_at", "updated_at"]）
  config.excluded_columns = %w[created_at updated_at]

  # ツール登録から除外する action 名
  config.excluded_tool_methods = %i[healthcheck debug_action]

  # --- Dynamic Mode 設定 ---

  # :full（全ツール列挙）/ :dynamic（2 メタツールのみ）（デフォルト: :full）
  config.tool_listing_mode = :full

  # tool_search のデフォルト返却件数（デフォルト: 10）
  config.max_search_results = 10

  # tool_search の返却件数の上限（デフォルト: 100）
  config.max_tool_search_results = 100

  # tool_search の目標応答時間しきい値 ms（デフォルト: 1000）
  config.search_timeout_ms = 1000
end
```

---

## Dynamic Mode（動的ロードモード）

ツール数が多いとき、`tools/list` で全定義を返すとエージェントの起動時コンテキストを大量消費します。  
**Dynamic Mode** を有効にすると `tools/list` が `tool_search` と `call_proxy` の 2 ツールだけを返すようになり、エージェントは「検索 → 実行」のフローでツールを利用できます。

```
[エージェント]
  ↓ tools/list           → { tool_search, call_proxy } のみ返却
  ↓ tool_search(query)   → 関連ツールの name / description / inputSchema を返却
  ↓ call_proxy(name, …)  → 実際のツールを実行して結果を返却
```

### 有効化

```ruby
MonkeyMcp.configure do |config|
  config.tool_listing_mode = :dynamic
end
```

### tool_search — ツールを検索する

キーワードで登録済みツールを検索し、`name` / `description` / `inputSchema` を返します。

**引数**

| 引数 | 型 | 必須 | 説明 |
|------|-----|------|------|
| `query` | string | ✓ | 検索キーワード（空文字・空白のみは不可） |
| `filters.namespace` | string | - | コントローラパス prefix でフィルタ（例: `"api/v1"`）|
| `max_results` | integer | - | 最大返却件数（省略時は `max_search_results` 設定値）|

**例**

```bash
curl -s -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "tool_search",
      "arguments": {
        "query": "タスク一覧",
        "filters": { "namespace": "api/v1" },
        "max_results": 5
      }
    }
  }'
```

**レスポンス**（`content[0].text` を JSON パース）

```json
[
  {
    "name": "task_index",
    "description": "タスク一覧を取得する",
    "inputSchema": { "type": "object", "properties": {}, "required": [] }
  }
]
```

### call_proxy — ツールを実行する

`tool_search` で取得したツール名でツールを実行します。  
内部では通常の `tools/call` と同一のディスパッチを利用します。

**引数**

| 引数 | 型 | 必須 | 説明 |
|------|-----|------|------|
| `name` | string | ✓ | 実行するツール名（`tool_search` で取得したもの）|
| `arguments` | object | - | ツールに渡す引数 |

**例**

```bash
curl -s -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
      "name": "call_proxy",
      "arguments": {
        "name": "task_index",
        "arguments": {}
      }
    }
  }'
```

### エラーコード

| 状況 | エラーコード |
|---|---|
| `query` が空文字 / 空白のみ / string 以外 | `-32602 Invalid params` |
| `filters` が object 以外 | `-32602 Invalid params` |
| `max_results` が 0 以下または非整数 | `-32602 Invalid params` |
| `call_proxy.name` が string 以外・空・未登録 | `-32602 Invalid params` |
| `call_proxy.arguments` が object 以外 | `-32602 Invalid params` |

### 後方互換性

- `tool_listing_mode` のデフォルトは `:full`（既存動作を維持）
- `:dynamic` モードでも `tools/call` への直接ツール呼び出しは引き続き動作します

---

## MCP クライアント設定例

MCP クライアントごとに設定キー名は異なります。  
以下は `http://localhost:3000/mcp` を使う場合の代表例です。

```json
{
  "mcpServers": {
    "my_task_app": {
      "url": "http://localhost:3000/mcp"
    }
  }
}
```

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

> 実際のキー名（`mcpServers` / `servers` / `transport` など）はクライアント実装に合わせて読み替えてください。  
> 認証やリバースプロキシを挟む場合は、クライアント側の header 設定も追加してください。

---

## その他の設定

### development / test 環境での事前ロード

`eager_load: false` の環境では、`to_prepare` で対象コントローラを参照してください。

```ruby
Rails.application.config.to_prepare do
  Api::V1::TasksController
end
```

### 手動ルーティング（`auto_append_route = false` 時）

```ruby
# config/routes.rb
post "/mcp", to: "monkey_mcp/mcp#handle"
```

---

## トラブルシュート

- **ツールが `tools/list` に表示されない**  
  → 対象コントローラが `to_prepare` でロードされているか確認  
  → アクションが `config/routes.rb` に存在するか確認

- **`Unknown tool` が返る**  
  → ツール名の命名規則と `excluded_tool_methods` 設定を確認

- **`No route found for ...` が返る**  
  → `config/routes.rb` に対象アクションが定義されているか確認

- **ログイン必須アプリで `tools/call` が 302 / 401 になる**  
  → `ControllerHelpers` と `protect_with_internal_token!` の設定を確認

- **`tools/call` が 406 Not Acceptable または HTML を返す**  
  → アクションに `format.json` が定義されているか確認（「[アクションの JSON レスポンス要件](#アクションの-json-レスポンス要件)」を参照）

---

## 開発

```bash
git clone https://github.com/kuracchi-enj/monkey_mcp
cd monkey_mcp
rbenv exec bundle install
rbenv exec bundle exec rspec
```
