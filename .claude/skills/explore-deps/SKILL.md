---
name: explore-deps
description: 監視基盤サービスの依存関係グラフをMermaid形式で生成・循環依存チェック
---

Exploreエージェントに以下のタスクを委譲してください:

**タスク**: 監視基盤サービスの依存関係グラフ作成

thoroughness level: very thorough

**調査項目**:
1. `terraform/envs/local/` 配下のすべての `terragrunt.hcl` を読み込み
2. `dependency` ブロックを抽出・整理
3. `depends_on` や環境変数での参照を確認
4. 起動順序の妥当性をチェック

**報告形式**:
- Mermaid形式の依存関係図
- 循環依存の有無
- 推奨される起動順序
