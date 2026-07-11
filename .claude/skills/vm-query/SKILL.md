---
name: vm-query
description: VictoriaMetrics(8428) へ PromQL を実弾クエリする定型（instant/range/シリーズ探索。引数に PromQL 式または調べたい事柄を渡す）
---

VictoriaMetrics に PromQL を直接投げて結果を要約する。引数（`$ARGUMENTS`）が PromQL 式ならそのまま、自然言語なら式に翻訳してから実行する。

## 接続先

`VM_URL=http://$TARGET_HOST:8428`（`TARGET_HOST` は `.env` から。source 後は `unset DOCKER_HOST`）。
VM は Prometheus 互換 API を持つ: `/api/v1/query` / `/api/v1/query_range` / `/api/v1/series` / `/api/v1/label/<name>/values`。

## 定型

```bash
# instant クエリ
curl -s "$VM_URL/api/v1/query" --data-urlencode "query=<expr>" | python3 -m json.tool

# range クエリ（直近1時間・30s刻みの例）
curl -s "$VM_URL/api/v1/query_range" \
  --data-urlencode "query=<expr>" \
  --data-urlencode "start=$(date -u -d '1 hour ago' +%s)" \
  --data-urlencode "end=$(date -u +%s)" \
  --data-urlencode "step=30s" | python3 -m json.tool

# メトリクス名の探索（何があるか分からないとき）
curl -s "$VM_URL/api/v1/label/__name__/values" | python3 -c \
  "import sys,json; [print(n) for n in json.load(sys.stdin)['data'] if '<keyword>' in n]"
```

## このラボ固有の知見

- **⚠️ 検索遅延（search.latencyOffset）**: VM は直近 ~30 秒のサンプルを即時クエリに含めない。
  書き込み直後の検証で「無い」と即断しない——**60秒以上待つか、広い窓（[1h]等）+ max_over_time で照会**する
  （2026-07 の 016 検証でこの罠が「不達」の幻を作り、調査を大幅に迷走させた実績あり）

- **016 MCP メトリクス**: `mcp_tool_invocations_total{service=...,tool=...}` / duration histogram。
  `service` はデータポイント属性（bare 名: `prometheus` 等）、Resource 由来は `service_name` に化ける——`{service=...}` が空なら `service_name` も試す
- Prometheus(9090) は短期、VM(8428) が長期保存。**過去データの調査は VM に聞く**（プレースホルダ事件の実値復元は VM の過去データが決め手だった）
- 結果は生 JSON を貼らず、シリーズ数・代表ラベル・値を表で要約する

## 報告形式

実行した式・シリーズ数・代表値を簡潔に。`0 series` の場合はメトリクス名探索（`__name__` 部分一致）まで行ってから報告する。
