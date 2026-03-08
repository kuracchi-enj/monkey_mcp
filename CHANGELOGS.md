# CHANGELOGS

このファイルは `monkey_mcp` の主な変更履歴を記載します。

## v0.3.0 - 2026-03-08

### Changed
- `my_task_app` 連携の疎通確認を実施し、Dynamic Mode（`tool_search` / `call_proxy`）でのタスク取得が正常に動作することを確認。

## v0.2.0 - 2026-03-08

### Added
- Dynamic Mode を追加。
  - `config.tool_listing_mode = :dynamic` で `tools/list` の返却を `tool_search` / `call_proxy` の2ツールに最小化。
  - `tool_search` を追加（キーワード検索、`filters.namespace`、`max_results` 対応）。
  - `call_proxy` を追加（ツール名指定によるプロキシ実行）。
- 設定項目を拡張。
  - `max_search_results`（検索件数デフォルト）
  - `max_tool_search_results`（検索件数上限）
  - `search_timeout_ms`（目標応答しきい値）
- `ToolSearcher` クラスを追加（検索ロジックを分離）。
- Dynamic Mode に関するテストを追加（設定、検索、プロキシ、後方互換、予約語保護）。

### Changed
- `tools/list` の挙動をモードで切り替え可能に変更。
  - `:full`（デフォルト）: 従来どおり全ツールを返却
  - `:dynamic`: メタツール2件のみ返却
- 予約語ツール名 `tool_search` / `call_proxy` は常時登録ブロックに変更。
- `tool_search` / `call_proxy` の入力バリデーションを強化。
  - 不正パラメータ時に `-32602 Invalid params` を返却。
  - `tool_search.query` は非空文字列必須。
  - `tool_search.filters` は object 必須。
  - `call_proxy.name` は非空文字列必須。
  - `call_proxy.arguments` は object 必須。

### Fixed
- Dynamic Mode 実装時の入力型不正で例外化するケースを、JSON-RPCエラー返却へ修正。

### Docs
- README を全面拡充。
  - 概要、クイックスタート、JSONレスポンス要件、設定リファレンス
  - Dynamic Mode 詳細（`tool_search` / `call_proxy`）
  - MCPクライアント設定例、トラブルシュートを追加

## v0.1.0 - 2026-03-08

### Added
- 初回リリース。
- Rails アプリを MCP サーバとして公開する基本機能。
- `POST /mcp` エンドポイント（JSON-RPC 2.0）を提供。
- Rails コントローラアクションの MCP ツール自動登録（`MonkeyMcp::Toolable`）。
- `tools/list` / `tools/call` / `initialize` の基本実装。
- `SchemaBuilder` による `inputSchema` 自動生成。
- 内部トークンを使った内部サブリクエスト認証ヘルパー。
