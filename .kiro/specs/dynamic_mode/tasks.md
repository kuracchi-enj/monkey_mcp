# 実装タスク：動的ロードモード（Dynamic Mode）

## Task 1: Configuration に dynamic mode 設定項目を追加

### 1.1 設定フィールドの追加
- `configuration.rb` に以下の `attr_accessor` を追加しデフォルト値を `initialize` で設定する
  - `tool_listing_mode`（デフォルト: `:full`）
  - `max_search_results`（デフォルト: `10`）
  - `max_tool_search_results`（デフォルト: `100`）
  - `search_timeout_ms`（デフォルト: `1000`）
  - `allow_meta_tool_override`（デフォルト: `false`）

_Requirements: 1.2, 4.1, 5.1, 5.3_

### 1.2 入力バリデーションの追加
- `tool_listing_mode=` のカスタム setter を定義し、`:full` / `:dynamic` 以外で `ArgumentError` を発生させる
- `max_search_results=`, `max_tool_search_results=`, `search_timeout_ms=` は 0 以下・nil・非整数で `ArgumentError`
- `allow_meta_tool_override=` は真偽値以外で `ArgumentError`

_Requirements: 1.3, 5.2, 5.4_

### 1.3 Configuration のユニットテスト
- 全フィールドのデフォルト値が正しいこと
- `:dynamic` を設定できること
- 各フィールドの不正値で `ArgumentError` が発生すること

_Requirements: 1.2, 1.3, 4.1, 5.2, 5.4_

---

## Task 2: 予約語保護（Toolable の変更）

### 2.1 予約語チェックの追加
- `toolable.rb` の `_register_mcp_tool` 内で、ツール名が `"tool_search"` または `"call_proxy"` の場合に動作を制御する
  - `MonkeyMcp.configuration.allow_meta_tool_override` が `false`（デフォルト）ならば登録をスキップし、警告ログを出力する
  - `true` の場合は登録を許可する（非推奨）

_Requirements: 1.4_

### 2.2 予約語保護のユニットテスト
- `allow_meta_tool_override: false` のとき、`tool_search` / `call_proxy` という名前のツールが Registry に登録されないこと
- `allow_meta_tool_override: true` のとき、登録されること

_Requirements: 1.4_

---

## Task 3: ToolSearcher クラスの実装

### 3.1 ToolSearcher クラスの骨格を作成
- `lib/monkey_mcp/tool_searcher.rb` を新規作成
- `initialize(tools)` を実装（`Registry.all` が返すツールハッシュの配列を受け取る）
- `search(query:, filters: {}, max_results: 10)` のシグネチャを定義
- `lib/monkey_mcp.rb`（またはエントリポイント）に `require` を追加

_Requirements: 2.1, NFR-2_

### 3.2 キーワードマッチングの実装
- `query` をスペース区切りでトークン化し、各ツールの `name` + `description` に対して出現回数をカウントしてスコア化
- スコア降順でソートし、スコア > 0 のツールを `max_results` 件返す
- 検索対象テキストは大文字小文字を区別しない（`downcase` 正規化）
- `query` は空でない前提（空文字チェックは `McpController#handle_tool_search` で行う）

_Requirements: 2.1, 2.3_

### 3.3 namespace フィルタの実装
- `filters[:namespace]` が指定されている場合、`tool[:controller]` を正規化（`"::"` → `"/"`, `"Controller"` 除去, `underscore`）した文字列が namespace で始まるツールのみを検索対象にする
- フィルタなしの場合はすべてのツールを対象にする

_Requirements: 2.4_

### 3.4 ToolSearcher のユニットテスト
- クエリにマッチするツールが返ること
- スコア降順でソートされること
- `max_results` 件を超えないこと
- `filters.namespace` でコントローラ namespace による絞り込みができること
- マッチしないクエリで空配列が返ること
- 大文字小文字を区別しないこと

_Requirements: 2.1, 2.3, 2.4_

---

## Task 4: McpController に dynamic mode を追加

### 4.1 `handle_tools_list` の分岐追加
- `MonkeyMcp.configuration.tool_listing_mode == :dynamic` の場合に `dynamic_meta_tools` を返す分岐を追加
- `:full` の場合は既存処理をそのまま呼ぶ（変更なし）

