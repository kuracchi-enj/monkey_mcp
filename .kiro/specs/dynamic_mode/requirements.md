# 要件定義：動的ロードモード（Dynamic Mode）

## 背景と目的

`monkey_mcp` は Rails のコントローラアクションを MCP ツールとして公開する gem である。アプリ規模が大きくなると `tools/list` が返すツール定義が膨大になり、エージェント起動直後からコンテキストを大量消費する問題が生じる（調査レポート参照）。

本機能は Skills の progressive disclosure の考え方を MCP に移植し、**「動的モード（dynamic mode）」** を導入することでこの問題を解決する。動的モードでは `tools/list` が返すツールを `tool_search` と `call_proxy` の 2 つに絞り込み、エージェントはまず検索してから必要なツールだけを呼び出せるようになる（案 C-1）。

---

## 要件一覧

### Requirement 1: ツール一覧表示モード設定

**1.1** WHEN ユーザーが `MonkeyMcp.configure` で `config.tool_listing_mode = :dynamic` を設定した場合、  
システムは `tools/list` の応答に `tool_search` および `call_proxy` の 2 ツール定義のみを含めなければならない。

**1.2** WHEN ユーザーが `config.tool_listing_mode` を設定しない（デフォルト）、または `:full` を設定した場合、  
システムは従来通りすべての登録済みツール定義を `tools/list` の応答に含めなければならない（後方互換性）。

**1.3** システムは `tool_listing_mode` の有効な値として `:full` および `:dynamic` のみを受け付けなければならない。それ以外の値が設定された場合はエラーを発生させなければならない。

**1.4** システムは `tool_search` および `call_proxy` を予約語として扱い、デフォルトではユーザー定義ツールとして登録できないようにしなければならない。  
ただし、互換性上の都合で上書きが必要な場合に限り、明示設定で上書きを許可できるようにしなければならない（非推奨）。

---

### Requirement 2: tool_search ツール

**2.1** WHEN `tools/call` で `tool_search` が呼び出され、`query` 文字列が渡された場合、  
システムは登録済みツールの中から `query` に関連性の高いツールを検索し、候補の一覧を返さなければならない。

**2.2** 返却される各候補ツールには以下の情報をすべて含めなければならない:
- `name`: ツール名
- `description`: ツール説明
- `inputSchema`: 入力スキーマ（既存の `SchemaBuilder` により生成されたもの）

**2.3** システムはデフォルトで BM25 に相当するキーワードマッチング（ツール名・description の部分一致）を検索アルゴリズムとして用いなければならない。

**2.4** WHEN `filters` パラメータが渡された場合、  
システムは `filters.namespace`（コントローラのパス prefix）による絞り込みをサポートしなければならない。

**2.5** システムは検索結果を最大 `max_results` 件に制限しなければならない。`max_results` のデフォルト値は 10 とし、設定で変更可能とする。

**2.6** WHEN `query` が空文字列の場合、  
システムは JSON-RPC エラー（code: -32602）を返さなければならない。

**2.7** `tool_search` は `tool_listing_mode` が `:full` のときは `tools/list` に含まれないが、  
`:dynamic` のときは常に `tools/list` に含まれなければならない。

**2.8** `tool_search` の `max_results` 引数は正の整数でなければならない。  
不正値（0 以下、非整数、nil以外の不正型）は JSON-RPC エラー（code: -32602）とし、上限を超える値は設定上限に丸める（clamp）か、エラーで拒否する動作を実装で統一しなければならない。

---

### Requirement 3: call_proxy ツール

**3.1** WHEN `tools/call` で `call_proxy` が呼び出され、`name` および `arguments` が渡された場合、  
システムは指定された名前のツールに対して既存の内部ディスパッチ（`internal_dispatch`）を実行し、その結果を返さなければならない。

**3.2** WHEN `name` に指定されたツールが登録されていない（`Registry.find` が nil を返す）場合、  
システムは JSON-RPC エラー（code: -32602）を返さなければならない。

**3.3** `call_proxy` のレスポンス形式は、既存の `tools/call` のレスポンス形式（`content[].type: "text"`, `isError` フラグ）と同一でなければならない。

**3.4** `call_proxy` は `tool_listing_mode` が `:full` のときは `tools/list` に含まれないが、  
`:dynamic` のときは常に `tools/list` に含まれなければならない。

---

### Requirement 4: 後方互換性

**4.1** `tool_listing_mode` のデフォルト値は `:full` でなければならない。既存の設定なしの環境では従来の挙動が変わらないことを保証する。

**4.2** `tool_listing_mode: :full` のとき、既存の `tools/call`（直接ツール呼び出し）の挙動は変わらないことを保証しなければならない。

**4.3** `tool_listing_mode: :dynamic` のときも、既存の `tools/call`（直接ツール呼び出し）は引き続き動作しなければならない。動的モードは `tools/list` の表示のみを変更し、実行パスを制限しない。

---

### Requirement 5: 設定インターフェース

**5.1** ユーザーは `MonkeyMcp.configure` ブロック内で以下のように設定できなければならない:

```ruby
MonkeyMcp.configure do |config|
  config.tool_listing_mode = :dynamic   # または :full（デフォルト）
  config.max_search_results = 10        # tool_search の最大返却件数（デフォルト: 10）
end
```

**5.2** `max_search_results` は正の整数でなければならない。不正な値（0 以下、nil、非整数）が設定された場合はエラーを発生させなければならない。

**5.3** ユーザーは `MonkeyMcp.configure` で以下を設定できなければならない:
- `allow_meta_tool_override`（デフォルト: `false`）  
  `true` の場合のみ、予約語 `tool_search` / `call_proxy` の上書きを許可する（非推奨）
- `max_tool_search_results`（デフォルト値は実装で定義）  
  `tool_search` の `max_results` 引数に対する上限値
- `search_timeout_ms`（デフォルト: `1000`）  
  `tool_search` の目標応答時間しきい値（非機能要件の設定値）

**5.4** `max_tool_search_results` および `search_timeout_ms` は正の整数でなければならない。不正値の場合はエラーを発生させなければならない。

---

### Requirement 6: JSON-RPC エラー方針

**6.1** 入力パラメータの不正（例: `tool_search.query` が空文字、`max_results` が不正型・不正値、`call_proxy.name` 不正）は JSON-RPC エラー `-32602`（Invalid params）で返さなければならない。

---

## 非機能要件

**NFR-1: パフォーマンス**  
`tool_search` の応答は、登録済みツール数が 1000 件以下の場合に `search_timeout_ms` 以内（デフォルト: 1000ms、Rails プロセス内計測）で返さなければならない。

**NFR-2: 拡張性**  
検索アルゴリズムは将来的にベクトル検索（embedding）に差し替え可能な設計とする（インターフェースを抽象化する）。ただし本機能の初期実装では BM25/キーワードマッチングのみ提供する。

**NFR-3: セキュリティ**  
`call_proxy` は `Registry` に登録済みのツールのみ実行できる。未登録ツールの実行はエラーとする。内部トークン（`MCP_INTERNAL_TOKEN`）は MCP プロトコルのレスポンスに含めない。

---

## 対象外（スコープ外）

- ベクトル検索（embedding）の実装（初期バージョン対象外。NFR-2 の拡張性として設計のみ考慮）
- ツール単位の RBAC/ABAC 認可（`call_proxy` のアクセス制御）
- MCP プロトコルバージョン 2025 系への対応
- `tool_search` / `call_proxy` の `:full` モードでの公開