_Requirements: 1.1, 1.2, 2.7, 3.4_

### 4.2 `dynamic_meta_tools` の実装（private メソッド）
- `tool_search` と `call_proxy` の MCP ツール定義（name / description / inputSchema）を返す
- 各 inputSchema は design.md の定義に従って実装する

_Requirements: 1.1, 2.7, 3.4_

### 4.3 `dispatch_method` の拡張
- `tools/call` ハンドラ内で `params["name"]` が `"tool_search"` の場合は `handle_tool_search` へ委譲する
- `params["name"]` が `"call_proxy"` の場合は `handle_call_proxy` へ委譲する
- それ以外は既存の `handle_tools_call` へ委譲する（変更なし）

_Requirements: 2.1, 3.1_

### 4.4 `handle_tool_search` の実装（private メソッド）
- `arguments["query"]` を取得し、空文字・nil・空白のみなら `-32602` を返す
- `arguments["filters"]` を取得（nil の場合は `{}`、キーは Symbol に変換）
- `arguments["max_results"]` が指定されている場合、正の整数でなければ `-32602` を返す
- `max_results` を `arguments["max_results"] || configuration.max_search_results` で決定し、`1..configuration.max_tool_search_results` に clamp する
- `ToolSearcher.new(Registry.all).search(...)` を呼ぶ
- 結果を JSON 文字列化し `content: [{ type: "text", text: ... }]` 形式で返す

_Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.8, 6.1_

### 4.5 `handle_call_proxy` の実装（private メソッド）
- `arguments["name"]` を取得し、nil・空文字なら `-32602` を返す
- `arguments["arguments"]` を取得（nil の場合は `{}`）
- `Registry.find(tool_name)` → nil の場合 `-32602` を返す
- 既存の `internal_dispatch(tool, args)` を呼ぶ
- 既存の `handle_tools_call` と同一形式（`content[].type: "text"`, `isError` フラグ）でレスポンスを返す

_Requirements: 3.1, 3.2, 3.3, 6.1, NFR-3_

---

## Task 5: 統合テストと後方互換性の確認

### 5.1 McpController の dynamic mode 統合テスト
- `tool_listing_mode: :dynamic` のとき `tools/list` が `tool_search` と `call_proxy` のみ返すこと
- `tool_listing_mode: :full`（デフォルト）のとき既存の全ツール一覧が返ること
- dynamic モードで `tool_search` を呼び出してツールが検索できること
- dynamic モードで `tool_search` に空クエリを渡すと `-32602` が返ること
- dynamic モードで `tool_search` に不正な `max_results` を渡すと `-32602` が返ること
- dynamic モードで `call_proxy` を呼び出して正常に実行できること
- dynamic モードで `call_proxy` に未登録ツール名を渡すと `-32602` が返ること

_Requirements: 1.1, 1.2, 2.1, 2.6, 2.8, 3.1, 3.2, 4.1, 4.2, 4.3, 6.1_

### 5.2 後方互換性テスト
- `tool_listing_mode` 未設定（デフォルト）で既存の `tools/call` 直接呼び出しが動作すること
- `tool_listing_mode: :dynamic` でも `tools/call` 直接呼び出し（tool_search/call_proxy 以外）が動作すること
- `full` モードでは `tool_search` / `call_proxy` が `tools/list` に含まれないこと

_Requirements: 4.1, 4.2, 4.3_

### 5.3 パフォーマンステスト（オプション）
- ツール数 1000 件相当のモックデータで `tool_search` が `search_timeout_ms`（デフォルト 1000ms）以内に応答することを確認

_Requirements: NFR-1_

---

## Task 6: require 整備と README 更新

### 6.1 require の整備
- `lib/monkey_mcp.rb`（またはエントリポイント）に `tool_searcher.rb` の require を追加
- `bundle exec rake` 等で既存テストがすべてパスすることを確認

_Requirements: 4.1, 4.2_

### 6.2 README の更新
- `dynamic_mode` の設定方法（`tool_listing_mode: :dynamic` と各設定項目）を README に追記
- `tool_search` / `call_proxy` の使い方と応答例を記載

_Requirements: 5.1, 5.3_
